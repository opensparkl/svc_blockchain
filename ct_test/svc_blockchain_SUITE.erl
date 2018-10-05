%%% @copyright (c) 2018 SPARKL Limited. All Rights Reserved.
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
%%% @doc
%%% Common_test suite for svc_blockchain.
%%%

-module(svc_blockchain_SUITE).

-include("sse.hrl").
-include("sse_cfg.hrl").
-include("sse_svc.hrl").
-include("sse_listen.hrl").
-include("svc_blockchain.hrl").
-include_lib("common_test/include/ct.hrl").

-compile(export_all).

-define(NODE1, 'ct_svc_blockchain1@127.0.0.1').
-define(NODE2, 'ct_svc_blockchain2@127.0.0.1').
-define(NODE3, 'ct_svc_blockchain3@127.0.0.1').
-define(NODE4, 'ct_svc_blockchain4@127.0.0.1').

-define(NODES_SIMPLE,
  {nodes, [{"nodes/sse1", ?NODE1}]}).
-define(NODES_MERKLE, {nodes, [
  {"nodes/sse2", ?NODE2},
  {"nodes/sse3", ?NODE3}]}).
-define(NODES_IOT, {nodes, [
  {"nodes/sse2", ?NODE2},
  {"nodes/sse3", ?NODE3},
  {"nodes/sse4", ?NODE4}]}).

-define(ADMIN_USER, "admin@localhost").
-define(TEST_USER, "test@sparkl.com").

-define(NODE1_STR, atom_to_list(?NODE1)).
-define(NODE2_STR, atom_to_list(?NODE2)).
-define(NODE3_STR, atom_to_list(?NODE3)).
-define(NODE4_STR, atom_to_list(?NODE4)).

-define(TESTEVENTS, "events").
-define(TESTBLOCKCHAIN, "blockchain").
-define(TESTLOCAL, "local").

-define(LOCAL_PREFIX, "l_").

-define(CTTEST_DATA_DIR, "../ct_test/svc_blockchain_SUITE_data").
-define(CLEAN_CHAINS_SCRIPT, "scripts/clean/clean_chains").
-define(TESTSCRIPTS_LOC, "scripts/ct_test").
-define(SCRIPTS_LOC, "scripts").
-define(EXAMPLES_LOC, "examples").
-define(NODE2_LOC, "nodes/sse2").
-define(NODE3_LOC, "nodes/sse3").
-define(NODE2_MERKLE_DETS, "ct_svc_blockchain2_merkle.dets").
-define(NODE3_MERKLE_DETS, "ct_svc_blockchain3_merkle.dets").

-define(BLOCKCHAIN_SIMPLE, "BlockchainSimple.xml").
-define(BLOCKCHAIN_STREAMING, "BlockchainStreaming.xml").
-define(BLOCKCHAIN_IOT, "BlockchainIOT.xml").
-define(LIB_FOLDER, "Lib.xml").
-define(BLOCKCYPHER, "lib.blockcypher.xml").
-define(PRIMES, "Primes.xml").
-define(COUNT_SCRIPT, "count.py").
-define(CHECK_SCRIPT, "check.py").
-define(STREAM_SCRIPT, "stream.sh").
-define(STREAMOUT_LOG, "/tmp/streamout.log").
-define(STREAMOUT_GREP, "'BLOCK PASSED'").
-define(DETS_FILE, "ct_svc_blockchain1_merkle.dets").
-define(PRIMES_PATH, "Scratch/Primes/Mix/CheckPrime").
-define(NODE1_BLOCKCHAIN, "local/blockchain/ct_svc_blockchain1@127.0.0.1/blockchain").
-define(NODE1_ADMIN_EVENTS, "local/events/" ?ADMIN_USER).
-define(EPOCH_URL, "http://localhost:8002/svc_blockchain/epoch/").
-define(PROOF_URL, "http://localhost:8002/svc_blockchain/proof/").

-import(ct_node_util, [
  init/1,
  start/1,
  rpc/4,
  import/5,
  resolve/2,
  retrieve/2,
  stop/1,
  solicit/4]).

-import(sse_cfg_util, [
  mix_of/1,
  ref_of/1,
  id_of/1]).


suite() -> [
  {timetrap, {hours, 1.5}}].


all() -> [
  {group, blockchain_events},
  {group, blockchain_local},
  {group, blockchain_streaming},
  {group, blockchain_merkle}
].


groups() -> [
  {blockchain_events, [], [
    test_blockchain_events
  ]},
  {blockchain_local, [], [
    test_blockchain_local
  ]},
  {blockchain_streaming, [], [
    test_blockchain_streaming
  ]},
  {blockchain_iot, [], [
    test_iot
  ]},
  {blockchain_merkle, [], [
    test_merkle
  ]}
].


init_per_suite(Config) ->
  {ok, HomeDir} =
    init:get_argument(home),
  ChainDir =
    filename:join(HomeDir, ?default_blockchain_dir),
  [{chain_dir, ChainDir} | Config].


end_per_suite(_Config) ->
  ok.


init_per_group(Group, Config) ->
  case os:type() of
    {unix, linux} ->
      ok =
        init_per_group_(Group, Config);

    _Other ->
      {skip, "Skipping Blockchain tests based on platform"}
  end.

init_per_group_(blockchain_iot, Config) ->
  clean_chainstores(),
  init_sparkl(
    [?NODES_IOT | Config]),

  AppDir =
    code:priv_dir(svc_blockchain),

  ok =
    import(Config,
      filename:join([AppDir, ?CTTEST_DATA_DIR, ?EXAMPLES_LOC, ?BLOCKCHAIN_IOT]),
      ?NODE2,
      ?ADMIN_USER,
      "/Scratch"),

  ok =
    import(Config,
      filename:join([AppDir, ?EXAMPLES_LOC, ?BLOCKCHAIN_SIMPLE]),
      ?NODE2,
      ?ADMIN_USER,
      "/Scratch/BlockchainIOT");

init_per_group_(blockchain_merkle, Config) ->
  clean_chainstores(),

  ChainDir =
    proplists:get_value(chain_dir, Config),
  AppDir =
    code:priv_dir(svc_blockchain),

  MerkleDETS2_Src =
    filename:join([AppDir, ?CTTEST_DATA_DIR, ?NODE2_LOC, ?NODE2_MERKLE_DETS]),
  MerkleDETS2_Dest =
    filename:join([ChainDir, ?NODE2_MERKLE_DETS]),
  {ok, _Bytes2} =
    file:copy(MerkleDETS2_Src, MerkleDETS2_Dest),

  MerkleDETS3_Src =
    filename:join([AppDir, ?CTTEST_DATA_DIR, ?NODE3_LOC, ?NODE3_MERKLE_DETS]),
  MerkleDETS3_Dest =
    filename:join([ChainDir, ?NODE3_MERKLE_DETS]),
  {ok, _Bytes3} =
    file:copy(MerkleDETS3_Src, MerkleDETS3_Dest),

  init_sparkl(
    [?NODES_MERKLE | Config]);

init_per_group_(Group, Config) ->
  ok =
    init_group_default(Group, Config, true).

init_group_default(Group, Config) ->
  ok =
    init_group_default(Group, Config, false).

init_group_default(_Group, Config, Clean) ->
  if
    Clean ->
      clean_chainstores();

    true ->
      ok
  end,

  init_sparkl(
    [?NODES_SIMPLE | Config]),

  AppDir =
    code:priv_dir(svc_blockchain),

  ok =
    import(Config,
      filename:join([AppDir, ?CTTEST_DATA_DIR, ?EXAMPLES_LOC, ?PRIMES]),
      ?NODE1,
      ?ADMIN_USER,
      "/Scratch"),

  ok =
    import(Config,
      filename:join([AppDir, ?EXAMPLES_LOC, ?BLOCKCHAIN_STREAMING]),
      ?NODE1,
      ?ADMIN_USER,
      "/Scratch/Primes"),

  ok =
    import(Config,
      filename:join([AppDir, ?CTTEST_DATA_DIR, ?EXAMPLES_LOC, ?LIB_FOLDER]),
      ?NODE1,
      ?ADMIN_USER,
      "/"),

  ok =
    import(Config,
      filename:join([AppDir, ?CTTEST_DATA_DIR, ?EXAMPLES_LOC, ?BLOCKCYPHER]),
      ?NODE1,
      ?ADMIN_USER,
      "/Lib").


clean_chainstores() ->
  timer:sleep(
    60000),  % tactical sleep allows system to settle

  CleanScriptPath =
    filename:join([
      code:priv_dir(svc_blockchain),
      ?CTTEST_DATA_DIR,
      ?CLEAN_CHAINS_SCRIPT]),

  CleanCmd =
    string:join(
      ["bash", CleanScriptPath],
      " "),
  ct:pal(
    "Clean Command: ~s", [CleanCmd]),

  CleanResult =
    os:cmd(
      CleanCmd),
  ct:pal(
    "Clean Result: ~s", [CleanResult]).


init_sparkl(Config) ->
  ok =
    init(Config),
  ok =
    start(Config),
  timer:sleep(5000),

  Nodes =
    proplists:get_value(nodes, Config),
  ct:pal("Nodes: ~p", [Nodes]),

  lists:foreach(
    fun({_Info, Node}) ->
      Start =
        fun() ->
          ct:pal("Starting sse on: ~s.", [Node]),
          Result =
            rpc(Node, sse, start, []),
          ct:pal("Start sse result on ~s: ~p", [Node, Result]),
          Apps =
            rpc(Node, application, which_applications, []),
          ct:pal("Apps on node ~s: ~p", [Node, Apps]),
          true
        end,
      wait_for(Start, 5, 3)  % Sometimes starting can bail as 'unsettled'
                             % Need to retry (here 3 times).
    end, Nodes),
  ok.


end_per_group(blockchain_iot, Config) ->
  ok =
    stop([?NODES_IOT | Config]);

end_per_group(_Group, Config) ->
  ok =
    stop([?NODES_SIMPLE | Config]).


init_per_testcase(_TestCase, Config) ->
  Config.


end_per_testcase(_TestCase, Config) ->
  Config.


%%% -------------------------------------------------------------------------
%%% helper functions
%%% -------------------------------------------------------------------------
do_primes(Primes) ->
  spawn(
    fun() ->
      [test_prime(N, ?PRIMES_PATH) || N <- Primes]
    end
  ).


%% @doc
%% Does chain check (using different user qualifications)
%%
chain_check(Config) ->
  chain_check(Config, true).

chain_check(Config, SkipRef) ->
  {_CountScript, CheckScript} =
    get_script_pair(?LOCAL_PREFIX),

  CheckCmd =
    make_command(CheckScript, Config, SkipRef),

  % Make note of Check Result for admin user (main result)
  CheckResult =
    chain_check(true, false, false, not SkipRef, CheckCmd),
  CheckCmd2 =
    make_command(CheckScript, ?TEST_USER, Config, SkipRef),
  chain_check(false, false, true, false,  CheckCmd2),

  CheckResult.

chain_check(Checked_, Bubbled_, Skipped_, Refd_, CheckCommand) ->
  ct:pal(
    "Check Command: ~s",
    [CheckCommand]),
  CheckResult =
    os:cmd(CheckCommand),
  ct:pal(
    "Check Result: ~p:~p:~p:~p ~s",
    [Checked_, Bubbled_, Skipped_, Refd_, CheckResult]),
  [Result, Checked, Bubbled, Skipped, Refd] =
    string:tokens(CheckResult,":"),

  true =
    list_to_atom(Result),
  true =
    list_to_integer(Checked) > 0 orelse not Checked_,
  true =
    list_to_integer(Bubbled) > 0 orelse not Bubbled_,
  true =
    list_to_integer(Skipped) > 0 orelse not Skipped_,
  % true =
  %  list_to_integer(Refd) > 0 orelse not Refd_,
  {Result, Checked, Bubbled, Skipped, Refd}.


test_prime(N, PrimesPath) ->
  test_prime(N, PrimesPath, ?NODE1).

test_prime(N, PrimesPath, Node) ->
  ct:pal("test_prime: ~p:~s:~p", [N, PrimesPath, Node]),
  {ok, {"Yes" ,_Ignore}} =
    rpc(Node, sse_svc_cmd, solicit, [
      ?ADMIN_USER,
      PrimesPath,
      [{"n", N}]]).


get_mix_refs() ->
  {ok, User} = rpc(
    ?NODE1, sse_cfg, get_user, [?ADMIN_USER]),
  ct:pal("Admin user... ~p", [User]),

  {ok, {_Perms, Seq}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/Sequencer"]),
  ct:pal("Sequencer object... ~p", [Seq]),

  {ok, {_Perms, N}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/n"]),
  ct:pal("N field... ~p", [N]),

  {ok, {_Perms, Div}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/div"]),
  ct:pal("Div field... ~p", [Div]),

  {ok, {_Perms, Yes}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/YES"]),
  ct:pal("Yes field... ~p", [Yes]),

  {ok, {_Perms, CheckPrime}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/Mix/CheckPrime"]),
  ct:pal("CheckPrime op... ~p", [CheckPrime]),

  {ok, {_Perms, FirstDivisor}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/Mix/FirstDivisor"]),
  ct:pal("FirstDivisor op... ~p", [FirstDivisor]),

  {ok, {_Perms, Test}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/Mix/Test"]),
  ct:pal("Test op... ~p", [Test]),

  {ok, {_Perms, FDOk}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/Mix/FirstDivisor/Ok"]),
  ct:pal("FD Ok reply... ~p", [FDOk]),

  {ok, {_Perms, TestYes}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/Mix/Test/Yes"]),
  ct:pal("Test Yes reply... ~p", [TestYes]),

  {ok, {_Perms, CheckPrimeYes}} = rpc(
    ?NODE1, sse_cfg, retrieve_object,
    [User, "/Scratch/Primes/Mix/CheckPrime/Yes"]),
  ct:pal("CheckPrime Yes response... ~p", [CheckPrimeYes]),

  #{seq => ref_of(Seq),
    n => ref_of(N),
    div_ => ref_of(Div),
    yes => ref_of(Yes),
    check => ref_of(CheckPrime),
    fd => ref_of(FirstDivisor),
    test => ref_of(Test),
    fdok => ref_of(FDOk),
    testyes => ref_of(TestYes),
    checkyes => ref_of(CheckPrimeYes)}.


count_dir(Config, Path) ->
  ChainDir =
    proplists:get_value(chain_dir, Config),
  Dir =
    filename:join(ChainDir, Path),
  {ok, DirList} =
    file:list_dir(
      Dir),
  Count =
    lists:foldl(
      fun(El, Acc) ->
        File =
          filename:join(Dir, El),
        Acc +
          list_to_integer(
            string:strip(
              os:cmd(
                "wc -l " ++ File ++ " | cut -f 1 -d ' '"),
              right, $\n))
      end,
      0, DirList),
  ct:pal(
    "WCL count: ~s:~w", [Path, Count]),
  Count.


wait_for_blocks(Config, TargetNumTxns, Bl, Ev) ->
  wait_for_blocks(Config, TargetNumTxns, Bl, Ev, ?NODE1).

wait_for_blocks(Config, TargetNumTxns, Bl, Ev, Node) ->
  ct:pal("Waiting for ~p blocks on... ~p", [TargetNumTxns, Node]),
  timer:sleep(15000),

  try
    {ok, User} = rpc(
      Node, sse_cfg, get_user, [?ADMIN_USER]),
    ct:pal("Admin user... ~p", [User]),

    #{
        txn_count := ActualNumTxns,
        block_count := BlockCountSlated} =
      rpc(Node, gen_server, call, [svc_blockchain, state]),

    ct:pal("Target Txns: ~w, Actual Txns: ~w", [TargetNumTxns, ActualNumTxns]),

    case TargetNumTxns of
      ActualNumTxns ->
        ct:pal("Block count slated: ~w", [BlockCountSlated]),

        {BlockCountDone, EventCountDone} =
          rpc(Node, gen_server, call, [svc_blockchain_local, state]),
        ct:pal("Block/Event count done: ~w:~w", [BlockCountDone, EventCountDone]),

        BlockFileCount =
          count_dir(Config, ?NODE1_BLOCKCHAIN),
        ct:pal("Actual block count:delta ~w:~w", [BlockFileCount, Bl]),

        EventsFileCount =
          count_dir(Config, ?NODE1_ADMIN_EVENTS),
        ct:pal("Actual event count:delta ~w:~w", [EventsFileCount, Ev]),

        Done = BlockCountDone == BlockCountSlated andalso
          BlockCountSlated == BlockFileCount + Bl andalso
          EventCountDone == EventsFileCount + Ev,

        if
          Done ->
            {BlockCountDone, EventCountDone};

          true ->
              ct:pal("Waiting for more blocks/events ~w:~w:~w ~w:~w...",
                [BlockCountDone, BlockCountSlated, BlockFileCount,
                  EventCountDone, EventsFileCount]),
              wait_for_blocks(Config, TargetNumTxns, Bl, Ev, Node)
        end;

      _Other ->
        ct:pal("Waiting for more txns"),
        wait_for_blocks(Config, TargetNumTxns, Bl, Ev, Node)
    end
  catch
    C:E ->
      ct:pal("ERROR: ~p ~p", [C, E]),
      wait_for_blocks(Config, TargetNumTxns, Bl, Ev, Node)
  end.


wait_for_files(Files) ->
  lists:foreach(
    fun(File) ->
      wait_for_file(File)
    end,
    Files).

wait_for_file(File) ->
  wait_for_file(
    File, 3).

wait_for_file(File, Time) ->
  Fun =
    fun() ->
      try
        filelib:is_file(File)
      catch
        _:_ ->
          false
      end
    end,
  wait_for(Fun, Time).

wait_for(Fun, Time) ->
  wait_for(Fun, Time, -1).

wait_for(Fun, Time, Iter) ->
  wait_for(Fun, Time, Iter, undefined).


wait_for(_Fun, _Time, 0, Last) ->
  throw(Last);

wait_for(Fun, Time, Iter, _Last) ->
  timer:sleep(
    trunc(
      Time * 1000)),

  {Status, Result, Last} =
    try
      {true, Fun(), undefined}
    catch
      C:E ->
        {false, undefined, {C, E}}
    end,

  case Status of
    true ->
      Result;

    false ->
      wait_for(
        Fun, Time*1.1, Iter-1, Last)
  end.


get_script_pair(Prefix) ->
  AppDir =
    code:priv_dir(svc_blockchain),
  CountScript =
    filename:join(
      [AppDir, ?CTTEST_DATA_DIR, ?TESTSCRIPTS_LOC, Prefix ++ ?COUNT_SCRIPT]),
  CheckScript =
    filename:join(
      [AppDir, ?CTTEST_DATA_DIR, ?TESTSCRIPTS_LOC, Prefix ++ ?CHECK_SCRIPT]),
  {CountScript, CheckScript}.


make_command(Cmd, Config, SkipRef) ->
  make_command(Cmd, ?ADMIN_USER, Config, SkipRef).


make_command(Cmd, User, Config, SkipRef) ->
  make_command(Cmd, User, ?NODE1_STR, Config, SkipRef).


make_command(Cmd, User, Node, Config, false) ->
  make_command_(Cmd, User, Node, Config, "");

make_command(Cmd, User, Node, Config, true) ->
  make_command_(Cmd, User, Node, Config, "SKIP_REFTEST=True").


make_command_(Cmd, User, Node, Config, SkipEnv) ->
  ChainDir =
    proplists:get_value(chain_dir, Config),
  PythonPath =
    lists:flatten(
      io_lib:format(
        "PYTHONPATH=~s:~s",
        [filename:join(
          [code:priv_dir(
            svc_blockchain), ?SCRIPTS_LOC]),
        filename:join(
          [code:priv_dir(
            svc_blockchain), ?CTTEST_DATA_DIR, ?SCRIPTS_LOC])])),
  string:join(
    [SkipEnv,
      PythonPath,
      "python3",
      Cmd,
      filename:join([ChainDir, ?TESTLOCAL]),
      Node,
      User], " ").


do_batches(
    TargetNumTxns, N, S, Primes, Config, SkipRef, Adds) ->
  do_batches(
    TargetNumTxns, N, S, Primes, Config, SkipRef, undefined, Adds).


do_batches(
  _TargetNumTxns_, 0, _S, _Primes, _Config, _SkipRef, CheckResult,
    [_Bl, _Ev, Bl1, Ev1]) ->
  {CheckResult, Bl1, Ev1};

do_batches(
  TargetNumTxns_, N, S, Primes, Config, SkipRef, _CheckResult, Adds) ->

  Range =
    lists:seq(1, S),

  [do_primes(Primes) || _I <- Range],

  TargetNumTxns =
    TargetNumTxns_ + (S * length(Primes)),

  [Bl, Ev | _Ign] = Adds,

  {Bl1, Ev1} =
    wait_for_blocks(Config, TargetNumTxns, Bl, Ev),

  CheckResult =
    chain_check(
      Config, SkipRef),

  do_batches(
    TargetNumTxns, N - 1, S, Primes, Config, SkipRef, CheckResult,
    [Bl, Ev, Bl1, Ev1]).


send_events_evh(Seq, TxnStart, Events, TxnEnd) ->
  % Send txn start
  ct:pal("Sending: ~p", [TxnStart]),
  {ok, _Ignore} =
    rpc(?NODE1, svc_blockchain_global_evh, handle_event, [
      TxnStart, undefined]),

  EvmEventWrapper =
    #?EVM_EVENT{
      subject = Seq,
      source = ?SEQUENCER_EVENT_SOURCE},

  lists:foreach(
    fun(Ev) ->
      EvmEvent =
        EvmEventWrapper#?EVM_EVENT{
          timestamp = erlang:system_time(),
          event = Ev},
      ct:pal("Sending: ~p", [EvmEvent]),

      {ok, _Ignore} =
        rpc(?NODE1, svc_blockchain_global_evh, handle_event, [
          EvmEvent, undefined])
    end,
    Events),

  % Send txn end
  ct:pal("Sending: ~p", [TxnEnd]),
  {ok, _Ignore} =
    rpc(?NODE1, svc_blockchain_global_evh, handle_event, [
      TxnEnd, undefined]).


check_chain_evh(Txns, Config, TxnId, EventsLen) ->
  ct:pal("Txns: ~p, TxnId: ~s, EventsLen: ~p",
    [Txns, TxnId, EventsLen]),

  % Wait for the block to write
  wait_for_blocks(Config, Txns, 0, 0),

  ChainDir =
    proplists:get_value(chain_dir, Config),
  ct:pal("ChainDir: ~s", [ChainDir]),

  BlockEventsFile =
    filename:join(
      [ChainDir, ?local_ev_col, ?local_ev_dir, ?ADMIN_USER, TxnId]),
  wait_for_file(
    BlockEventsFile),

  {ok, BlockEvents_} =
    file:read_file(
      BlockEventsFile),

  BlockEvents =
    string:tokens(
      ?s(BlockEvents_),
      "\n"),
  ct:pal("BlockEvents: ~s", [BlockEvents]),

  EventsLen =
    length(BlockEvents),

  ChainBlockDir =
    filename:join(
      [ChainDir, ?local_bc_col, ?local_bc_dir, ?NODE1_STR, "blockchain"]),

  {ok, ChainBlocks_} =
    file:list_dir(ChainBlockDir),

  [ChainBlockFile | _Ignore] =
    lists:reverse(
      lists:sort(
        [list_to_integer(C) || C <- ChainBlocks_])),

  {ok, ChainBlock_} =
    file:read_file(
      filename:join(
        ChainBlockDir,
        integer_to_list(
          ChainBlockFile))),

  ChainBlock =
    jsx:decode(
      ChainBlock_, [return_maps]),
  ct:pal("Chainblock: ~p", [ChainBlock]),

  TxnIdBlock =
    ?s(
      maps:get(
        ?u(?event_txn),
        ChainBlock)),

  ct:pal("TxnId in, TxnId from block: ~s: ~s",
    [TxnId, TxnIdBlock]),

  TxnId =
    TxnIdBlock,

  chain_check(
    Config,
    true).


wait_get_epoch(Epoch) ->
  wait_get(
    ?EPOCH_URL ++ integer_to_list(
      Epoch)).

wait_get_proof(Signed) ->
  wait_get(
    ?PROOF_URL ++ Signed).

wait_get(Url) ->
  GetFun =
    fun() ->
      {ok, {{_Version, StatusCode, _ReasonPhrase},
            _Headers, Resp}} =
        rpc(?NODE2, httpc, request, [
          get, {Url, []}, [], []]),

      {ok, #{"content" := Content}} =
        sse_json:decode(
          list_to_binary(
            Resp)),
      ContentMap =
        maps:from_list(
          [{Tag_, Content_} ||
            #{"tag" := Tag_, "content" := Content_} <- Content]),
      ct:pal(
        "StatusCode: Record: ~p:~p",
        [StatusCode, ContentMap]),
      ContentMap
    end,
  wait_for(GetFun, 5, 3).


%%% -------------------------------------------------------------------------
%%% blockchain_events
%%% -------------------------------------------------------------------------
test_blockchain_events(Config) ->
  #{seq := Seq,
    n := N,
    div_ := Div,
    yes := Yes,
    check := CheckPrime,
    fd := FirstDivisor,
    test := Test,
    fdok := FDOk,
    testyes := TestYes,
    checkyes := CheckPrimeYes} =
    get_mix_refs(),

  TxnId1 =
    "E-N8R-TQ9-1K1",

  TxnStart1 =
    #?EVM_EVENT{
      source = ?SEQUENCER_EVENT_SOURCE,
      subject = Seq,
      event = {?GENERIC_EVENT,{30123,38529,2017},
        txn_start,
        Seq, [#?CAUSE{subject = Seq}],
        undefined,svc_sequencer_event_reduce,
        [{txn,[{txn_id, TxnId1},
          {node,'sse1@andrew.local'}]}]}},

  DataEvents =
    [{data_event,
      {20653,29816,37352},
      CheckPrime, [""],
      {generic_event,{30123,38529,2017}},
      undefined,
      [{datum, N, 3}]},

      {data_event,
        {30123,38529,39},
        FirstDivisor, [""],
        {generic_event,{30123,38529,2017}},
        undefined,
        [{datum, N, 3}]},

      {data_event,
        {30123,38529,2146},
        FDOk, [""],
        {generic_event,{30123,38529,2017}},
        {data_event,{30123,38529,39}},
        [{datum, Div, 2}]},

      {data_event,
        {30123,38529,103},
        Test, [""],
        {generic_event,{30123,38529,2017}},
        undefined,
        [{datum, N, 3},
          {datum, Div, 2}]},

      {data_event,
        {30123,38529,135},
        TestYes, [""],
        {generic_event,{30123,38529,2017}},
        {data_event,{30123,38529,103}},
        [{datum, Yes, undefined}]},

      {data_event,
        {30123,38529,167},
        CheckPrimeYes, [""],
        {generic_event,{30123,38529,2017}},
        {data_event,{20653,29816,37352}},
        [{datum, Yes, undefined}]}],

  TxnEnd1 =
    #?EVM_EVENT{
    source = ?SEQUENCER_EVENT_SOURCE,
    event =
      {?GENERIC_EVENT, {30123,38529,199},
        txn_end,
        Seq, [""],
        undefined,
        svc_sequencer_event_reduce,
        [{txn,[
          {txn_id, TxnId1},
          {reason,normal}]}]
        }},

  send_events_evh(
    Seq, TxnStart1, DataEvents, TxnEnd1),

  check_chain_evh(1, Config, TxnId1, 6),

  TxnId2 =
    "E-N8R-TQ9-1K2",

  TxnStart2 =
    #?EVM_EVENT{
      source = ?SEQUENCER_EVENT_SOURCE,
      subject = Seq,
      event = {?GENERIC_EVENT,{30123,38529,2018},
        txn_start,
        Seq, [#?CAUSE{subject = Seq}],
        undefined,svc_sequencer_event_reduce,
        [{txn,[{txn_id, TxnId2},
          {node,'sse1@andrew.local'}]}]}},

  MixedEvents =
    [{data_event,
      {20653,29816,37352},
      CheckPrime, [""],
      {generic_event,{30123,38529,2018}},
      undefined,
      [{datum, N, 3}]},

      {data_event,
        {30123,38529,39},
        FirstDivisor, [""],
        {generic_event,{30123,38529,2018}},
        undefined,
        [{datum, N, 3}]},

      {error_event,
        {30123,38529,2146},
        FirstDivisor, [""],
        {generic_event,{30123,38529,2018}},
        {data_event,{30123,38529,39}},
        prohibited}],

  TxnEnd2 =
    #?EVM_EVENT{
      source = ?SEQUENCER_EVENT_SOURCE,
      event =
      {?GENERIC_EVENT, {30123,38529,200},
        txn_end,
        Seq, [""],
        undefined,
        svc_sequencer_event_reduce,
        [{txn,[
          {txn_id, TxnId2},
          {reason,normal}]}]
      }},

  send_events_evh(
    Seq, TxnStart2, MixedEvents, TxnEnd2),

  check_chain_evh(2, Config, TxnId2, 3).


%%% -------------------------------------------------------------------------
%%% blockchain_local
%%% -------------------------------------------------------------------------
test_blockchain_local(Config) ->
  ct:pal("Start big txn", []),
  Primes =
    [10000019],

  % include merkle tree ref testing
  do_batches(
    0, 2, 2, Primes, Config, false, [0, 0]),

  ChainDir =
    proplists:get_value(chain_dir, Config),
  DetsFile =
    filename:join([ChainDir, ?DETS_FILE]),

  % Run a txn.
  test_prime(13, ?PRIMES_PATH),

  % Give chance to write chain.
  {Bl, Ev} =
    wait_for_blocks(Config, 5, 0, 0),  % this one, and the previous 'big' ones

  true =
    filelib:is_file(DetsFile),
  true =
    filelib:is_dir(
      filename:join(
        [ChainDir, ?TESTLOCAL, ?TESTBLOCKCHAIN])),
  true =
    filelib:is_dir(
      filename:join(
        [ChainDir, ?TESTLOCAL, ?TESTEVENTS])),

  % Then kill files to test for resiliency.
  clean_chainstores(),

  ct:pal("Start over", []),
  Primes2 =
    [971, 977, 983, 991, 997],

  {_CheckResult, Bl1, Ev1} =
    do_batches(
      5, 2, 3, Primes2, Config, true, [Bl, Ev]),

  Bl2 = Bl1 - Bl,
  Ev2 = Ev1 - Ev,

  ct:pal("Current Blocks/Events: ~p/~p", [Bl2, Ev2]),

  % Then restart SPARKL to test the restore from back-up
  ok =
    end_per_group(blockchain_local, Config),
  ok =
    init_group_default(blockchain_local, Config),

  {CheckResult, Bl3, _Ev3} =
    do_batches(
      0, 1, 1, Primes2, Config, true, [-Bl2, -Ev2]),

  BlCh =
    list_to_integer(
      element(
        2, CheckResult)),
  ct:pal("Checked Blocks: ~p+~p=~p", [Bl2, Bl3, BlCh]),
  BlCh = Bl2 + Bl3.


%%% -------------------------------------------------------------------------
%%% blockchain_streaming
%%% -------------------------------------------------------------------------
test_blockchain_streaming(_Config) ->
  AppDir =
    code:priv_dir(svc_blockchain),
  StreamScript =
    filename:join([AppDir, ?SCRIPTS_LOC, ?STREAM_SCRIPT]),

  StreamCmd =
    string:join(
      ["bash", StreamScript, AppDir],
      " "),

  ct:pal("Stream Command: ~s", [StreamCmd]),

  spawn(
    fun() ->
      os:cmd(StreamCmd)
    end),

  BlockGrep =
    string:join(
      ["grep ", ?STREAMOUT_GREP, " ", ?STREAMOUT_LOG, " | wc -l"],
      ""),

  StreamTest =
    fun() ->
      % Run a txn.
      test_prime(13, ?PRIMES_PATH),

      BlockPassed =
        string:strip(
          os:cmd(BlockGrep),
          right,
          $\n),

      ct:pal("Block Passed: ~s", [BlockPassed]),

      list_to_integer(BlockPassed) > 0
    end,

  wait_for(StreamTest, 5).


%%% -------------------------------------------------------------------------
%%% blockchain_iot
%%% -------------------------------------------------------------------------
test_iot(Config) ->
  ChainDir_ =
    proplists:get_value(chain_dir, Config),
  ChainDir =
    filename:join([ChainDir_, ?TESTLOCAL, ?TESTBLOCKCHAIN]),

  % Run a txn.
  PrimesPath =
    "Scratch/BlockchainIOT/Primes/Mix/CheckPrime",
  test_prime(13, PrimesPath, ?NODE4),

  Node2Dir =
    filename:join([ChainDir, ?NODE2_STR, ?TESTBLOCKCHAIN]),
  Node3Dir =
    filename:join([ChainDir, ?NODE3_STR, ?TESTBLOCKCHAIN]),

  % Give chance to write chain.
  wait_for_files(
    [Node2Dir, Node3Dir]),

  WaitNodeFiles =
    fun() ->
      {ok, [Node2File_]} =
        file:list_dir(Node2Dir),
      ct:pal("Node2 File: ~s", [Node2File_]),

      {ok, [Node3File_]} =
        file:list_dir(Node3Dir),
      ct:pal("Node3 File: ~s", [Node3File_]),

      {Node2File_, Node3File_}
    end,

  FileResult =
    wait_for(WaitNodeFiles, 5),
  ct:pal("File Result: ~p", [FileResult]),

  {Node2File, Node3File} =
    FileResult,

  {ok, Node2Block_} =
    file:read_file(
      filename:join([Node2Dir, Node2File])),
  Node2Block =
    maps:remove(
      <<?block_signed>>,
      jsx:decode(
        Node2Block_,
        [return_maps])),
  ct:pal("Node2 Block: ~p", [Node2Block]),

  Node2BlockEnc =
    svc_blockchain_blocks:term_encode(Node2Block),
  ct:pal("Node2 Block Enc: ~s", [Node2BlockEnc]),

  Node2BlockHash =
    svc_blockchain_crypto:digest(Node2BlockEnc),
  ct:pal("Node2 Block Hash: ~s", [Node2BlockHash]),

  {ok, Node3Block_} =
    file:read_file(
      filename:join([Node3Dir, Node3File])),
  Node3Block =
    maps:remove(
      <<?block_signed>>,
      jsx:decode(
        Node3Block_,
        [return_maps])),
  Node2BlockHash_ =
   maps:get(<<?block_hash>>, Node3Block),

  ct:pal("Node3 Listed Node2 Hash: ~s", [Node2BlockHash_]),

  true =
    Node2BlockHash == Node2BlockHash_,

  % Do chain checking, including bubbled hashes.
  {_CountScript, CheckScript} =
    get_script_pair(?LOCAL_PREFIX),
  CheckCmd =
    make_command(
      CheckScript, ?UNDEFINED_STRING, ?UNDEFINED_STRING, Config, false),
  chain_check(true, true, false, false, CheckCmd).


%%% -------------------------------------------------------------------------
%%% blockchain_merkle
%%% -------------------------------------------------------------------------
test_merkle(_Config) ->
  #{
      <<"epoch">> := [0],
      <<"root">> :=
      [<<"67050eeb5f95abf57449d92629dcf69f80c26247e207ad006a862d1e4e6498ff">>],
      <<"sigkey">> :=
      [<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>],
      <<"timestamp">> := [<<"1529295494.613966">>]} =
    wait_get_epoch(0),

  #{
      <<"epoch">> := [1],
      <<"root">> :=
      [<<"9c2e4d8fe97d881430de4e754b4205b9c27ce96715231cffc4337340cb110280">>],
      <<"sigkey">> :=
      [<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>],
      <<"timestamp">> := [<<"1529295510.342922">>]} =
    wait_get_epoch(1),

  #{
      <<"epoch">> := [2],
      <<"root">> :=
      [<<"0c08173828583fc6ecd6ecdbcca7b6939c49c242ad5107e39deb7b0a5996b903">>],
      <<"sigkey">> :=
      [<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>],
      <<"timestamp">> := [<<"1529295525.832627">>],
      <<"urls">> :=
      [#{"content" :=
      [#{"content" := [<<"blockcypher">>],
        "tag" := <<"type">>},
        #{"content" :=
        [<<"https://api.blockcypher.com/v1/bcy/test/txs/56ad47f6d390215af01401c061449fd31fd34a2621797318b03996f190384504?limit=50&includeHex=true">>],
          "tag" := <<"url">>}],
        "tag" := <<"value">>},
        #{"content" :=
        [#{"content" := [<<"twitter">>],
          "tag" := <<"type">>},
          #{"content" :=
          [<<"https://twitter.com/HashesSparkl/status/1008564665478098957">>],
            "tag" := <<"url">>}],
          "tag" := <<"value">>}]} =
    wait_get_epoch(2),

  #{
      <<"epoch">> := [3],
      <<"root">> :=
      [<<"80903da4e6bbdf96e8ff6fc3966b0cfd355c7e860bdd1caa8e4722d9230e40ac">>],
      <<"sigkey">> :=
      [<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>],
      <<"timestamp">> := [<<"1529295541.174937">>],
      <<"urls">> :=
      [#{"content" :=
      [#{"content" := [<<"twitter">>],
        "tag" := <<"type">>},
        #{"content" :=
        [<<"https://twitter.com/HashesSparkl/status/1008564716510183424">>],
          "tag" := <<"url">>}],
        "tag" := <<"value">>}]} =
    wait_get_epoch(3),

  #{
      <<"epoch">> := [4],
      <<"root">> :=
      [<<"5a9eab9148389395eff050ddf00220d722123ca8736c862bf200316389b3f611">>],
      <<"sigkey">> :=
      [<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>],
      <<"timestamp">> := [<<"1529295556.842302">>],
      <<"urls">> :=
      [#{"content" :=
      [#{"content" := [<<"blockcypher">>],
        "tag" := <<"type">>},
        #{"content" :=
        [<<"https://api.blockcypher.com/v1/bcy/test/txs/870f146b5479b0428ef2918b6d5ea72100bc132d36e66c35354fe110131fe069?limit=50&includeHex=true">>],
          "tag" := <<"url">>}],
        "tag" := <<"value">>},
        #{"content" :=
        [#{"content" := [<<"twitter">>],
          "tag" := <<"type">>},
          #{"content" :=
          [<<"https://twitter.com/HashesSparkl/status/1008564782205579265">>],
            "tag" := <<"url">>}],
          "tag" := <<"value">>}]} =
    wait_get_epoch(4),

  #{
      <<"epoch">> := [5],
      <<"hashes">> :=
      [#{"content" :=
      [#{"content" :=
      [<<"m7k0e0bv5ytgoEoiiycECzU/9mbw/NzeOMQ+97Medsx4jyzadCAxI8m9MV703YFoGMPYHCXPUw8jjyoIPFy8AA==">>],
        "tag" := <<"sig">>},
        #{"content" :=
        [<<"d607a1a53c7a3039fb5d458421cfabb70ab20ae1a16821f834dfbb7a18d3bc45">>],
          "tag" := <<"hash">>}],
        "tag" := <<"value">>},
        #{"content" :=
        [#{"content" :=
        [<<"3nUT2gDR/40+nMN4x9vUdYrXNoXOB5IpfK5muUb3MldvU7z0g9is6hziYzL86YffDZfSTSYlrXYzNWcBgBNBAg==">>],
          "tag" := <<"sig">>},
          #{"content" :=
          [<<"44c33dc54a2c15a53bf3dfa3ef5b054c638a8d980b147bf6f9e33dff5162b6ff">>],
            "tag" := <<"hash">>}],
          "tag" := <<"value">>}],
      <<"root">> :=
      [<<"feb5cf483b89f430344d125df83a5163bfe8bb4c461a0ba55f3436495ca81d52">>],
      <<"sigkey">> :=
      [<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>],
      <<"timestamp">> := [<<"1529295571.983963">>],
      <<"urls">> :=
      [#{"content" :=
      [#{"content" := [<<"twitter">>],
        "tag" := <<"type">>},
        #{"content" :=
        [<<"https://twitter.com/HashesSparkl/status/1008564845728239616">>],
          "tag" := <<"url">>}],
        "tag" := <<"value">>}]} =
    wait_get_epoch(5),

  try
    wait_get_epoch(6),
    fail
  catch
    _:_ ->
      ok
  end,

  #{<<"epoch">> := [5],
    <<"proof">> :=
    [<<"3nUT2gDR/40+nMN4x9vUdYrXNoXOB5IpfK5muUb3MldvU7z0g9is6hziYzL86YffDZfSTSYlrXYzNWcBgBNBAg==, "
    "feb5cf483b89f430344d125df83a5163bfe8bb4c461a0ba55f3436495ca81d52">>],
    <<"sig">> :=
    [<<"c6DVTQsriBMzIdloFEr8OfSFbTNIVY1bCBPvHJAF6JHZpAMp0p7LIYW9DXwR8rGwFq5Pbi9ByoH4fA1RF3m2Dg==">>],
    <<"sigkey">> :=
    [<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>]} =

    wait_get_proof("m7k0e0bv5ytgoEoiiycECzU/9mbw/NzeOMQ+97Medsx4"
      "jyzadCAxI8m9MV703YFoGMPYHCXPUw8jjyoIPFy8AA=="),

  #{<<"epoch">> := [5],
    <<"proof">> :=
    [<<"m7k0e0bv5ytgoEoiiycECzU/9mbw/NzeOMQ+97Medsx4jyzadCAxI8m9MV703YFoGMPYHCXPUw8jjyoIPFy8AA==, "
    "feb5cf483b89f430344d125df83a5163bfe8bb4c461a0ba55f3436495ca81d52">>],
    <<"sig">> :=
    [<<"TcS7ubSPLNWNtni0MKcmrvgnxRPssdDNinHgUuaQbe9/G0FvBbWQphM1oSRSX/+JqTv9Mp74nH2XTg4dw5SkAw==">>],
    <<"sigkey">> :=
    [<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>]} =

    wait_get_proof("3nUT2gDR/40+nMN4x9vUdYrXNoXOB5IpfK5muUb3Mldv"
      "U7z0g9is6hziYzL86YffDZfSTSYlrXYzNWcBgBNBAg==").
