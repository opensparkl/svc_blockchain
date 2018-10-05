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
%%% @author <ahfarrell@sparkl.com> Andrew Farrell.
%%% @doc
%%% svc_blockchain extension configuration module.
%%%
-module(svc_blockchain_configurator).

-include("sse.hrl").
-include("sse_configure.hrl").
-include("sse_log.hrl").
-include("svc_blockchain.hrl").

-behaviour(sse_configure).
-export([
  configure/0,
  configure/4]).

-define(ADMIN_USER, "admin@localhost").

-spec
configure() ->
  list(config_spec()).

configure() -> [
  #?CONFIG_SPEC{
    mode = ?CONFIG_MODE_INIT,
    pass = 20,
    app_keys = [
      {sse, extensions},
      {sse_yaws, yaws_app_mods},
      {svc_blockchain, sign_keypair},
      {svc_blockchain, chain_dir},
      {svc_blockchain, block_interval},
      {svc_blockchain, block_fwd_interval},
      {svc_blockchain, block_fwd_nodes},
      {svc_blockchain, block_receive_keys},
      {svc_blockchain, merkletree_interval},
      {svc_blockchain, merkletree_quorum},
      {svc_blockchain, merkletree_fwds},
      {svc_blockchain, merkletree_urls}
      ]}
  ].


configure(?CONFIG_MODE_INIT, _Pass, AppKey, Value) ->
  configure(AppKey, Value).


% Add svc_blockchain to the sse extensions list.
configure({sse, extensions}, Current) ->
  [svc_blockchain | Current];

% Add a default svc_blockchain signing keypair
configure({svc_blockchain, sign_keypair}, undefined) ->
  {<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>,
    <<"OTtd0dO5sRpDXiQqVUuUde8yuq9sBwu9sKnUWLwXEh2k/"
    "gtGA7SNQqXsR2U1Y5FIzf85uQXpwLFPplxcxoPYxw==">>};

% svc_blockchain chain_dir
configure({svc_blockchain, chain_dir}, undefined) ->
  {ok, HomeDir} =
    init:get_argument(home),

  % Base directory for local blockchain/events.
  %
  filename:join(
    HomeDir, ?default_blockchain_dir);

% svc_blockchain block generation interval (ms)
configure({svc_blockchain, block_interval}, undefined) ->
  ?default_block_interval;

% svc_blockchain block fwd interval (ms)
configure({svc_blockchain, block_fwd_interval}, undefined) ->
  ?default_block_fwd_interval;

% svc_blockchain block receive keys
configure({svc_blockchain, block_receive_keys}, undefined) ->
  [<<"pP4LRgO0jUKl7EdlNWORSM3/ObkF6cCxT6ZcXMaD2Mc=">>];

% svc_blockchain block forward nodes
configure({svc_blockchain, block_fwd_nodes}, undefined) ->
      [];

% svc_blockchain merkletree forward solicits
configure({svc_blockchain, merkletree_fwds}, undefined) ->
  [{?ADMIN_USER, "Lib/lib.twitter/Mix/PostStatus", ["status"], 1, "twitter"},
    {?ADMIN_USER, "Lib/lib.blockcypher/Mix/PostHash", ["hash"], 2, "blockcypher"}];

% svc_blockchain merkletree urls
configure({svc_blockchain, merkletree_urls}, undefined) ->
  ["https://saas.sparkl.com"];

% svc_blockchain merkle tree generation interval (ms)
configure({svc_blockchain, merkletree_interval}, undefined) ->
  ?default_merkletree_interval;

% svc_blockchain merkle tree quorum minimum
configure({svc_blockchain, merkletree_quorum}, undefined) ->
  ?default_merkletree_quorum;

% Add the svc_blockchain yapp
configure({sse_yaws, yaws_app_mods}, Current) ->
  Current ++ [
    {"/svc_blockchain/", svc_blockchain_yapp}].
