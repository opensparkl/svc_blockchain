%%% @copyright 2018 SPARKL Limited. All Rights Reserved.
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%% http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%% @author <ahfarrell@sparkl.com> Andrew Farrell
%%% @version {@version}
%%% @doc
%%%% Block processing gen_server.
%%% @end

-module(svc_blockchain_blocks).

-define(SERVER, ?MODULE).

-include("sse.hrl").
-include("sse_log.hrl").
-include("sse_cfg.hrl").
-include("sse_svc.hrl").
-include("sse_yaws.hrl").
-include("svc_blockchain.hrl").

%% ------------------------------------------------------------------
%% Exports
%% ------------------------------------------------------------------
-export([
  start/2,
  start_link/2]).

-behaviour(gen_server).
-export([
  init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-export([
  term_encode/1,
  get_subject_blockchains/1]).

%% ------------------------------------------------------------------
%% Imports.
%% ------------------------------------------------------------------
-import(
sse_cfg_util, [
  id_of/1,
  parent_of/1,
  ref_of/1
]).

%% ------------------------------------------------------------------
%% Definitions.
%% ------------------------------------------------------------------
-define(STATE, ?MODULE).
-record(?STATE, {
  chain_dir            :: string(),
  dets_open            :: fun((reference()) -> reference()),
  blocks_table_ref     :: reference(),
  pubkey               :: ed25519_pubkey(),
  privkey              :: ed25519_privkey(),
  class_timers         :: map(),
  block_fwd_interval   :: integer(),
  block_fwd_nodes      :: list(term()),
  block_receive_keys   :: list(string()),
  merkletree_urls      :: list(string()),
  merkletree_info      :: map()
}).

%% ------------------------------------------------------------------
%% API Functions
%% ------------------------------------------------------------------
-spec
start(ChainDir, BlockKeys) ->
  {ok, PId}
when
  ChainDir  :: string(),
  BlockKeys :: {ed25519_pubkey(), ed25519_privkey(), list(ed25519_pubkey())},
  PId       :: pid().

start(ChainDir, BlockKeys) ->
  InstanceSpec =
    #{
      id      => svc_blockchain_blocks,
      start   => {?MODULE, start_link, [ChainDir, BlockKeys]},
      restart => temporary,
      type    => worker},
  {ok, _Pid} =
    supervisor:start_child(svc_blockchain_sup, InstanceSpec).

%% @doc
%% Starts singleton chain block processor, returning the gen_server
%% pid if successful.
-spec
start_link(ChainDir, BlockKeys) ->
  {ok, PId}
when
  ChainDir  :: string(),
  BlockKeys :: {ed25519_pubkey(), ed25519_privkey(), list(ed25519_pubkey())},
  PId       :: pid().

start_link(ChainDir, BlockKeys) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, {ChainDir, BlockKeys}, []).


%% @doc
%% Encodes an erlang term into an mangled JSON equivalent, using a
%% bespoke pre-processor.
%%
-spec
term_encode(Term) ->
  B64Data
when
  Term   :: term(),
  B64Data :: string().

term_encode(Term) ->
  ?s(jsx:encode(
    pre_process(
      Term))).


%% @doc
%% Gets any sibling folders of a sequencer subject that have a blockchain.spec
%% defined for them.
%%
get_subject_blockchains(Subject) ->
  {ok, #?FOLDER{entries = Entries}} =
    sse_cfg:get_record_quick(
      parent_of(Subject)),

  Folders =
    [Entry || Entry = {Type, _Id} <- Entries,
      Type == folder],

  [{Folder, Spec} || {Folder, Spec} <-
    [{Folder, sse_cfg_prop:value(Folder,
      {?prop_blockchain_spec, ?attr_class})} || Folder <- Folders],
    Spec /= undefined].


%% ------------------------------------------------------------------
%% gen_server implementation
%% ------------------------------------------------------------------
init({ChainDir, BlockKeys}) ->
  % The time interval at which blocks are forwarded
  % (to other nodes or a public blockchain via a notify op)
  %
  BlockFwdInterval =
    application:get_env(
      svc_blockchain,
      block_fwd_interval,
      ?default_block_fwd_interval),

  % The nodes to forward blocks to, or notify ops to call with block hash.
  % [{node, Node}, ..., {notify, Username, SubjectPath}]
  %
  BlockFwdNodes =
    application:get_env(
      svc_blockchain,
      block_fwd_nodes,
      []),

  MerkleTreeUrls =
    application:get_env(
      svc_blockchain,
      merkletree_urls,
      []),

  ?DEBUG([
    {chain_dir, ChainDir},
    {block_fwd_interval, BlockFwdInterval},
    {block_fwd_nodes, BlockFwdNodes},
    {block_keys, BlockKeys}]),

  %% Ensure chain dir
  ChainLoc =
    filename:join(
      ChainDir, ?default_blockchain_dir),
  filelib:ensure_dir(
    ChainLoc),

  %% Dets Table for maintaining some minimal blockchain state,
  %% specifically the last chain block hash for each chain class.
  %%
  {ok, {BlocksTableRef, DetsOpen, _Node}} =
    svc_blockchain:create_table(?dets_prefix_blocks, ChainDir),

  %% Register Blockchain evh
  %%
  ok =
    sse_listen:add_handler_singleton(
      svc_blockchain_global_evh, [], []),

  {PubKey, PrivKey, BlockReceiveKeys} =
    BlockKeys,

  {ok, #?STATE{
    pubkey = PubKey,
    privkey = PrivKey,
    dets_open = DetsOpen,
    blocks_table_ref = BlocksTableRef,
    chain_dir = ChainDir,
    class_timers = #{},
    block_fwd_nodes = BlockFwdNodes,
    block_fwd_interval = BlockFwdInterval,
    block_receive_keys = BlockReceiveKeys,
    merkletree_info = #{},
    merkletree_urls = MerkleTreeUrls
  }}.


handle_call(_Request, _From, State) ->
  {reply, ok, State}.


handle_cast(
    {merkletree_info, MerkleTreeInfo},
    State) ->

  {noreply, State#?STATE{merkletree_info = MerkleTreeInfo}};

handle_cast(
    {process_txn_block, BlockInfo},
    State_) ->

  State =
    block_op(
      fun() ->
        process_txn_block(
          BlockInfo, State_)
      end),

  {noreply, State};

handle_cast(
    {receive_fwd_block, BlockInfo},
    State_) ->

  State =
    block_op(
      fun() ->
        receive_fwd_block(
          BlockInfo, State_)
      end),

  {noreply, State};

handle_cast(
    {send_fwd_block, BlockInfo},
    State_) ->

  State =
    block_op(
      fun() ->
        send_fwd_block(
          BlockInfo, State_)
      end),

  {noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.


handle_info(_Info, State) ->
  {noreply, State}.


terminate(
    _Reason,
    #?STATE{
      blocks_table_ref = DetsRef}) ->

  %% Close the blockchain state DETS file.
  ok =
    dets:close(DetsRef),
  ok.


code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% @doc
%% Perform some chain block processing, with error handling.
%%
block_op(BlockOp) ->
  try
    BlockOp()
  catch Class:Error ->
    ?LOG_ERROR(Class, Error)
  end.


%% @doc
%% Processes a chain block with running event hash, and last block info.
%%
-spec process_txn_block(
    BlockInfo, State_) ->
  State
when
  BlockInfo :: map(),
  State_    :: #?STATE{},
  State     :: #?STATE{}.

process_txn_block(
    BlockInfo,
    #?STATE{merkletree_info = MerkleTreeInfo} = State) ->

  #{
      event_hash := EventsHash,
      notifies := Notifies,
      txn_id := TxnId,
      owner := Owner,
      class := BlockClass,
      mix_info := MixInfo,
      first_event := FirstEvIdx,
      last_event := LastEvIdx
  } = BlockInfo,

  Block =
    [{?event_txn,
      ?u(TxnId)},
     {?block_eventshash,
      ?u(EventsHash)}],

   {MixId, MixDigest} =
    MixInfo,

  CompleteBlock =
    fun(ChainBlock_) ->
      ChainBlock_#{
        ?block_mixid => ?u(MixId),
        ?block_mixdigest => ?u(MixDigest),
        ?block_owner => ?u(Owner),
        ?block_firstev => FirstEvIdx,
        ?block_lastev => LastEvIdx,
        ?block_refs => MerkleTreeInfo
      }
    end,

  Config =
    #{block => Block,
      block_class => BlockClass,
      block_id => TxnId,
      notifies => Notifies,
      fun_complete_block => CompleteBlock},

  complete_chain_block(
    Config,
    State#?STATE{merkletree_info = #{}}).


%% @doc
%% Sends block to registered forwarding nodes and/or notifies.
%%
-spec send_fwd_block(
    BlockClass, State_) ->
  State
when
  BlockClass :: string(),
  State_     :: #?STATE{},
  State      :: #?STATE{}.

send_fwd_block(
    BlockClass,
    #?STATE{
      blocks_table_ref = BlocksTableRef_,
      block_fwd_nodes = BlockFwdNodes,
      merkletree_urls = MerkleTreeUrls,
      class_timers = ClassTimers_} = State_) ->

  BlocksTableRef =
    if
      BlockFwdNodes == [] ->
        BlocksTableRef_;

      true ->
        send_fwd_block_(BlockClass, State_)
    end,

  if
    MerkleTreeUrls == [] ->
      ok;

    true ->
      send_merkle_urls(
        MerkleTreeUrls, BlockClass, BlocksTableRef)
  end,

  ClassTimers =
    maps:remove(BlockClass, ClassTimers_),

  State_#?STATE{
    class_timers = ClassTimers,
    blocks_table_ref = BlocksTableRef}.


send_fwd_block_(
    BlockClass,
    #?STATE{
      pubkey = PubKey,
      privkey = PrivKey,
      dets_open = DetsOpen,
      blocks_table_ref = BlocksTableRef_,
      block_fwd_nodes = BlockFwdNodes}) ->

  BlocksTableRef =
    DetsOpen(BlocksTableRef_),

  [{BlockClass, {LastBlockId, LastBlockHash}}] =
    dets:lookup(BlocksTableRef, BlockClass),

  BlockTriple =
    svc_blockchain_crypto:digest(
      ?u(BlockClass ++ ?s(LastBlockHash) ++ LastBlockId)),

  BlockSigned =
    try
      svc_blockchain_crypto:sign(
        BlockTriple, ?u(PrivKey))
    catch
      _:_ ->
        ?u(?UNDEFINED_STRING)
    end,

  BlockInfo =
    #{block_writer => atom_to_list(node()),
      block_class => BlockClass,
      block_hash => LastBlockHash,
      block_id => LastBlockId,
      block_signed => BlockSigned,
      block_key => PubKey},

  ?DEBUG(
    [{blockinfo, BlockInfo}]),

  lists:foreach(
    fun
      ({node, Node}) ->
        gen_server:cast(
          {svc_blockchain_blocks, Node},
          {receive_fwd_block, BlockInfo});

      ({notify, Username, SubjectPath}) ->
        Fields =
          [{?block_hash, LastBlockHash}],
        try
          sse_svc_cmd:notify(
            Username, SubjectPath, Fields)
        catch
          ?BADMATCH({error, not_found}) ->
            ok
        end
    end,
    BlockFwdNodes),

  BlocksTableRef.


send_merkle_urls(Urls,  BlockClass, BlocksTableRef) ->
  spawn(
    fun() ->
      [{BlockClass, {LastBlockId, LastBlockHash}}] =
        dets:lookup(BlocksTableRef, BlockClass),

      ?DEBUG([
        {tableref, BlocksTableRef},
        {blockclass, BlockClass},
        {lastblockhash, LastBlockHash},
        {lastblockid, LastBlockId}]),

      MerkleTreeInfo =
        svc_blockchain_yapp:forward_mt_hosts(
          Urls, LastBlockHash),

      gen_server:cast(
        svc_blockchain_blocks, {merkletree_info, MerkleTreeInfo})
    end).


%% @doc
%% Receives forwarding block and includes in chain.
%%
-spec receive_fwd_block(
    BlockInfo, State_) ->
  State
when
  BlockInfo :: map(),
  State_    :: #?STATE{},
  State     :: #?STATE{}.

receive_fwd_block(
    BlockInfo,
    #?STATE{
      block_receive_keys =  BlockReceiveKeys} = State_) ->

  #{block_writer := BlockWriter,
    block_class := BlockClass,
    block_hash := BlockHash,
    block_id := BlockId,
    block_signed := BlockSigned,
    block_key := BlockKey} = BlockInfo,

  ?DEBUG([
    {blockinfo, BlockInfo}]),

  true =
    lists:member(BlockKey, BlockReceiveKeys),

  BlockTriple =
    svc_blockchain_crypto:digest(
      ?u(BlockClass ++ ?s(BlockHash) ++ BlockId)),

  Verify =
    try
      svc_blockchain_crypto:verify(
        BlockTriple, BlockSigned, ?u(BlockKey))
    catch
      _:_ ->
        false
    end,

  if
    Verify ->
      Block =
        [{?block_hash, ?u(BlockHash)},
          {?block_src, ?u(BlockWriter)}],

      CompleteBlock =
        fun(ChainBlock) ->
          ChainBlock
        end,

      Config =
        BlockInfo#{
          block => Block,
          notifies => [],
          fun_complete_block => CompleteBlock},

      complete_chain_block(
        Config,
        State_);

    true ->
      State_
  end.


%% @doc
%% Helper function used to wrap the processing of a chain block.
%%
-spec complete_chain_block(
    Config, State_) ->
  State
when
  Config :: map(),
  State_    :: #?STATE{},
  State     :: #?STATE{}.

complete_chain_block(
    Config,
    #?STATE{
      pubkey = PubKey,
      privkey = PrivKey,
      dets_open = DetsOpen,
      blocks_table_ref = BlocksTableRef_,
      block_fwd_interval = BlockFwdInterval,
      block_fwd_nodes = BlockFwdNodes,
      merkletree_urls = MerkleTreeUrls,
      class_timers = ClassTimers_} = State_) ->

  #{block := Block_,
    block_class := BlockClass,
    block_id := BlockId,
    notifies := Notifies,
    fun_complete_block := CompleteBlock} = Config,

  BlocksTableRef =
    DetsOpen(BlocksTableRef_),

  {LastBlockId, LastBlockHash} =
    case dets:lookup(BlocksTableRef, BlockClass) of
      [] ->
        {?UNDEFINED_STRING, ?UNDEFINED_STRING};

      [{BlockClass, BlockDetails}] ->
        BlockDetails
    end,

  ?DEBUG([
    {tableref, BlocksTableRef},
    {blockclass, BlockClass},
    {lastblockhash, LastBlockHash},
    {lastblockid, LastBlockId}]),

  Block =
    maps:from_list(
      [{?block_lastid, ?u(LastBlockId)},
      {?block_lasthash, ?u(LastBlockHash)} | Block_]),

  BlockIdx =
    erlang:unique_integer([positive, monotonic]),

  ChainBlock__ =
    Block#{
      ?block_key => ?u(PubKey),
      ?block_class => ?u(BlockClass),
      ?block_id => ?u(BlockId),
      ?block_writer => ?u(atom_to_list(node())),
      ?block_idx => BlockIdx},

  ChainBlock_ =
    CompleteBlock(ChainBlock__),

  BlockEnc =
    term_encode(
      ChainBlock_),

  ?DEBUG([
    {blockenc, BlockEnc}]),

  BlockHash =
    svc_blockchain_crypto:digest(?u(BlockEnc)),

  BlockSigned =
    try
      svc_blockchain_crypto:sign(BlockHash, ?u(PrivKey))
    catch
      _:_ ->
        ?u(?UNDEFINED_STRING)
    end,

  ChainBlock =
    ChainBlock_#{?block_signed => BlockSigned},

  ?DEBUG([
    {chain_block, ChainBlock}]),

  dets:insert(BlocksTableRef, {BlockClass, {BlockId, BlockHash}}),

  {ok, ChainBlockJSON} =
    sse_json:encode(
      ChainBlock),

  ok =
    svc_blockchain_local:write_block(ChainBlock, ChainBlockJSON),

  NotifyFields =
    [{?mix_field_chainblock,  ChainBlockJSON}],

  lists:foreach(
    fun({Username, NotifyPath}) ->
      sse_svc_cmd:notify(Username, NotifyPath, NotifyFields)
    end, Notifies),

  ClassTimers =
    add_class_timer(
      BlockFwdNodes,
      MerkleTreeUrls,
      BlockClass,
      ClassTimers_,
      BlockFwdInterval),

  State_#?STATE{
    class_timers = ClassTimers,
    blocks_table_ref = BlocksTableRef}.


%% @doc
%% Adds a timer for a particular blockchain class.  On expiry, last block
%% for blockchain class is to sent to forwarding nodes.
%%
-spec add_class_timer(
    BlockFwdNodes, MerkleTreeUrls, BlockClass, ClassTimers_, BlockFwdInterval) ->
  ClassTimers
when
  BlockFwdNodes    :: list(term()),
  MerkleTreeUrls   :: list(string()),
  BlockClass       :: string(),
  ClassTimers_     :: map(),
  BlockFwdInterval :: integer(),
  ClassTimers      :: map().

add_class_timer(
    BlockFwdNodes, MerkleTreeUrls, BlockClass, ClassTimers, BlockFwdInterval) ->

  DoNothing = BlockFwdNodes == [] andalso MerkleTreeUrls == [],

  if
    DoNothing ->
      ClassTimers;

    true ->
      case maps:get(
          BlockClass, ClassTimers, undefined) of

        undefined ->
          {ok, TimerRef} =
            timer:apply_after(
              BlockFwdInterval,
              gen_server,
              cast,
              [self(), {send_fwd_block, BlockClass}]),
          maps:put(BlockClass, TimerRef, ClassTimers);

        _ClassTimer ->
          ClassTimers
      end
  end.


%% @doc
%% Pre-processes term with the intention of using the result for
%% generating a digest.  As this needs to be repeatable, we must
%% derive a canonical represntation, converting
%% maps into lists (with an ordering over their keys), etc.
%%
pre_process(true) ->
  true;

pre_process(false) ->
  false;

pre_process(undefined) ->
  <<"null">>;

pre_process([]) ->
  [];

pre_process(Atom)
    when is_atom(Atom) ->
  ?u(Atom);

pre_process(Tuple)
    when is_tuple(Tuple) ->
  [pre_process(Data) || Data <- tuple_to_list(Tuple)];

pre_process(List)
    when is_list(List) ->

  case io_lib:printable_unicode_list(List) of
    true ->
      ?u(List);

    false ->
      [pre_process(V) || V <- List]
  end;

pre_process(Map) when is_map(Map) ->
  [[pre_process(K),
    pre_process(maps:get(K, Map))] ||
    K <- lists:sort(maps:keys(Map))];

pre_process(Other) ->
  Other.
