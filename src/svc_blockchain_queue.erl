%%% @copyright 2018 Sparkl Limited. All Rights Reserved.
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
%%%
%%% Simple queue abstraction for events of a transaction
%%%

-module(svc_blockchain_queue).
-include("sse.hrl").
-include("sse_log.hrl").
-include("sse_cfg.hrl").
-include("sse_svc.hrl").
-include("svc_blockchain.hrl").

%% ------------------------------------------------------------------
%% Behaviour Exports.
%% ------------------------------------------------------------------
-behaviour(gen_server).
-export([
  init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-export([
  start/4,
  start_link/4,
  add_event/2,
  txn_end/1]).

%% ------------------------------------------------------------------
%% Definitions.
%% ------------------------------------------------------------------
-define(STATE, ?MODULE).
-record(?STATE, {
  event_queue :: list(),
  timer       :: timer:tref() | undefined,
  event_count :: integer(),
  txn_id      :: string(),
  service     :: service_ref(),
  listeners   :: list(pid()),
  txn_end     :: boolean()
}).

-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% User API functions.
%% ------------------------------------------------------------------
-spec
start(Service, TxnId, TxnStart, Classes) ->
  {ok, PId}
when
  Service   :: service_ref(),
  TxnId     :: string(),
  TxnStart  :: generic_event(),
  Classes   :: list(string()),
  PId       :: pid().


start(Service, TxnId, TxnStart, Classes) ->
  ?DEBUG([
    {txnid, TxnId}]),
  InstanceSpec =
    #{
      id      => TxnId,
      start   => {?MODULE, start_link, [Service, TxnId, TxnStart, Classes]},
      restart => temporary,
      type    => worker},
  {ok, PId} =
    supervisor:start_child(
      svc_blockchain_sup, InstanceSpec),
  register(
    regid(
      TxnId),
    PId),

  {ok, PId}.

%% @doc
%% Starts a new blockchain listener, returning the gen_server
%% pid if successful.
-spec
start_link(Service, TxnId, TxnStart, Classes) ->
  {ok, PId}
| {error, Reason}
when
  Service   :: service_ref(),
  TxnId     :: string(),
  TxnStart  :: generic_event(),
  PId       :: pid(),
  Classes   :: list(string()),
  Reason    :: reason().

start_link(Service, TxnId, TxnStart, Classes) ->
  gen_server:start_link(?MODULE,
    {Service, TxnId, TxnStart, Classes}, []).


%%
%% @doc
%% Adds an event to the process' txn queue
%% with minimal fuss as we need to be quick.
%%
add_event(TxnId, Event) ->
  ok =
    try
      gen_server:call(
        regid(
          TxnId),
        {add_event, Event})
    catch
      exit:{noproc, _Call} ->
        ok
    end.

%%
%% @doc
%% Signals the end of transaction to queue process.
%%
txn_end(TxnId) ->
  ok =
    gen_server:cast(
      regid(
        TxnId),
      txn_end).


%% ------------------------------------------------------------------
%% gen_server implementation.
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

init_({Service, TxnId, TxnStart, Classes}) ->
  gen_server:cast(
    self(), {init, TxnStart, Classes}),

  State =
    #?STATE{
      event_count = 0,  % data or error events
      event_queue = [],
      listeners = [],
      timer = undefined,
      txn_id = TxnId,
      service = Service,
      txn_end = false},

  {ok, State}.

handle_call(
    {add_event, Event},
    _From,
    #?STATE{
      event_queue = EventQueue_,
      event_count = EventCount} = State_) ->

  EventQueue =
    lists:append(EventQueue_, [
      {Event, EventCount}]),

  State =
    State_#?STATE{
      event_queue = EventQueue,
      event_count = EventCount + 1},

  {reply, ok, State};

handle_call(_Msg, _From, State) ->
  {reply, ok, State}.


handle_cast(
    {init, TxnStart, Classes},
    #?STATE{
      txn_id = TxnId,
      service = Service} = State) ->

  {_BlockProc, Cast, Call} =
    svc_blockchain:get_blockfuns(),

  {ok, {PubKey, PrivKey}} =
    application:get_env(
      svc_blockchain,
      sign_keypair),

  TxnIdSigned =
    svc_blockchain_crypto:sign(
      ?u(TxnId), ?u(PrivKey)),

  QueueServer =
    self(),

  %% Start listeners for the transaction
  %%
  spawn(
    fun() ->
      Listeners =
        lists:foldl(
          fun(Class, Listeners_) ->
            StartConfig =
               #{
                 txnid_sig => TxnIdSigned,
                 pubkey => PubKey,
                 cast => Cast,
                 call => Call,
                 queuesrv => QueueServer,
                 service => Service,
                 txnid => TxnId,
                 txnstart => TxnStart,
                 class => Class},

            {ok, Listener} =
              Call(
                svc_blockchain,
                {start_blockchain_events,
                  StartConfig}),
            lists:append(
              Listeners_, [Listener])
          end,
          [],
          Classes),
      ok =
        gen_server:cast(
          QueueServer, {init_done, Listeners})
    end),
  {noreply, State};


handle_cast(
    {init_done, Listeners},
    #?STATE{} = State_) ->

  BlockInterval =
    application:get_env(
      svc_blockchain, block_interval, ?default_block_interval),

  %% Start a timer for pushing block of events to listener
  %%
  {ok, TimerRef} =
    timer:apply_interval(
      BlockInterval,
      gen_server,
      cast,
      [self(), {push_events, Listeners}]),

  State =
    State_#?STATE{
      timer = TimerRef,
      listeners = Listeners},

  {noreply, State};


handle_cast(
    {push_events, Listeners},
    #?STATE{
      txn_end = TxnEnd,
      event_count = EvCnt_,
      event_queue = EventQueue} = State_) ->

  if
    EventQueue == [] andalso not TxnEnd ->
      ok;

    true ->
      EvCnt =
        if
          TxnEnd ->
            EvCnt_;

          true ->
            undefined
        end,

      ?DEBUG([
        {evcnt, EvCnt}]),

      spawn(  % No blocking of gen_server
        fun() ->
          lists:foreach(
            fun(Listener) ->
              ok =
                  gen_server:cast(
                  Listener,
                  {push_events, EventQueue, EvCnt})
            end, Listeners)
        end)
  end,

  State =
    State_#?STATE{
      event_queue = []},

  {noreply, State};

handle_cast(
    txn_end, State) ->

  {noreply, State#?STATE{
    txn_end = true}};

handle_cast(_Msg, State) ->
  {noreply, State}.


handle_info(_Info, State) ->
  {noreply, State}.


terminate(
    _Reason,
    #?STATE{
      txn_id = TxnId}) ->

  true =
    unregister(
      regid(
        TxnId)).


code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% @doc
%% Get registered process id from txn id - just do a 'list_to_atom' op.
%%
regid(TxnId) ->
  list_to_atom(
    TxnId).
