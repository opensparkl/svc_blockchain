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
%%% Merkle tree REST API
%%%
-module(svc_blockchain_yapp).

-include("sse.hrl").
-include("sse_log.hrl").
-include("sse_cfg.hrl").
-include("svc_blockchain.hrl").
-include("yaws_api.hrl").

%% YAWS callback export.
-export([
  out/1,
  handle_request/4,
  forward_mt_hosts/2]).


%% @doc
%% Dispatching function for requests directed to this module.
out(Arg) ->
  sse_yaws_util:out(Arg, ?MODULE).

%% @doc
%% Request function clauses all return a struct of the usual form (or 'ok').
%%
%% If no clause matches, then the function clause exception is caught
%% in the out/1 function and an error returned to the user.
-spec
handle_request(#arg{}, Method, Path, user()) ->
  ok
  | {ok, struct:struct()}
  | {error, reason()}
when
  Method :: atom(),
  Path :: string().

%% Posts a hash for inclusion in a future merkle tree record
%%
handle_request(Arg, 'POST',
    "/hash" ++ Hash_, #?USER{}) ->

  Registered =
    registered(),
  ?DEBUG([
    {node, node()},
    {registered, Registered}]),

  MerkleEnabled =
    lists:member(
      svc_blockchain_merkle, Registered),

  if
    MerkleEnabled ->
      Hash =
        if
          Hash_ == "" ->
            sse_yaws_util:param(Arg, ?mt_param_hash);

          true ->
            string:slice(Hash_, 1)
        end,

      ?DEBUG([
        {hash, Hash}]),

      {ok, {Signed, PubKey}} =
        svc_blockchain_merkle:push_hash(Hash),

      {ok, {?mt_param_merkle, [],
        [{?mt_param_signed, [], [{?PRIMITIVE, ?string, ?s(Signed)}]},
          {?mt_param_pubkey, [], [{?PRIMITIVE, ?string, ?s(PubKey)}]}]}};

    true ->
      {error, merkle_not_enabled}
  end;

%% @doc
%% Gets a proof of a hash if exists from merkle tree record
%%
handle_request(Arg, 'GET',
    "/proof" ++ Signed_, #?USER{}) ->

  Registered =
    registered(),
  ?DEBUG([
    {node, node()},
    {registered, Registered}]),

  MerkleEnabled =
    lists:member(
      svc_blockchain_merkle, Registered),

  if
    MerkleEnabled ->
      Signed__ =
        if
          Signed_ == "" ->
            sse_yaws_util:param(Arg, ?mt_param_signed);

          true ->
            string:slice(Signed_, 1)
        end,

      ?DEBUG([
        {signed, Signed__}]),

      case svc_blockchain_merkle:get_proof(Signed__) of

        {ok, {Signed, Proof, PubKey, Epoch}} ->
          {ok, {?mt_param_merkle, [],
            [{?mt_param_epoch, [], [{?PRIMITIVE, ?integer, Epoch}]},
              {?mt_param_proof, [], [{?PRIMITIVE, ?string, ?s(Proof)}]},
              {?mt_param_signed, [], [{?PRIMITIVE, ?string, ?s(Signed)}]},
              {?mt_param_pubkey, [], [{?PRIMITIVE, ?string, ?s(PubKey)}]}]}};

        {error, Reason} ->
          {error, Reason}
      end;

    true ->
      {error, merkle_not_enabled}
  end;

%% @doc
%% Gets merkle tree information for particular epoch
%%
handle_request(Arg, 'GET',
    "/epoch" ++ Epoch_, #?USER{}) ->

  Registered =
    registered(),
  ?DEBUG([
    {node, node()},
    {registered, Registered}]),

  MerkleEnabled =
    lists:member(
      svc_blockchain_merkle, Registered),

  if
    MerkleEnabled ->

      Epoch =
        if
          Epoch_ == "" ->
            sse_yaws_util:param(Arg, ?mt_param_epoch);

          true ->
            string:slice(Epoch_, 1)
        end,

      get_epoch_info(
        list_to_integer(Epoch));

    true ->
      {error, merkle_not_enabled}
  end;

%% @doc
%% Gets merkle tree information for latest epoch
%%
handle_request(_Arg, 'GET',
    "/latest", #?USER{}) ->

  Registered =
    registered(),
  ?DEBUG([
    {node, node()},
    {registered, Registered}]),

  MerkleEnabled =
    lists:member(
      svc_blockchain_merkle, Registered),

  if
    MerkleEnabled ->

      {ok, #sse_blockchain_merkle_hashes{epoch = Epoch}} =
        sse_cfg:get_resource(sse_blockchain_merkle_hashes, ?hashes_record_key),

      if
        is_integer(Epoch) ->
          get_epoch_info(Epoch - 1);

        true ->
          {error, not_found}
      end;

    true ->
      {error, merkle_not_enabled}
  end;

handle_request(Arg, Method,
    Path, #?USER{}) ->

  ?DEBUG([
    {arg, Arg},
    {path, Path},
    {method, Method}]),
  ok.


forward_mt_hosts(Urls, Hash) ->
  NumHosts =
    length(Urls),

  RespFwd = self(),

  lists:foreach(
    fun(Url) ->
      spawn(
        fun() ->
          ok =
            post_hash(Url, Hash, RespFwd)
        end)
    end,
    Urls),
  forward_mt_hosts_(NumHosts, #{}, Hash).


forward_mt_hosts_(0, Info, Hash) ->
  #{?mt_param_hash => Hash,
    ?mt_param_urls => Info};

forward_mt_hosts_(NumHosts, Info_, Hash) ->
  Info =
    receive
      Resp_ ->
        case Resp_ of
          undefined ->
            Info_;

          {Url, Resp} ->
            maps:put(Url, Resp, Info_)
        end
    end,
  forward_mt_hosts_(NumHosts - 1, Info, Hash).

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

get_epoch_info(Epoch) ->
  ?DEBUG([
    {epoch, Epoch}]),

  {ok, Record} =
    sse_cfg:get_resource(sse_blockchain_merkle_epoch, Epoch),

  ?DEBUG([
    {record, Record}]),

  #sse_blockchain_merkle_epoch{
    hashes = Hashes_,
    epoch = Epoch,
    urls = Urls_,
    pubkey = PubKey,
    root = RootHash,
    timestamp = Timestamp
  } = Record,

  Hashes =
    [{?mt_param_value, [], [
      {?mt_param_signed, [], [{?PRIMITIVE, ?string, ?s(Signed)}]},
      {?mt_param_hash, [], [{?PRIMITIVE, ?string, ?s(Hash)}]}]} ||
    {Signed, Hash} <- Hashes_],

  Urls =
    [{?mt_param_value, [], [
      {?mt_param_type, [], [{?PRIMITIVE, ?string, ?s(Type)}]},
      {?mt_param_url, [], [{?PRIMITIVE, ?string, ?s(Url)}]}]} ||
      {Type, Url} <- Urls_],

  {ok, {?mt_param_merkle, [],
    [ {?mt_param_timestamp, [], [{?PRIMITIVE, ?string, ?s(Timestamp)}]},
      {?mt_param_pubkey, [], [{?PRIMITIVE, ?string, ?s(PubKey)}]},
      {?mt_param_hashes, [], Hashes},
      {?mt_param_root, [], [{?PRIMITIVE, ?string, ?s(RootHash)}]},
      {?mt_param_urls, [], Urls},
      {?mt_param_epoch, [], [{?PRIMITIVE, ?integer, Epoch}]}]}}.


%% @doc
%% Does number of retries of an http post until success
%% with exponentially increasing waits.
%%
post_hash(Base, Hash, RespFwd) ->
  Url =
    lists:flatten(
      io_lib:format("~s/svc_blockchain/hash", [Base])),
  Body =
    lists:flatten(
      io_lib:format("hash=~s", [Hash])),
  post_hash(3, 2, Base, Url, Body, RespFwd).

-spec
post_hash(Retries, Wait, Base, Url, Body, RespFwd) ->
  ok
when
  Retries  :: pos_integer(),
  Wait     :: pos_integer(),
  Base     :: string(),
  Url      :: string(),
  Body     :: string(),
  RespFwd  :: pid().

post_hash(0, _Wait, _Base, _Url, _Body, RespFwd) ->
  RespFwd ! undefined, ok;

post_hash(Retries, Wait, Base, Url, Body, RespFwd) ->
  ?DEBUG([
    {url, Url},
    {body, Body}]),

  {ok,
    {{_HttpVersion, Status, _ReasonPhrase}, _Headers, Resp}} =
    httpc:request(
      post, {Url, [], "application/x-www-form-urlencoded", Body}, [], []),

  ?DEBUG(
    [{status, Status},
      {resp, Resp}]),

  if
    Status >= 200 andalso Status =< 299 ->
      RespMap_ =
        jsx:decode(
          list_to_binary(
            Resp),
          [return_maps]),
      Content =
        maps:get(?json_content, RespMap_),
      RespMap =
        maps:from_list([{?s(Tag_), lists:nth(1, Content_)} ||
          #{?json_content := Content_,
            ?json_tag := Tag_} <- Content]),
      RespFwd ! {Base, RespMap}, ok;

    true ->
      timer:sleep(
        Wait * 100),
      post_hash(
        Retries-1, Wait*2, Base, Url, Body, RespFwd)
  end.
