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
%%%% Merkle tree processing gen_server.
%%% @end

-module(svc_blockchain_merkle).

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
  push_hash/1,
  get_proof/1,
  get_proofhash/1,
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

%% ------------------------------------------------------------------
%% Imports.
%% ------------------------------------------------------------------
-import(
 sse_cfg_util, [
  ref_of/1
]).

%% ------------------------------------------------------------------
%% Definitions.
%% ------------------------------------------------------------------
-define(STATE, ?MODULE).
-record(?STATE, {
  chain_dir            :: string(),
  backup_table_ref     :: reference(),
  pubkey               :: ed25519_pubkey(),
  privkey              :: ed25519_privkey(),
  block_receive_keys   :: list(string()),
  set_process_timer    :: fun(() -> {ok, ref()}),
  set_quorum_timer     :: fun(() -> {ok, ref()}),
  set_backup_timer     :: fun(() -> {ok, ref()}),
  backup_epoch         :: integer(),
  merkletree_fwds      :: list({string(), string()})
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
  ?DEBUG([
    {ChainDir, BlockKeys}]),

  InstanceSpec =
    #{
      id      => svc_blockchain_merkle,
      start   => {?MODULE, start_link, [ChainDir, BlockKeys]},
      restart => temporary,
      type    => worker},
  {ok, Pid} =
    supervisor:start_child(svc_blockchain_sup, InstanceSpec),

  ?DEBUG([
    {node, node()},
    {registered, registered()}]),

  {ok, Pid}.

%% @doc
%% Starts singleton merkle tree processor, returning the gen_server
%% pid if successful.
-spec
start_link(ChainDir, BlockKeys) ->
  {ok, PId}
  when
  ChainDir  :: string(),
  BlockKeys :: {ed25519_pubkey(), ed25519_privkey(), list(ed25519_pubkey())},
  PId       :: pid().

start_link(ChainDir, BlockKeys) ->
  gen_server:start_link(
    {local, ?SERVER}, ?MODULE, {ChainDir, BlockKeys}, []).


%% @doc
%% Push hash to merkle tree record
push_hash(Hash) ->
  gen_server:call(
    svc_blockchain_merkle, {hash, Hash}).

%% @doc
%% Get proof of signature
get_proof(Signed) ->
  gen_server:call(
    svc_blockchain_merkle, {proof, Signed}).

%% @doc
%% Get proof of original hash
get_proofhash(Hash) ->
  gen_server:call(
    svc_blockchain_merkle, {proofhash, Hash}).


%% ------------------------------------------------------------------
%% gen_server implementation
%% ------------------------------------------------------------------
init({ChainDir, BlockKeys}) ->
  ?DEBUG([
    {chain_dir, ChainDir},
    {block_keys, BlockKeys}]),

  %% Dets Table file path for back-up of merkle-tree state.
  %%
  {ok, {BackupTableRef, _DetsOpen, Node}} =
    svc_blockchain:create_table(
      ?dets_prefix_merkle, ChainDir),

  %% Create initial state records.
  ok =
    create_init_records(),

  {PubKey, PrivKey, BlockReceiveKeys} =
    BlockKeys,

  MerkleTimeout =
    application:get_env(
      svc_blockchain,
      merkletree_interval,
      ?default_merkletree_interval),

  MerkleQuorum =
    application:get_env(
      svc_blockchain,
      merkletree_quorum,
      ?default_merkletree_quorum),

  MerkleTreeFwds =
    application:get_env(
      svc_blockchain,
      merkletree_fwds,
      []),

  %% Each svc_blockchain_merkle periodically competes to generate the latest merkle tree
  SetProcessTimer =
    new_process_timer(MerkleTimeout),

  %% Each svc_blockchain_merkle must add to the quorum view of what latest epoch they have.
  %% Timer will cease its periodic trigger when quorum is achieved.
  SetQuorumTimer =
    new_quorum_timer(MerkleTimeout, MerkleQuorum),
  {ok, _QuorumTimerRef} =
    SetQuorumTimer(),

  %% Each svc_blockchain_merkle backs-up to DETS.  This is only started once quorum is achieved.
  SetBackupTimer =
    new_backup_timer(MerkleTimeout),

  %% Recover prior state stored in DETS, as back-up
  {ok, BackupEpoch} =
    recover_dets(BackupTableRef, Node),

  State = #?STATE{
    pubkey = PubKey,
    privkey = PrivKey,
    chain_dir = ChainDir,
    backup_table_ref = BackupTableRef,
    block_receive_keys = BlockReceiveKeys,
    set_process_timer =  SetProcessTimer,
    set_quorum_timer = SetQuorumTimer,
    set_backup_timer = SetBackupTimer,
    backup_epoch = BackupEpoch,
    merkletree_fwds = MerkleTreeFwds
  },

  ?DEBUG([
    {state, State}]),
  {ok, State}.


handle_call(
    {hash, Hash},
    _From,
    #?STATE{
      pubkey = PubKey,
      privkey = PrivKey} = State) ->

  ?DEBUG([
    {hash, Hash}]),

  Signed =
    add_pending_hash(Hash, PrivKey),

  Reply =
    {ok, {Signed, PubKey}},

  ?DEBUG([
    {signed, Signed}]),
  {reply, Reply, State};

handle_call(
    {proofhash, Hash},
    _From,
    #?STATE{
      pubkey = PubKey,
      privkey = PrivKey} = State) ->

  Signed =
    ?s(svc_blockchain_crypto:sign(
      ?u(Hash), PrivKey)),

  {reply, handle_get_proof(Signed, PubKey, PrivKey), State};


handle_call(
    {proof, Signed},
    _From,
    #?STATE{
      pubkey = PubKey,
      privkey = PrivKey} = State) ->

  {reply, handle_get_proof(Signed, PubKey, PrivKey), State};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(
    process_merkle_tree,
    #?STATE{
      set_process_timer = SetProcessTimer,
      merkletree_fwds = MerkleTreeFwds,
      pubkey = PubKey,
      backup_table_ref = BackupTableRef} = State) ->

  {ok, HashesRecord_} =
    sse_cfg:get_resource(
      sse_blockchain_merkle_hashes, ?hashes_record_key),

  #sse_blockchain_merkle_hashes{
    epoch = Epoch
  } = HashesRecord_,

  ?DEBUG([
    {epoch, Epoch}]),

  % If we have not achieved quorum view on what epoch we are
  % then we cannot proceed.
  if
    Epoch == undefined ->
      ok;

    true ->
      process_merkle_tree(MerkleTreeFwds, BackupTableRef, PubKey)
  end,

  {ok, _TimerRef} =
    SetProcessTimer(),

  {noreply, State};

handle_cast(
    {determine_quorum, MerkleQuorum},
    #?STATE{
      set_quorum_timer = SetQuorumTimer,
      set_backup_timer = SetBackupTimer,
      set_process_timer = SetProcessTimer} = State) ->

  ?DEBUG([
    {merkle_quorum, MerkleQuorum}]),

  {ok, QuorumRecord_} =
    sse_cfg:get_resource(
      sse_blockchain_merkle_quorum, ?quorum_record_key),

  #sse_blockchain_merkle_quorum{
    quorum = Quorum
  } = QuorumRecord_,

  ?DEBUG([
    {quorum, Quorum}]),

  if
    length(Quorum) >= MerkleQuorum ->
      MaxEpoch =
        lists:max(
          [Epoch || {_Node, Epoch} <- Quorum]),

      update_hashes_epoch(MaxEpoch),

      {ok, _ProcessTimerRef} =
        SetProcessTimer(),

      {ok, _BackupTimerRef} =
        SetBackupTimer();

    true ->
      {ok, _TimerRef} =
        SetQuorumTimer()
  end,
  {noreply, State};

handle_cast(
    merkle_backup,
    #?STATE{
      backup_table_ref = BackupTableRef,
      backup_epoch = BackupEpoch} = State) ->

  spawn(
    fun() ->
      update_dets(BackupTableRef, BackupEpoch)
    end),
  {noreply, State};

handle_cast(
    {set_backup_epoch, BackupEpoch__},
    #?STATE{
      backup_epoch = BackupEpoch_,
      set_backup_timer = SetBackupTimer} = State_) ->

  BackupEpoch =
    if
      BackupEpoch_ == BackupEpoch__ ->
        {ok, _TimerRef} =
          SetBackupTimer(),
        BackupEpoch_;

      true ->
        ok = gen_server:cast(self(), merkle_backup),
        BackupEpoch_ + 1
  end,

  State = State_#?STATE{
    backup_epoch = BackupEpoch},
  {noreply, State};

handle_cast(Msg, State) ->
  ?ERROR(
    [{msg, Msg},
     {state, State}]),
  {noreply, State}.


handle_info(_Info, State) ->
  {noreply, State}.


terminate(
    _Reason,
    #?STATE{
      backup_table_ref = BackupTableRef}) ->

  %% Close the blockchain proof DETS file.
  ok =
    dets:close(BackupTableRef),
  ok.


code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% @doc
%% Common get proof of hash logic.
%%
handle_get_proof(Signed_, PubKey, PrivKey) ->
  try
    ?DEBUG([
      {get_proof, Signed_}]),

    {Signed, Proof, Epoch} =
      get_proof(Signed_, PrivKey),

    ?DEBUG([
      {epoch, Epoch},
      {signed, Signed},
      {proof, Proof}]),

    {ok, {Signed, Proof, PubKey, Epoch}}
  catch
    ?BADMATCH(_Term) ->
      % Check to see if it is in the pending queue.
      {ok, HashesRecord_} =
        sse_cfg:get_resource(
          sse_blockchain_merkle_hashes, ?hashes_record_key),

      #sse_blockchain_merkle_hashes{
        hashes = Hashes
      } = HashesRecord_,

      case proplists:get_value(Signed_, Hashes) of
        undefined ->
          {error, not_found};

        _Hash ->
          {error, pending}
      end
  end.


%% @doc
%% Goes through the keys of the back-up dets table, which are hashes
%% to get associated proofs.  Constructs a proof record which is pushed to
%% mnesia if not already there.   Also updates a quorum record 'latest'
%% with the node's view of what the next epoch is.
%%
-spec recover_dets(TableRef, Node) ->
  {ok, NextEpoch}
when
  TableRef       :: reference(),
  Node           :: string(),
  NextEpoch      :: integer().

recover_dets(TableRef, Node) ->
  First =
    dets:first(TableRef),
  ?DEBUG([
    {first, First}]),

  NextEpoch =
    case First of
      '$end_of_table' ->
        0;

      First ->
        recover_dets_(
          TableRef, First, 0)
    end,
  assert_quorum_record(
    Node, NextEpoch),
  {ok, NextEpoch}.


-spec recover_dets_(TableRef, DetsKey, NextEpoch_) ->
  NextEpoch
when
  DetsKey      :: term(),
  TableRef     :: reference(),
  NextEpoch_   :: integer(),
  NextEpoch    :: integer().

recover_dets_(
    TableRef, {sse_blockchain_merkle_proof, HashKey}, NextEpoch) ->

  [{{sse_blockchain_merkle_proof, HashKey},
      #sse_blockchain_merkle_proof{} = ProofRecord}] =
    dets:lookup(TableRef, {sse_blockchain_merkle_proof, HashKey}),

  AddProofRecord =
    fun(Record) ->
      #sse_blockchain_merkle_proof{
        epoch = Epoch_
      } = Record,

      case Epoch_ of
        undefined ->
          ProofRecord;

        _Present ->
          undefined
      end
    end,

  update_resource(
    AddProofRecord, #sse_blockchain_merkle_proof{}, HashKey),

  Next =
    dets:next(TableRef, {sse_blockchain_merkle_proof, HashKey}),
  ?DEBUG([{debug, Next}]),

  case dets:next(TableRef, {sse_blockchain_merkle_proof, HashKey}) of
    '$end_of_table' ->
      NextEpoch;

    Key ->
      recover_dets_(TableRef, Key, NextEpoch)
  end;

recover_dets_(
    TableRef, {sse_blockchain_merkle_epoch, Epoch}, NextEpoch_) ->

  [{{sse_blockchain_merkle_epoch, Epoch},
      #sse_blockchain_merkle_epoch{} = EpochRecord}] =
    dets:lookup(TableRef, {sse_blockchain_merkle_epoch, Epoch}),

  AddEpochRecord =
    fun(Record) ->
      #sse_blockchain_merkle_epoch{
        epoch = Epoch_
      } = Record,

      case Epoch_ of
        undefined ->
          EpochRecord;

        _Present ->
          undefined
      end
    end,

  update_resource(
    AddEpochRecord, #sse_blockchain_merkle_epoch{}, Epoch),

  Epoch1 =
    Epoch + 1,

  NextEpoch =
    if
      Epoch1 > NextEpoch_ ->
        Epoch1;

      true ->
        NextEpoch_
    end,


  case dets:next(
      TableRef, {sse_blockchain_merkle_epoch, Epoch}) of
    '$end_of_table' ->
      NextEpoch;

    Key ->
      recover_dets_(TableRef, Key, NextEpoch)
  end.


%% @doc
%% Asserts a quorum record, where an individual node records its view of what the
%% next epoch record is.
%%
-spec
assert_quorum_record(Node, NextEpoch) ->
  ok
when
  Node      :: string(),
  NextEpoch :: integer().

assert_quorum_record(Node, NextEpoch) ->
  % The default epoch record doubles as the quorum record.  This node will declare
  % what it considers the next epoch to be.
  AssertQuorumRecord =
    fun(Record) ->
      #sse_blockchain_merkle_quorum{
        quorum = Quorum} = Record,

      Record#sse_blockchain_merkle_quorum{
        quorum = [{Node, NextEpoch} | Quorum]
      }
    end,

  update_resource(
    AssertQuorumRecord, #sse_blockchain_merkle_quorum{}, ?quorum_record_key).


%% @doc
%% Update proofs and epoch record in dets, some of which may have come from other nodes.
%%
-spec update_dets(BackupTableRef, BackupEpoch) ->
  ok
when
  BackupTableRef :: reference(),
  BackupEpoch   :: integer().

update_dets(BackupTableRef, BackupEpoch_) ->
  GetEpochRecord =
    fun() ->
      sse_cfg:get_resource(sse_blockchain_merkle_epoch, BackupEpoch_)
    end,

  BackupEpoch =
    case
      lock_trans(
        sse_blockchain_merkle_epoch, self(), GetEpochRecord)
    of
      {error, not_found} ->
        BackupEpoch_;

      {ok, EpochRecord} ->
        #sse_blockchain_merkle_epoch{
          hashes = Hashes
        } = EpochRecord,

        ?DEBUG([
          {record, EpochRecord}]),

        % Update DETS
        DetsEntry = dets:lookup(
          BackupTableRef,
          {sse_blockchain_merkle_epoch, BackupEpoch_}),

        if
          DetsEntry == [] ->
            ok =
              dets:insert(
                BackupTableRef,
                {{sse_blockchain_merkle_epoch, BackupEpoch_},
                  EpochRecord}),

            lists:foreach(
              fun(Hash_) ->
                {ok, ProofRecord} =
                  sse_cfg:get_resource(sse_blockchain_merkle_proof, Hash_),

                ?DEBUG([
                  {proofrecord, ProofRecord}]),

                ok =
                  dets:insert(
                    BackupTableRef,
                    {{sse_blockchain_merkle_proof, Hash_},
                      ProofRecord})
              end,
              Hashes),
            ok;

          true ->    % Already have records
            ok
        end,
        BackupEpoch_ + 1
    end,
  ok = gen_server:cast(
    self(), {set_backup_epoch, BackupEpoch}).


%% @doc
%% Sets timer for processing merkle tree.  We add a random offset to the time
%% period to ensure that different blockchain nodes trigger at different offsets.
%%
set_process_timer(MerkleTimeout) ->
  {ok, TimerRef} =
    timer:apply_after(
      % Apply a rand to create differing timeout across svc_blockchains
      MerkleTimeout + trunc(rand:uniform() * 1000),
      gen_server,
      cast,
      [self(), process_merkle_tree]),
  ?DEBUG([
    {timerref, TimerRef}]),
  {ok, TimerRef}.


new_process_timer(MerkleTimeout) ->
  fun() ->
    {ok, _TimerRef} =
      set_process_timer(MerkleTimeout)
  end.


%% @doc
%% Sets timer for deciding whether quorum has been achieved
%%
set_quorum_timer(MerkleTimeout, MerkleQuorum) ->
  {ok, TimerRef} =
    timer:apply_after(
      MerkleTimeout,
      gen_server,
      cast,
      [self(), {determine_quorum, MerkleQuorum}]),
  ?DEBUG([
    {timerref, TimerRef}]),
  {ok, TimerRef}.


new_quorum_timer(MerkleTimeout, MerkleQuorum) ->
  fun() ->
    {ok, _TimerRef} =
      set_quorum_timer(MerkleTimeout, MerkleQuorum)
  end.


%% @doc
%% Sets timer for deciding whether quorum has been achieved
%%
set_backup_timer(MerkleTimeout) ->
  {ok, TimerRef} =
    timer:apply_after(
      MerkleTimeout,
      gen_server,
      cast,
      [self(), merkle_backup]),
  ?DEBUG([
    {timerref, TimerRef}]),
  {ok, TimerRef}.


new_backup_timer(MerkleTimeout) ->
  fun() ->
    {ok, _TimerRef} =
      set_backup_timer(MerkleTimeout)
  end.


%% @doc
%% Gets merkle proof and signs it.
%%
-spec
get_proof(Signed_, PrivKey) ->
  {Signed, Proof, Epoch}
when
  Signed_ :: ed25519_signature(),
  PrivKey :: ed25519_privkey(),
  Signed  :: ed25519_signature(),
  Proof   :: list(merkle_tree_node()),
  Epoch   :: integer().

get_proof(Signed_, PrivKey) ->
  {ok, #sse_blockchain_merkle_proof{
    proof = Proof_,
    epoch = Epoch}} = sse_cfg:get_resource(sse_blockchain_merkle_proof, Signed_),

  ?DEBUG([
    {proof_, Proof_},
    {epoch, Epoch}]),

  Proof =
    lists:foldl(
      fun(El, Acc) ->
        case Acc of
          "" ->
            El;

          Acc ->
            Acc ++ ", " ++ El
        end
      end,
      "",
      Proof_),

  ?DEBUG([
    {proof, Proof}]),

  Signed =
    ?s(svc_blockchain_crypto:sign(
      ?u("\"" ++ Proof ++ "\""), PrivKey)),

  ?DEBUG([
    {signed, Signed},
    {proof, Proof},
    {epoch, Epoch}]),

  {Signed, Proof, Epoch}.


%% @doc
%% Creates a resource record.
%%
-spec
create_init_record(EmptyRecord, Key) ->
  ok
when
  EmptyRecord :: term(),
  Key         :: term().

create_init_record(EmptyRecord, Key) ->
  ?DEBUG([
    {empty_record,
      EmptyRecord}]),

  Resource =
    element(1, EmptyRecord),
  CreateRecord =
    fun() ->
      case sse_cfg:get_resource(Resource, Key) of
        {error, not_found} ->
          {ok, _ResRef} =
            sse_cfg:put_resource(
              Resource, Key, EmptyRecord, []),
          ok;

        {ok, _Record} ->
          ok
      end
    end,
  ok =
    lock_trans(
      Resource, self(), CreateRecord).


%% @doc
%% Creates initial state records.
%%
-spec
create_init_records() ->
  ok.

create_init_records() ->
  ok =
    create_init_record(
      #sse_blockchain_merkle_hashes{}, ?hashes_record_key),
  ok =
    create_init_record(
      #sse_blockchain_merkle_quorum{}, ?quorum_record_key).


%% @doc
%% Update pending hashes record with epoch
%%
-spec
update_hashes_epoch(Epoch) ->
  {ok, #sse_blockchain_merkle_hashes{}}
when
  Epoch :: integer().

update_hashes_epoch(Epoch) ->
  UpdateRecord =
    fun(HashesRecord_) ->
      HashesRecord =
        HashesRecord_#sse_blockchain_merkle_hashes{
          epoch = Epoch
        },
      ?DEBUG([
        {hashes_record, HashesRecord}]),
      HashesRecord
    end,

  update_resource(
    UpdateRecord, #sse_blockchain_merkle_hashes{}, ?hashes_record_key).


%% @doc
%% Adds hash to list of pending hashes.  What gets added is in fact the
%% hash obtained from signing the hash with the node's private key.
%%
-spec
add_pending_hash(Hash, PrivKey) ->
  Signed
when
  Hash    :: sha256_double_hash(),
  PrivKey :: ed25519_privkey(),
  Signed  :: ed25519_signature().

add_pending_hash(Hash, PrivKey) ->
  Signed =
    ?s(svc_blockchain_crypto:sign(?u(Hash), PrivKey)),

  UpdateRecord =
    fun(Record) ->
      #sse_blockchain_merkle_hashes{
          hashes = Hashes
      } = Record,

      Record#sse_blockchain_merkle_hashes{
        hashes = [{Signed, Hash} | Hashes]
      }
    end,

  update_resource(
    UpdateRecord, #sse_blockchain_merkle_hashes{}, ?hashes_record_key),

  Signed.


%% @doc
%% Processes the merkle tree into a set of proofs, one per pending hash.
%% Will try and record the proofs in mnesia, but will need to get in first!
%%
-spec
process_merkle_tree(MerkleTreeFwds, Backup, PubKey) ->
  ok | {ok, term()}
when
  MerkleTreeFwds :: list(term()),
  Backup :: reference(),
  PubKey :: ed25519_pubkey().

process_merkle_tree(MerkleTreeFwds, Backup, PubKey) ->
  {ok, HashRecord} =
    sse_cfg:get_resource(sse_blockchain_merkle_hashes, ?hashes_record_key),

  #sse_blockchain_merkle_hashes{
    hashes = Hashes,
    epoch = Epoch
  } = HashRecord,

  ?DEBUG([
    {hashrecord, HashRecord}]),

  %% Construct the candidate merkle proofs
  {ok, Proofs, RootHash_} =
    process_merkle_tree(Hashes),

  ?DEBUG([
    {proofs, Proofs}]),

  RecordMerkleProofs =
    fun(Record_) ->
      #sse_blockchain_merkle_hashes{
        hashes = Hashes_,
        epoch = Epoch_
      } = Record_,

      case Epoch_ of
        Epoch ->
          Hashes__ =
            sets:to_list(
              sets:subtract(
                sets:from_list(Hashes_),
                sets:from_list(Hashes))),

          ?DEBUG([
            {curhashes, Hashes},
            {remhashes, Hashes__}]),

          Epoch__ = Epoch_ + 1,
          Record = Record_#sse_blockchain_merkle_hashes{
            hashes = Hashes__,
            epoch = Epoch__
          },

          ?DEBUG([
            {hashrecord, Record}]),

          RootHash =
            if
              RootHash_ == <<>> ->
                svc_blockchain_crypto:digest(
                  ?u(?s(Epoch)));

              true ->
                RootHash_
            end,

          AssertEpochRecord =
            fun(Record__) ->
              Record__#sse_blockchain_merkle_epoch{
                epoch = Epoch,
                hashes = Hashes,
                pubkey = PubKey,
                root = RootHash
              }
            end,

          {ok, EpochRecord} =
            update_resource(
              AssertEpochRecord, #sse_blockchain_merkle_epoch{}, Epoch),

          ok =
            dets:insert(
              Backup,
              {{sse_blockchain_merkle_epoch, Epoch}, EpochRecord}),

          % Store merkle proofs.
          ok =
            store_merkle_proofs(
              Proofs, Backup, Epoch),

          post_tree_details(
            MerkleTreeFwds, Backup, Epoch_),
          Record;

        _Epoch1 ->
          undefined
      end
    end,

  update_resource(
    RecordMerkleProofs, #sse_blockchain_merkle_hashes{}, ?hashes_record_key).


%% @doc
%% Processes a list of values (hash or sigs) into a merkle hash tree.
-spec
process_merkle_tree(Hashes, Tree_) ->
  Tree
when
  Hashes :: list(merkle_tree_node()),
  Tree_  :: list(list(merkle_tree_node())),
  Tree   :: list(list(merkle_tree_node())).

process_merkle_tree([], Tree) ->
  Tree;

process_merkle_tree([RootHash], Tree) ->
  [[RootHash] | Tree];

process_merkle_tree(Hashes_, Tree) ->
  ?DEBUG([
    {hashes, Hashes_}]),
  Hashes__ =
    case length(Hashes_) rem 2 of
      0 ->
        Hashes_;

      1 ->
        lists:append(Hashes_, [?UNDEFINED_STRING])
    end,

  Hashes =
    process_merkle_hashes(Hashes__),
  process_merkle_tree(Hashes, [Hashes__ | Tree]).


%% @doc
%% Constructs a set of merkle proof records for a list of hashes.
%% First constructs a merkle tree from the list of hashes,
%% and then constructs the proof (which is the path through the merkle tree)
%% for each hash.
%%
-spec
process_merkle_tree(Hashes) ->
  {ok, Proofs, RootHash}
when
  Hashes   :: list(merkle_tree_node()),
  Proofs   :: list(list(merkle_tree_node())),
  RootHash :: sha256_double_hash().

process_merkle_tree(Hashes_) ->
  ?DEBUG([
    {hashes, Hashes_}]),
  % The sigs are in fact the 'hashes' we use for the leaves of the merkle tree.
  %
  Hashes__ =
    [Sig || {Sig, _OrgHash} <- Hashes_],
  ?DEBUG([
    {hashes, Hashes__}]),

  % The following covers the simple case of where there is one leaf hash
  % We need at least two!  Odd numbers greater than one are covered by the
  % general clause below, which uses 'rem 2' test.
  %
  Hashes =
    if
      length(Hashes__) == 1 ->
        [H] = Hashes__,
        [H, ?UNDEFINED_STRING];

      true ->
        Hashes__
    end,

  Tree =
    lists:reverse(
      process_merkle_tree(Hashes, [])),

  RootHash =
    if
      Tree == [] ->
        "";

      true ->
        [RootHash_] = lists:last(Tree),
        RootHash_
    end,

  ?DEBUG([
    {tree, Tree},
    {root, RootHash}]),

  {ok, Proofs} =
    process_merkle_proofs(Tree),
  ?DEBUG([
    {proofs, Proofs}]),

  {ok, Proofs, ?u(RootHash)}.


%% @doc
%% Processes a level of a merkle tree under construction (from leaves to root).
%% The set of hashes from the prior level is combined to form of a new level
%% that is half the size of the prior level.
%%
-spec
process_merkle_hashes(Hashes_) ->
  Hashes
when
  Hashes_  :: list(merkle_tree_node()),
  Hashes   :: list(merkle_tree_node()).

process_merkle_hashes(Hashes__) ->
  lists:reverse(
    process_merkle_hashes(Hashes__, [])).

process_merkle_hashes([], Hashes) ->
  Hashes;

process_merkle_hashes([Hash1, Hash2 | Hashes__], Hashes) ->
  ?DEBUG([
    {hash1, Hash1},
    {hash2, Hash2}]),

  process_merkle_hashes(
    Hashes__,
    [?s(svc_blockchain_crypto:digest(?u(Hash1 ++ Hash2))) | Hashes]).


%% @doc
%% Extracts a proof for each leaf hash from a merkle tree.
%%
-spec
process_merkle_proofs(Tree) ->
  {ok, Proofs}
when
  Tree   :: list(list(merkle_tree_node())),
  Proofs :: list(list(merkle_tree_node())).

process_merkle_proofs([]) ->
  {ok, []};

process_merkle_proofs(Tree) ->
  [Leaves | _Tree] = Tree,
  process_merkle_proofs_leaves(Leaves, 1, Tree, []).

process_merkle_proofs_leaves([], _Idx, _Tree, Proofs) ->
  {ok, Proofs};

process_merkle_proofs_leaves([?UNDEFINED_STRING | _Ignore], _Idx, _Tree, Proofs) ->
  {ok, Proofs};

process_merkle_proofs_leaves([Hash | Hashes], Idx, Tree, Proofs) ->
  Proof =
    process_merkle_proofs_leaf(Tree, Idx, [Hash]),
  process_merkle_proofs_leaves(Hashes, Idx + 1, Tree, [Proof | Proofs]).


process_merkle_proofs_leaf([[RootLevel]], _Idx, Proof) ->
  lists:reverse([RootLevel | Proof]);

process_merkle_proofs_leaf([TreeLevel | Tree], Idx_, Proof) ->
  PairIdx =
    Idx_ + 2 * (Idx_ rem 2) - 1,

  ?DEBUG([
    {treelevel, TreeLevel},
    {tree, Tree},
    {idx_, Idx_},
    {proof, Proof},
    {pairidx, PairIdx}]),

  Hash =
    lists:nth(
      PairIdx, TreeLevel),
  Idx =
    trunc((Idx_ + 1) / 2),  % add 1 to retain numbering from 1

  process_merkle_proofs_leaf(
    Tree, Idx, [Hash | Proof]).


%% @doc
%% Stores merkle proofs in mnesia
%%
-spec
store_merkle_proofs(Proofs, Backup, Epoch) ->
  ok
when
  Proofs :: list(list(term())),
  Backup :: reference(),
  Epoch  :: integer().

store_merkle_proofs([], _Backup, _Epoch) ->
  ok;

store_merkle_proofs(
    [[Hash | Proof] | Proofs], Backup, Epoch) ->

  AddProofRecord =
    fun(Record) ->
      Record#sse_blockchain_merkle_proof{
        proof = Proof,
        epoch = Epoch
      }
    end,

  {ok, ProofRecord} =
    update_resource(
      AddProofRecord, #sse_blockchain_merkle_proof{}, Hash),
  ok =
    dets:insert(
      Backup, {{sse_blockchain_merkle_proof, Hash}, ProofRecord}),
  ok =
    store_merkle_proofs(Proofs, Backup, Epoch).


%%% @doc
%%% Post details of the latest merkle tree to services such as Twitter.
%%%
-spec
post_tree_details(MerkleTreeFwds, Backup, Epoch) ->
  ok
when
  MerkleTreeFwds :: list(term()),
  Backup         :: reference(),
  Epoch          :: integer().

post_tree_details(MerkleTreeFwds, Backup, Epoch) ->
  spawn(
    fun() ->
      {ok, #sse_blockchain_merkle_epoch{root = RootHash}} =
        sse_cfg:get_resource(sse_blockchain_merkle_epoch, Epoch),

      Timestamp =
        sse_util:timestamp_6dp_str(),

      Message =
        ?u(lists:flatten(
          io_lib:format(
            "Time: ~s, Hash: ~s, See: https://saas.sparkl.com/svc_blockchain/epoch/~w ",
            [Timestamp, ?s(RootHash), Epoch]))),

      Urls =
        lists:foldl(
          fun
            ({Username, SubjectPath, Fields_, EpochPeriod, Type}, Acc) ->
              Post = Epoch rem EpochPeriod == 0 andalso
                (RootHash /= <<>> orelse not lists:member(?mt_param_hash, Fields_)),
              if
                Post->
                  Fields__ =
                    [{?mt_param_status, Message},
                      {?mt_param_hash, RootHash}],
                  Fields =
                    [{Name, Value} ||
                      {Name, Value} <- Fields__, lists:member(Name, Fields_)],

                  try
                    ?DEBUG([
                      {username, Username},
                      {solicit, SubjectPath},
                      {indata, Fields}]),
                    {ok, {?REPLY_OK, ResponseValues_}} =
                      sse_svc_cmd:solicit(
                        Username, SubjectPath, Fields),

                    ResponseValues =
                      maps:from_list(ResponseValues_),
                    ?DEBUG([
                      {outdata, ResponseValues}]),

                    Url =
                      maps:get(?mt_param_url, ResponseValues),

                    [{Type, Url} | Acc]

                  catch
                    C:E ->
                      ?DEBUG([
                        {class, C},
                        {error, E}]),
                      Acc
                  end;
                true ->
                  Acc
              end
          end,
          [],
          MerkleTreeFwds),

      % We also need to assert records for each epoch
      AssertEpochRecord =
        fun(Record) ->
          Record#sse_blockchain_merkle_epoch{
            timestamp = Timestamp,
            urls = Urls
          }
        end,

      {ok, EpochRecord} =
        update_resource(
          AssertEpochRecord, #sse_blockchain_merkle_epoch{}, Epoch),

      ok =
        dets:insert(
          Backup, {{sse_blockchain_merkle_epoch, Epoch},
            EpochRecord})
    end),
  ok.


%% @doc
%% Updates a resource in an appropriate resource lock.
%%
-spec
update_resource(Func, EmptyRecord, Key) ->
  ok | {ok, Record}
when
  Func        :: fun((term()) -> term()),
  EmptyRecord :: term(),
  Record      :: term(),
  Key         :: term().

update_resource(Func, EmptyRecord, Key) ->
  Resource =
    element(1, EmptyRecord),

  ?DEBUG([
    {resource, Resource},
    {key, Key}]),

  Action =
    fun() ->
      Record__ =
        case sse_cfg:get_resource(Resource, Key) of
          {error, not_found} ->
            EmptyRecord;

          {ok, Record_} ->
            Record_
        end,

      Record =
        Func(Record__),

      ?DEBUG([
        {record, Record}]),

      if
        Record == undefined ->
          ok;

        true ->
          {ok, _ResRef} =
            sse_cfg:put_resource(Resource, Key, Record, []),
          {ok, Record}
      end
    end,

  lock_trans(
    Resource, self(), Action).


%% @doc
%% Applies serialized access to a resource based on
%% resource name (Resource). If current access is not
%% PId, then PId waits.
%%
-spec
lock_trans(Resource, PId, Action) ->
  Any
when
  Resource :: atom(),
  PId      :: pid(),
  Action   :: fun(),
  Any      :: term().

lock_trans(Resource, PId, Action) ->
  global:trans(
    {Resource, PId}, Action).
