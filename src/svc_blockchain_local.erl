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
%%% Blockchain single-node, internal local writer.
%%%
%%% It is the responsibility of the SPARKL node admin to ensure that
%%% blockchain and events files are archived appropriately.
%%%
-module(svc_blockchain_local).
-include("sse.hrl").
-include("sse_log.hrl").
-include("sse_cfg.hrl").
-include("sse_svc.hrl").
-include("svc_blockchain.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

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

%% ------------------------------------------------------------------
%% User API Exports.
%% ------------------------------------------------------------------
-export([
  start/1,
  start_link/1]).

-export([
  write_event/2,
  write_block/2]).

%% ------------------------------------------------------------------
%% Definitions.
%% ------------------------------------------------------------------
-define(STATE, ?MODULE).
-record(?STATE, {
  block_dir     :: string(),
  event_dir     :: string(),
  block_count   :: integer(),
  event_count   :: integer()
}).

-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% User API functions.
%% ------------------------------------------------------------------
-spec
start(string()) ->
  {ok, pid()}.

start(ChainDir) ->
  InstanceSpec =
    #{
      id      => svc_blockchain_local,
      start   => {?MODULE, start_link, [ChainDir]},
      restart => temporary,
      type    => worker},
  {ok, _Pid} =
    supervisor:start_child(svc_blockchain_sup, InstanceSpec).


%% @doc
%% Starts a new instance of service, returning the gen_server pid if successful.
%%
-spec
start_link(string()) ->
  {ok, pid()}
  | {error, reason()}.

start_link(ChainDir) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, ChainDir, []).


%% @doc
%% Writes an event to the local blockchain store.
%%
-spec write_event(Event, EventJSON) ->
  ok
when
  Event :: term(),
  EventJSON :: binary().

write_event(Event, EventJSON) ->
  ok =
    gen_server:cast(
      svc_blockchain_local,
      {write_event, Event, EventJSON}).


%% @doc
%% Writes a block to the local blockchain store.
%%
-spec write_block(Block, BlockJSON) ->
  ok
when
  Block :: term(),
  BlockJSON :: binary().

write_block(Block, BlockJSON) ->
  ok =
    gen_server:cast(
      svc_blockchain_local,
      {write_block, Block, BlockJSON}).


%% ------------------------------------------------------------------
%% gen_server implementation.
%% ------------------------------------------------------------------
init(ChainDir) ->
  ?TRAP_EXIT,

  BcDir =
    filename:join(
      [ChainDir, ?local_bc_col, ?local_bc_dir]),

  EvDir =
    filename:join(
      [ChainDir, ?local_ev_col, ?local_ev_dir]),

  State =
    #?STATE{
      block_dir = BcDir,
      event_dir = EvDir,
      block_count = 0,
      event_count = 0},

  {ok, State}.


handle_call(
    state, _From, #?STATE{
      block_count = BlockCount,
      event_count = EventCount} = State) ->
  {reply, {BlockCount, EventCount}, State}.


handle_cast(
    {write_event, Event, EventJSON},
    #?STATE{
      event_count = EventCount_,
      event_dir = EvDir} = State) ->

  #{?event_txn := BlockId,
    ?block_owner := BlockOwner} = Event,

  write_to_file(
    filename:join([EvDir, BlockOwner]),
    BlockId,
    EventJSON),

  EventCount =
    EventCount_ + 1,

  {noreply, State#?STATE{
    event_count = EventCount}};

handle_cast(
  {write_block, Block, BlockJSON},
  #?STATE{
    block_count = BlockCount_,
    block_dir = BcDir} = State) ->

  #{?block_class := BlockClass,
    ?block_writer := BlockWriter} = Block,

  Timestamp =
    integer_to_list(
      trunc(erlang:system_time(second) / 10)),

  write_to_file(
    filename:join([BcDir, BlockWriter, BlockClass]),
    Timestamp,
    BlockJSON),

  BlockCount =
    BlockCount_ + 1,

  {noreply, State#?STATE{
    block_count = BlockCount}};

handle_cast(_Msg, State) ->
  {noreply, State}.


handle_info(_Info, State) ->
  {noreply, State}.


terminate(
  _Reason, #?STATE{}) ->
  ok.


code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% @doc
%% Writes data to file.
%%
write_to_file(Dir, File_, Data) ->
  ?DEBUG([
    {dir, Dir},
    {file, File_},
    {data, Data}]),

  File =
    filename:join([Dir, File_]),
  ok =
    filelib:ensure_dir(File),
  ok =
    file:write_file(File, <<Data/binary, $\n>>, [append]).
