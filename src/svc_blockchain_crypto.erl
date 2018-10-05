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
%%%
%%% Signing and verification utility functions (using ED25519)
%%%

-module(svc_blockchain_crypto).

-include("sse.hrl").
-include("sse_cfg.hrl").
-include("sse_svc.hrl").
-include("sse_log.hrl").
-include("svc_blockchain.hrl").

-export([
  keygen/0,
  sign/2,
  verify/3,
  digest_160/1,
  digest/1]).


%% @doc
%% Calls external script to generate an ed25519 priv/pub key pair.
%%
-spec
keygen() ->
  {PublicKey, PrivateKey}
when
  PublicKey  :: binary(),
  PrivateKey :: binary().

keygen() ->
  AppDir =
    code:priv_dir(svc_blockchain),

  RunCmd =
    filename:join(
      [AppDir, ?scripts_crypto_path, ?script_keygen]),

  Result =
    run_command(
      RunCmd),

  #{?dictkey_private := PrivateKey,
    ?dictkey_public := PublicKey} =
    Result,

  {PublicKey, PrivateKey}.


%% @doc
%% Calls external script to do verification of a signature on a message.
%%
-spec
verify(Message, Signed, PublicKey) ->
  true | false
when
  Message   :: binary(),
  Signed    :: binary(),
  PublicKey :: binary().

verify(Message, Signed, PublicKey)->
  AppDir =
    code:priv_dir(svc_blockchain),

  VerifyScript =
    filename:join(
      [AppDir, ?scripts_crypto_path, ?script_verify]),
  RunCmd =
    string:join(
      [VerifyScript, ?s(Message), ?s(Signed), ?s(PublicKey)],
      " "),

  Result =
    run_command(
      RunCmd),

  #{?dictkey_verify := Verify} =
    Result,

  Verify.

%% @doc
%% Calls external script to do verification of a signature on a message.
%%
-spec
sign(Message, PrivateKey) ->
  Signed
when
  Message    :: binary(),
  PrivateKey :: binary(),
  Signed     :: binary().

sign(Message, PrivateKey) ->
  AppDir =
    code:priv_dir(svc_blockchain),

  SignScript =
    filename:join(
      [AppDir, ?scripts_crypto_path, ?script_sign]),
  RunCmd =
    string:join(
      [SignScript, ?s(Message), ?s(PrivateKey)],
      " "),

  Result =
    run_command(
      RunCmd),

  #{?dictkey_signed := Signed} =
    Result,

  Signed.


%% @doc
%% Generates a (SHA256) digest of a value, given as a binary string
%%
-spec
digest(Value) ->
  Digest
when
  Value  :: binary(),
  Digest :: sha256_double_hash().

digest(Value) ->
  ?DEBUG([
    {value, Value}]),
  <<Hash:256>> =
    crypto:hash(
      sha256, crypto:hash(
        sha256, Value)),
  Digest =
    ?u(string:to_lower(
      lists:flatten(
        io_lib:format(
          "~64.16.0B", [Hash])))),
  ?DEBUG([
    {digest, Digest}]),
  Digest.


%% @doc
%% Generates a (SHA160) digest of a value
%%
-spec
digest_160(Value) ->
  Digest
when
  Value :: binary(),
  Digest :: sha160_double_hash().

digest_160(Value) ->
  <<Hash:160>> =
    crypto:hash(
      sha, crypto:hash(
        sha, Value)),
  ?u(string:to_lower(
    lists:flatten(
      io_lib:format(
        "~40.16.0B", [Hash])))).


%% @doc
%% Runs a command with robustness to occasional failure
%% from lack of available erlang port.
%%
run_command(Command) ->
  run_command_(5, 2, Command).

run_command_(0, _Wait, Command) ->
  throw(
    {cannot_execute, [{cmd, Command}]});

run_command_(Retries, Wait, Command) ->
  RunCmd =
    string:join(
      ["python3", Command],
      " "),
  ?DEBUG([
    {run_cmd, RunCmd}]),

  case get_result(
    os:cmd(
      RunCmd)) of
    {ok, Result} ->
      ?DEBUG([
        {result, Result}]),
      Result;

    error ->
      timer:sleep(
        Wait * 1000),
      run_command_(
        Retries-1, Wait*2, Command)
  end.


%% @doc
%% Determines whether a result has been obtained, or whether
%% a non-script error has occurred, such as an erlang port error.
%%
get_result(Result) ->
  try
    {ok, jsx:decode(
        list_to_binary(
          Result),
        [return_maps])}
  catch
      error:badarg->
        error
  end.
