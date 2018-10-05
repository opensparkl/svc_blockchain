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
%%% Principal svc_blockchain gen_server started by supervisor
%%% on application start.
%%% @end

-module(svc_blockchain).

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
  start_link/0,
  get_blockfuns/0,
  create_table/2,
  start_ext_svc/1,
  start_ext_svc/2,
  retract_token/2
]).

-behaviour(sse).
-export([
  info/0]).

-behaviour(gen_server).
-export([
  init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

%% ------------------------------------------------------------------
%% Definitions.
%% ------------------------------------------------------------------
-define(STATE, ?MODULE).
-record(?STATE, {
  block_count          :: integer(),
  txn_count            :: integer(),
  chain_dir            :: string(),
  block_receive_keys   :: list(string()),
  pubkey               :: ed25519_pubkey(),
  privkey              :: ed25519_privkey()
}).


%% ------------------------------------------------------------------
%% API Functions
%% ------------------------------------------------------------------
%% @doc
%% Supervisor start callback
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc
%% sse behaviour callback.
-spec
info() ->
  undefined | struct().

info() ->
  #{block_count := BlockCount,
    txn_count := TxnCount,
    chain_dir := ChainDir} =
    gen_server:call(?MODULE, state),

  Attrs = [
    {block_count, BlockCount},
    {txn_count, TxnCount},
    {chain_dir, ChainDir}],

  {?MODULE, Attrs}.


%% @doc
%% Gets cast and call functions appropriate to whether
%% block processing is done locally or remotely.
%%
get_blockfuns() ->
  case
    application:get_env(
      svc_blockchain, block_procnode, undefined) of

    undefined ->
      Cast =
        fun(Module, Message) ->
          ok =
            gen_server:cast(Module, Message)
        end,
      Call =
        fun(Module, Message) ->
          gen_server:call(Module, Message)
        end,
      {undefined, Cast, Call};

    BlockProcNode ->
      Cast =
        fun(Module, Message) ->
          ok =
            gen_server:cast({Module, BlockProcNode}, Message)
        end,
      Call =
        fun(Module, Message) ->
          gen_server:call({Module, BlockProcNode}, Message)
        end,
      {BlockProcNode, Cast, Call}
  end.


%% @doc
%% Creates 'get table' closure - used whenever we want to
%% record chain information using DETS.
%% Closure checks that table file is still there and if not
%% recreates it.
%%
-spec create_table(Prefix, ChainDir) ->
  {ok, {TableRef, GetTableFun, Node}}
when
  Prefix      :: string(),
  ChainDir    :: string(),
  TableRef    :: reference(),
  GetTableFun :: fun((reference()) -> reference()),
  Node        :: string().

create_table(Prefix, ChainDir) ->
  %% Where am I?
  %%
  Node_ =
    atom_to_list(
      node()),

  [Node | _Host] =
    string:tokens(Node_, "@"),

  DetsTable_ =
    lists:flatten(
      io_lib:format("~s_~s.dets", [Node, Prefix])),

  DetsTable =
    filename:join([ChainDir, DetsTable_]),

  GetTableFun =
    fun(TableRef) ->
      get_table(TableRef, DetsTable)
    end,

  TableRef = get_table(DetsTable),

  {ok, {TableRef, GetTableFun, Node}}.


%% @doc
%% Starts external service for purpose of
%% connecting as an svc_rest instance.
%%
-spec
start_ext_svc(Config) ->
  ok
  when
  Config :: map().

start_ext_svc(Config) ->
  start_ext_svc(Config, ?post_start_delay).

start_ext_svc(Config, Sleep) ->
  #{
    envs := Envs,
    user := Username,
    pypath := PyPath,
    svcpath := SvcPath,
    module := Module} = Config,

  {ok, User} =
    sse_cfg:get_user(Username),

  Unique =
    ?s(erlang:unique_integer(
      [positive, monotonic])),
  Node =
    ?s(node()),

  TokenName =
    lists:flatten(
      io_lib:format(
        "tmp.~s.~s",
        [Node, Unique])),

  % Generate a time-limited access token.
  {Secret, #?PROP{
      name = PropName} = Prop} =
    sse_cfg_pwd:token_prop(
      TokenName),
  ok =
    sse_cfg:store_props(
      User, [Prop]),
  ?DEBUG(
    [{added_token, PropName}]),

  {ok, _TRef} =
    timer:apply_after(
      ?default_svc_token_timeout,
      svc_blockchain,
      retract_token,
      [PropName, User]),

  {ok, Hostname} =
    sse_inet_util:get_sse_address_composed(),
  {ok, {HttpPort, _HttpsPort}} =
    sse_inet_util:get_sse_port(),

  HttpUrl =
    lists:flatten(
      io_lib:format(
        "http://~s:~s",
        [Hostname, ?s(HttpPort)])),
  ?DEBUG(
    [{http_url, HttpUrl}]),

  Command = lists:flatten(
    io_lib:format(
      "~s bash -c '(sparkl close || true) &&  sparkl connect ~s && "
      "sparkl login -t ~s ~s ~s && "
      "sparkl service --path ~s ~s ~s > /tmp/out 2>&1' &",
      [Envs, HttpUrl, TokenName, Username, Secret, PyPath, SvcPath, Module])),
  ?DEBUG(
    [{start_ext_svc, Command}]),
  Result =
    os:cmd(Command),
  ?DEBUG(
    [{result, Result}]),

  % Requires a small delay to allow connection.
  % Calling solicits should also retry for extra resilience.
  timer:sleep(Sleep),
  ok.


%% ------------------------------------------------------------------
%% gen_server implementation
%% ------------------------------------------------------------------
init(Args) ->
  ?TRAP_EXIT,
  try
    init_(Args)
  catch
    Class: Error ->
      ?LOG_ERROR(
        Class, Error)
  end.

init_(_Args) ->
  {BlockProc, _Cast, _Call} =
    get_blockfuns(),

  if
    BlockProc == undefined ->

      % We are a local processor.
      {ok, HomeDir} =
        init:get_argument(home),

      % Base directory for local blockchain/events.
      ChainDir =
        application:get_env(
          svc_blockchain,
          chain_dir,
          filename:join(
            HomeDir, ?default_blockchain_dir)),

      BlockReceiveKeys =
        application:get_env(
          svc_blockchain,
          block_receive_keys,
          []),

      %% Event and chain block signing key pair
      %%
      {ok, {PubKey, PrivKey}} =
        application:get_env(
          svc_blockchain,
          sign_keypair),

      %% Start blockchain processing
      ok =
        gen_server:cast(svc_blockchain, start_processing),

      {ok, #?STATE{
        block_count = 0,
        txn_count = 0,
        chain_dir = ChainDir,
        block_receive_keys = BlockReceiveKeys,
        pubkey = PubKey,
        privkey = PrivKey
      }};

    true ->

      % No local processing.
      {ok, undefined}
  end.


%% @doc
%% Return gen_server state as a map.
%%
handle_call(state, _From, State) ->
  #?STATE{
    block_count = TxnCount,
    txn_count = BlockCount,
    chain_dir = ChainDir
  } = State,

  StateMap = #{
    block_count => TxnCount,
    txn_count => BlockCount,
    chain_dir => ChainDir
  },

  {reply, StateMap, State};

handle_call(
    {start_blockchain_events, StartConfig},
    _From,
    #?STATE{
      block_receive_keys = BlockRecieveKeys,
      pubkey = BlockPubKey} = State) ->

  #{pubkey := PubKey,
    txnid := TxnId,
    txnid_sig := TxnIdSigned} = StartConfig,

  true =
    BlockPubKey == PubKey orelse
      lists:member(PubKey, BlockRecieveKeys),

  Verify =
    try
      svc_blockchain_crypto:verify(
        ?u(TxnId), ?u(TxnIdSigned), ?u(PubKey))
    catch
      _:_ ->
        false
    end,

  true =
    Verify,

  Reply =
    svc_blockchain_events:start(
      StartConfig),

  {reply, Reply, State};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.


%% @doc
%% Start blockchain processing.
%%
handle_cast(
    start_processing, #?STATE{
      pubkey = PubKey,
      privkey = PrivKey,
      chain_dir = ChainDir,
      block_receive_keys = BlockReceiveKeys} = State) ->

  {ok, BlockchainProc} =
    svc_blockchain_blocks:start(
      ChainDir, {PubKey, PrivKey, BlockReceiveKeys}),

  ?DEBUG([
    {blockchain_proc, BlockchainProc}]),

  {ok, BlockchainLocal} =
    svc_blockchain_local:start(ChainDir),

  ?DEBUG([
    {blockchain_local, BlockchainLocal}]),

  MerkleTimeout =
    application:get_env(
      svc_blockchain,
      merkletree_interval,
      ?default_merkletree_interval),

  if
    MerkleTimeout == -1 ->
      ok;

    true ->
      {ok, BlockchainMerkle} =
        svc_blockchain_merkle:start(
          ChainDir, {PubKey, PrivKey, BlockReceiveKeys}),

      ?DEBUG([
        {blockchain_merkle, BlockchainMerkle}])
  end,

  {noreply, State};

%% @doc
%% Increase count of blocks processed by this node.
%%
handle_cast(
    incr_blockcount,
    #?STATE{
      block_count = BlockCount} = State) ->

  ?DEBUG([
    {incr_blockcount, BlockCount + 1}]),

  {noreply, State#?STATE{
    block_count = BlockCount + 1}};

%% @doc
%% Increase count of transactions processed by this node.
%%
handle_cast(
    incr_txncount,
    #?STATE{
      txn_count = TxnCount} = State) ->

  ?DEBUG([
    {incr_txncount, TxnCount + 1}]),

  {noreply, State#?STATE{
    txn_count = TxnCount + 1}};

handle_cast(_Msg, State) ->
  {noreply, State}.


handle_info(_Info, State) ->
  {noreply, State}.


terminate(
    _Reason,
    #?STATE{}) ->
  ok.


code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% Gets DETS table reference.
%% Check DETS table file is present, and
%% if so uses that. Otherwise, creates table file.
%%
-spec get_table(Table) ->
  TableRef
when
  Table    :: string(),
  TableRef :: reference().


get_table(Table) ->
  Action =
    fun() ->
      {ok, TableRef} =
        dets:open_file(Table),
      TableRef
    end,
  get_table_(Action, Table).


-spec get_table(TableRef_, Table) ->
  TableRef
when
  Table     :: string(),
  TableRef_ :: reference(),
  TableRef  :: reference().


get_table(TableRef, Table) ->
  Action =
    fun() ->
      TableRef
    end,
  get_table_(Action, Table).


get_table_(Action, Table) ->
  ?DEBUG([
    {table, Table}]),

  case filelib:is_file(Table) of
    true ->
      Action();

    false ->
      {ok, TableRef} =
        dets:open_file(
          make_ref(), [{type, set}, {file, Table}, {repair, true}]),
      TableRef
  end.


%% @doc
%% Retracts temp access token with propname, PropName
%%
-spec
retract_token(PropName, User) ->
  ok
when
  PropName :: string(),
  User     :: user().

retract_token(PropName, User) ->
  ok =
    sse_cfg:remove_props(
      User, [PropName]),
  ?DEBUG(
    [{retracted_token, PropName}]),
  ok.
