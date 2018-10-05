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
%%% Blockchain single-node transaction event handler
%%%
-module(svc_blockchain_global_evh).
-include("sse.hrl").
-include("sse_log.hrl").
-include("sse_cfg.hrl").
-include("sse_svc.hrl").
-include("sse_listen.hrl").
-include("svc_blockchain.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% ------------------------------------------------------------------
%% Behaviour Exports.
%% ------------------------------------------------------------------
-behaviour(gen_event).
-export([
  handle_call/2,
  handle_event/2,
  handle_info/2,
  init/1,
  terminate/2]).


%% ------------------------------------------------------------------
%% Imports.
%% ------------------------------------------------------------------
-import(
sse_cfg_util, [
  ref_of/1,
  id_of/1
]).

%% ------------------------------------------------------------------
%% gen_event implementation.
%% ------------------------------------------------------------------
init(Node) ->
  {ok, Node}.


%% @doc
%% Forwards txn events from sequencer source to txn-specific blockchain
%% queue.  This handling of events is optimized to be quick as we are
%% executing in a global transaction block.
%%
-spec handle_event(evm_event(), term()) ->
  {ok, term()}.

handle_event(
    #?EVM_EVENT{
      source = ?SEQUENCER_EVENT_SOURCE,
      subject = Service,
      event = #?GENERIC_EVENT{
        tag = txn_start} = TxnStart},
    Args) ->

  Classes =
    svc_blockchain_blocks:get_subject_blockchains(
      Service),

  if
    Classes == [] ->
      ok;

    true ->
      TxnId =
        id_of(
          ref_of(
            TxnStart)),

      %% Start a queue for the transaction
      %%
      {ok, _PId} =
        svc_blockchain_queue:start(
          Service, TxnId, TxnStart, Classes)
  end,
  {ok, Args};

handle_event(
    #?EVM_EVENT{
      source = ?SEQUENCER_EVENT_SOURCE,
      event = #?GENERIC_EVENT{
        tag = txn_end,
        content = [{txn, Txn}]}},
    Args) ->

  TxnId =
    proplists:get_value(
      txn_id, Txn),

  ok =
    svc_blockchain_queue:txn_end(
      TxnId),
  {ok, Args};

handle_event(
  #?EVM_EVENT{
    source = ?SEQUENCER_EVENT_SOURCE,
    timestamp = Timestamp,
    event = #?DATA_EVENT{
      txn = Txn} = DataEvent},
  Args) ->

  %% Add event to txn-specific queue
  %%
  ok =
    svc_blockchain_queue:add_event(
      id_of(Txn), {DataEvent, Timestamp}),
  {ok, Args};

handle_event(
    #?EVM_EVENT{
      source = ?SEQUENCER_EVENT_SOURCE,
      timestamp = Timestamp,
      event = #?ERROR_EVENT{
        txn = Txn} = ErrorEvent},
    Args) ->

  %% Add event to txn-specific queue
  %%
  ok =
    svc_blockchain_queue:add_event(
      id_of(Txn), {ErrorEvent, Timestamp}),
  {ok, Args};

%% Non evm events are ignored.
handle_event(_EvmEvent, Node) ->
  {ok, Node}.


handle_call(_Msg, Node) ->
  {ok, Node, Node}.


handle_info(_Info, Node) ->
  {ok, Node}.


terminate(
    _Reason,
    _Node) ->
  ok.
