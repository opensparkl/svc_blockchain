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
%%% Default blockchain listener for a transaction.
%%%

-module(svc_blockchain_events).
-include("sse.hrl").
-include("sse_log.hrl").
-include("sse_cfg.hrl").
-include("sse_svc.hrl").
-include("sse_listen.hrl").
-include("svc_blockchain.hrl").
-include("sse_yaws.hrl").

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

-export([
  start/1,
  start_link/1]).

%% ------------------------------------------------------------------
%% Imports.
%% ------------------------------------------------------------------
-import(
  sse_cfg_util, [
    mix_of/1,
    ref_of/1,
    id_of/1,
    id_to_ref/1,
    owner_of/1,
    fields_of/1,
    name_of/1,
    path_of/1,
    parent_of/1
]).

-import(
  sse_svc_util, [
    type_of/1
]).

%% ------------------------------------------------------------------
%% Definitions.
%% ------------------------------------------------------------------
-define(STATE, ?MODULE).
-record(?STATE, {
  class          :: string(),
  notifies       :: map(),
  event_in_cnt   :: integer() | undefined,
  event_proc_cnt :: integer(),
  event_runhash  :: binary(),
  mix_info       :: {string(), string()} | undefined,
  cause          :: cause() | undefined,
  owner          :: string(),
  txn_id         :: string(),
  block_proc     :: {fun(), fun()},
  event_queue    :: pid()
}).

-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% User API functions.
%% ------------------------------------------------------------------
-spec
start(
    StartConfig) ->
  {ok, PId}
when
  StartConfig :: map(),
  PId         :: pid().

start(StartConfig) ->
  Id =
    lists:flatten(
      io_lib:format(
        "~s_events", [maps:get(txnid, StartConfig)])),

  InstanceSpec =
    #{
      id      => Id,
      start   => {?MODULE, start_link, [StartConfig]},
      restart => temporary,
      type    => worker},
  {ok, PId} =
    supervisor:start_child(
      svc_blockchain_sup, InstanceSpec),

  {ok, PId}.

%% @doc
%% Starts a new blockchain listener, returning the gen_server
%% pid if successful.
-spec
start_link(StartConfig) ->
  {ok, PId}
| {error, Reason}
when
  StartConfig :: map(),
  PId         :: pid(),
  Reason      :: reason().

start_link(StartConfig) ->
  gen_server:start_link(
    ?MODULE, StartConfig, []).

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

init_(StartConfig) ->

  #{
    cast := Cast,
    call := Call,
    queuesrv := QueueServer,
    service := Service,
    txnid := TxnId,
    txnstart := TxnStart,
    class := {ChainFolder, ChainClass}} =
      StartConfig,

  % Get the event and chainblock fields, if any, in the blockchain folder.
  BlockEvent =
    resolve_relative_(
      ChainFolder, ?mix_field_event),
  ChainBlock =
    resolve_relative_(
      ChainFolder, ?mix_field_chainblock),

  TraverseFun =
    fun
      (item, #?NOTIFY{} = Notify, Acc) ->
          NotifyFields =
            fields_of(Notify),
          case NotifyFields of
            [NotifyField] ->
              case NotifyField of
                BlockEvent ->
                  maps:put(
                    notify_event,
                    [split_op_path(Notify) |
                      maps:get(notify_event, Acc, [])],
                    Acc);

                ChainBlock ->
                  maps:put(
                    notify_block,
                    [split_op_path(Notify) |
                      maps:get(notify_block, Acc, [])],
                    Acc);

                _Other ->
                  Acc
              end;

            NotifyFields ->
              Acc
          end;

      (_Other, _Rec, Acc) ->
        Acc
    end,

  Notifies =
    sse_cfg:traverse(ChainFolder, TraverseFun, #{}),

  {ok, #?USER{name = Owner}} =
    sse_cfg:get_record_quick(
      owner_of(
        Service)),

  State_ =
    #?STATE{
      owner = Owner,
      class = ChainClass,
      event_proc_cnt = 0,
      event_in_cnt = undefined,
      event_runhash = <<?UNDEFINED_STRING>>,
      notifies = Notifies,
      txn_id = TxnId,
      block_proc = {Cast, Call},
      event_queue = QueueServer},

  State =
    process_txn_start(TxnStart, State_),

  {ok, State}.


handle_call(_Msg, _From, State) ->
  {reply, ok, State}.


handle_cast(
    {push_events, EventQueue, EvCnt},
    #?STATE{} = State) ->
  process_events(EventQueue, EvCnt, State);

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

%% @doc
%% Processes events in batch, which are pushed periodically from
%% svc_blockchain_queue.  Returns the appropriate reply for the
%% gen_server.
%%
-spec process_events(Events, EvCnt, State_) ->
  {noreply, State}
| {stop, normal, State}
when
  Events  :: list(),
  EvCnt   :: integer(),
  State_  :: #?STATE{},
  State   :: #?STATE{}.

process_events(
    Events, EvCnt, State_) ->

  {FirstEvIdx, LastEvIdx} =
    if
      length(Events) > 0 ->
        {{_LastEvent_, _LastTimestamp}, LastEvIdx_} =
          lists:last(Events),
        [{{_FirstEvent_, _FirstTimestamp}, FirstEvIdx_} | _Events_] =
          Events,
        {FirstEvIdx_, LastEvIdx_};

      true ->
        {undefined, undefined}
    end,

  State__ =
    lists:foldl(
      fun(Event, StateAcc) ->
        process_raw_event(Event, StateAcc)
      end,
      State_,
      Events),

  %% If the EvCnt is set then we know this to be the definitive
  %% event count for the transaction.  This listener is done
  %% when it has processed this many events.
  %%
  State =
    case EvCnt of
      undefined ->
        State__;

      EvCnt ->
        State__#?STATE{event_in_cnt = EvCnt}
    end,

  %% Roll a chain block for the transaction thus far!
  %%
  process_txn_block(
    {FirstEvIdx, LastEvIdx}, State).


%% @doc
%% Processes incoming sequencer data or error event.
%% We dispatch the event once transformed on any compatible notifies in the mix.
%%
-spec process_raw_event(
    {{Event, Timestamp}, EvIdx}, State_) ->
  State
when
  Event     :: event(),
  Timestamp :: integer(),
  EvIdx     :: integer(),
  State_     :: #?STATE{},
  State      :: #?STATE{}.

process_raw_event(
    {{Event_, Timestamp}, EvIdx},
    #?STATE{
      event_runhash = EventRunHash_,
      event_proc_cnt = EventProcCnt,
      owner = Owner,
      class = Class,
      notifies = Notifies
      } = State) ->

  EventIn =
    transform_event(
      Event_, Timestamp),

  Event =
    maps:merge(
      #{
        ?event_idx => EvIdx,
        ?block_writer => ?u(atom_to_list(node())),
        ?block_class => ?u(Class),
        ?block_owner => ?u(Owner)
      },
      EventIn
    ),
  EventEnc =
    svc_blockchain_blocks:term_encode(
      Event),
  EventHash =
    svc_blockchain_crypto:digest(
      ?u(EventEnc)),
  EventOut =
    maps:put(
      ?event_hash, EventHash, Event),
  EventRunHash =
    svc_blockchain_crypto:digest(
      <<EventRunHash_/binary, EventHash/binary>>),
  {ok, EventJSON} =
    sse_json:encode(
      EventOut),

  ?DEBUG(
    [{event_json, EventJSON},
      {event_runhash, EventRunHash}]),

  %% Write event to local chain store.
  ok =
    svc_blockchain_local:write_event(
      EventOut, EventJSON),

  %% Notify the event!
  NotifiesEvent =
    maps:get(notify_event, Notifies, []),
  NotifyFields =
    [{?mix_field_event, EventJSON}],

  lists:foreach(
    fun({Username, NotifyPath}) ->
      ok =
        sse_svc_cmd:notify(
          Username, NotifyPath, NotifyFields)
    end, NotifiesEvent),

  State#?STATE{
    event_runhash = EventRunHash,
    event_proc_cnt = EventProcCnt + 1}.


%% @doc
%% Process a transaction start event, by setting appropriate information
%% such as MixId, MixDigest, initial transaction cause, etc.
%% Returns updated loop state.
%%
-spec process_txn_start(TxnStart, State_) ->
  State
when
  TxnStart   :: generic_event(),
  State_     :: #?STATE{},
  State      :: #?STATE{}.

process_txn_start(
    #?GENERIC_EVENT{
      cause = Cause},
    State)->

  [#?CAUSE{subject = Subject} | _Ignore] =
    Cause,

  Mix =
    case mix_of(Subject) of
      undefined ->
        parent_of(Subject);

      Mix_ ->
        Mix_
    end,

  MixId =
    id_of(Mix),

  {ok, {UserRef, Path}} =
    sse_cfg:get_account_path(Mix),

  {ok, #?USER{name = Username} = User} =
    sse_cfg:get_record_quick(UserRef),

  FullPath =
    lists:flatten(
      io_lib:format(
        "~s~s", [Username, Path])),

  {ok, MixDigest} =
    hash_resource(
      User, FullPath),

  State#?STATE{
    cause = Cause,
    mix_info = {MixId, MixDigest}}.


%% @doc
%% Initiates the processing of a transaction chain block as a result of
%% a batch of events being received from the listener's blockchain queue.
%%
-spec
process_txn_block(
    {FirstEvIdx, LastEvIdx}, State_) ->
  {noreply, State} | {stop, normal, State}
when
  FirstEvIdx :: integer(),
  LastEvIdx :: integer(),
  State_     :: #?STATE{},
  State      :: #?STATE{}.

process_txn_block(
    {FirstEvIdx, LastEvIdx},
    #?STATE{
      owner = Owner,
      class = BlockClass,
      event_in_cnt = EventInCnt,
      event_proc_cnt = EventProcCnt,
      event_runhash = EventRunHash,
      mix_info = MixInfo,
      txn_id = TxnId,
      notifies = Notifies,
      block_proc = {Cast, _Call},
      event_queue = EventQueue} = State_) ->

  NotifiesBlock =
    maps:get(
      notify_block, Notifies, []),

  if
    FirstEvIdx == undefined ->
      ok;

    true ->
      BlockInfo =
        #{
          mix_info => MixInfo,
          event_hash => EventRunHash,
          notifies => NotifiesBlock,
          txn_id => TxnId,
          owner => Owner,
          class => BlockClass,
          first_event => FirstEvIdx,
          last_event => LastEvIdx
        },

      ?DEBUG([
        {blockinfo, BlockInfo}]),

      ok =
        Cast(svc_blockchain, incr_blockcount),

      ok =
        Cast(
          svc_blockchain_blocks,
          {process_txn_block, BlockInfo})
  end,

  State =
    State_#?STATE{
      event_runhash = <<?UNDEFINED_STRING>>},

  if
    EventProcCnt == EventInCnt ->
      ok =
        Cast(svc_blockchain, incr_txncount),

      ok = gen_server:stop(  % Stop the event queue.
        EventQueue),

      {stop, normal, State};

    true ->
      {noreply, State}
  end.


%% @doc
%% Splits the path of an op into username prefix
%% and following op path.
%%
-spec
split_op_path(Notify) ->
  {Username, NotifyPath}
when
  Notify     :: notify(),
  Username   :: string(),
  NotifyPath :: string().

split_op_path(Notify) ->
  [Username | NotifyPath_] =
    string:tokens(
      path_of(Notify), "/"),
  NotifyPath =
    string:join(NotifyPath_, "/"),
  {Username, NotifyPath}.


%% @doc
%% Gets a double-SHA256 hash for a resource
%%
-spec
hash_resource(User, ResourcePath) ->
  Result
when
  User         :: #?USER{} | string(),
  ResourcePath :: string(),
  Result       :: {ok, string()} | {error, reason()}.

hash_resource(
    #?USER{} = User, ResourcePath) ->
  case sse_cfg:retrieve_object(User, ResourcePath) of
    {ok, {_Permissions, Record}} ->
      Digest =
        string:to_lower(
          ?s(svc_blockchain_crypto:digest(
            encoding_xml:encode_struct(
              struct:from_record(
                Record, ?FORMAT_SOURCE))))),
      {ok, Digest};

    {error, Reason} ->
      {error, Reason}
  end.


%% @doc
%% Wraps sse_cfg:resolve_relative to return 'undefined' if
%% cannot resolve path relative to folder.
%%
resolve_relative_(FolderRef, Path) ->
  case sse_cfg:resolve_relative(
      FolderRef, Path) of
    {ok, Object_} ->
      Object_;

    {error, _Reason} ->
      undefined
  end.


%% @doc
%% Applies a 'prettifying' transform to sequencer data and error events.
%%
-spec
transform_event(Event_, Timestamp) ->
  Event
when
  Event_     :: event(),
  Event      :: map(),
  Timestamp  :: integer().

transform_event(
    #?DATA_EVENT{
      txn = Txn,
      ref = Ref,
      subject = Subject,
      data = Data_
    } = Event, Timestamp) ->

  Data =
    maps:from_list(
      [{name_of(Field),
          decide_value(
            Field, Value)} ||
        #?DATUM{
          field = Field,
          value = Value} <- Data_,
        type_of(Field) /= ?UNDEFINED]),

  Meta =
    [#{?event_datum_name =>
        ?u(name_of(Field)),
      ?event_datum_type =>
        ?u(type_of(Field))} ||
      #?DATUM{field = Field} <- Data_],

  maps:from_list(
    [{?event_tag,
        ?value_data_event},
      {?event_data, Data},
      {?event_meta, Meta},
      {?event_timestamp, Timestamp} |
        transform_event_(
          Event, Txn, Ref, Subject)]);

transform_event(
    #?ERROR_EVENT{
      txn = Txn,
      ref = Ref,
      subject = Subject,
      reason = Reason
    } = Event, Timestamp) ->

  maps:from_list(
    [{?event_tag,
        ?value_error_event},
      {?event_reason,
          ?u(Reason)},
      {?event_timestamp, Timestamp} |
        transform_event_(
          Event, Txn, Ref, Subject)]);

transform_event(
    Event, _Timestamp) ->
  Event.


transform_event_(
    Event, Txn, Ref, Subject) ->

  [{?event_id,
    ?u(id_of(ref_of(Event)))},
  {?event_txn,
    ?u(id_of(Txn))},
  {?event_ref,
    ?u(id_of(Ref))},
  {?event_subject,
    ?u(id_of(Subject))},
  {?event_subject_name,
    ?u(name_of(Subject))},
  {?event_subject_path,
    ?u(path_of(Subject))}].


%% @doc
%% Decide field value based on type.  For term and binary data (except
%% binary data representing strings), we replace the value
%% with a "__removed__" string.
%%
decide_value(Field, Value) ->
  case type_of(Field) of
    term ->
      ?value_removed;

    binary ->
      case io_lib:printable_unicode_list(
          binary_to_list(
            Value)) of
        true ->
          Value;

        false ->
          ?value_removed
      end;

    string ->
      ?u(Value);

    json ->
      ?u(Value);

    _Type ->
      Value
  end.
