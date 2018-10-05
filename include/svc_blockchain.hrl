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
%%% @doc Blockchain include file

-define(prop_blockchain_spec, "blockchain.spec").
-define(attr_class, "chain").

-define(dets_prefix_blocks, "blocks").
-define(dets_prefix_merkle, "merkle").

-define(quorum_record_key, undefined).
-define(hashes_record_key, undefined).

-define(event_hash, "eventhash").
-define(event_txn, "txn").
-define(event_id, "id").
-define(event_idx, "idx").
-define(event_timestamp, "timestamp").
-define(event_ref, "ref").
-define(event_subject, "subject").
-define(event_subject_path, "path").
-define(event_subject_name, "name").
-define(event_datum_name, "name").
-define(event_datum_type, "type").
-define(event_tag, "tag").
-define(event_data, "data").
-define(event_meta, "meta").
-define(event_reason, "reason").

-define(mix_field_event, "event").
-define(mix_field_chainblock, "chainblock").

-define(block_lastid, "lastblockid").
-define(block_lasthash, "lastblockhash").
-define(block_mixid, "mix").
-define(block_mixdigest, "mixhash").
-define(block_firstev, "first_event").
-define(block_lastev, "last_event").
-define(block_id, "id").
-define(block_idx, "idx").
-define(block_writer, "writer").
-define(block_class, "class").
-define(block_owner, "owner").
-define(block_signed, "sig").
-define(block_key, "sigkey").
-define(block_hash, "hash").
-define(block_src, "src").
-define(block_eventshash, "eventshash").
-define(block_refs, "refs").

-define(value_data_event, <<"data_event">>).
-define(value_error_event, <<"error_event">>).
-define(value_removed, <<"__removed__">>).

-define(local_bc_col, "local").
-define(local_ev_col, "local").
-define(local_bc_dir, "blockchain").
-define(local_ev_dir, "events").

-define(default_merkletree_interval, 300000).
-define(default_merkletree_quorum, 1).
-define(default_genserver_timeout, 15000).
-define(default_block_interval, 2500).
-define(default_block_fwd_interval, 10000).
-define(default_blockchain_dir, ".blockchain").

-define(scripts_crypto_path, "scripts/crypto/").
-define(script_sign, "sign.py").
-define(script_verify, "verify.py").
-define(script_keygen, "keygen.py").

-define(dictkey_private, <<"privatekey">>).
-define(dictkey_public, <<"publickey">>).
-define(dictkey_signed, <<"signed">>).
-define(dictkey_verify, <<"verify">>).

-define(mt_param_hash, "hash").
-define(mt_param_hashes, "hashes").
-define(mt_param_root, "root").
-define(mt_param_url, "url").
-define(mt_param_urls, "urls").
-define(mt_param_epoch, "epoch").
-define(mt_param_proof, "proof").
-define(mt_param_timestamp, "timestamp").
-define(mt_param_signed, ?block_signed).
-define(mt_param_pubkey, ?block_key).
-define(mt_param_merkle, "merkle").
-define(mt_param_block, "block").
-define(mt_param_value, "value").
-define(mt_param_status, "status").
-define(mt_param_type, "type").

-define(json_content, <<"content">>).
-define(json_tag, <<"tag">>).

%% Delay inserted after starting service to
%% give time to connect
-define(post_start_delay, 3000).

-define(LOG_ERROR(Class, Error),
  ?ERROR([
    {class, Class},
    {error, Error},
    {stack, erlang:get_stacktrace()}]),
  {stop, {Class, Error}}).

-type(ed25519_pubkey() :: binary()).
-type(ed25519_privkey() :: binary()).
-type(ed25519_signature() :: binary()).
-type(sha256_double_hash() :: binary()).
-type(sha160_double_hash() :: binary()).
-type(merkle_tree_leaf() :: ed25519_signature()).
-type(merkle_tree_nonleaf() :: sha256_double_hash()).
-type(merkle_tree_node() :: merkle_tree_leaf() | merkle_tree_nonleaf() | string()).
-type(tree_epoch()   :: integer()).
-type(tree_proof()   :: list(sha256_double_hash())).

-record(svc_blockchain_merkle_proof, {
  proof = []         :: tree_proof(),
  epoch = undefined  :: tree_epoch() | undefined
}).

-record(svc_blockchain_merkle_hashes, {
  hashes = []        :: list({sha256_double_hash(), sha256_double_hash()}),
  epoch = undefined  :: tree_epoch() | undefined
}).

-record(svc_blockchain_merkle_epoch, {
  hashes = []        :: list({sha256_double_hash(), sha256_double_hash()}),
  epoch = undefined  :: tree_epoch() | undefined,
  pubkey = <<>>      :: ed25519_pubkey(),
  urls = []          :: list({string(), string()}),
  root = <<>>        :: sha256_double_hash(),
  timestamp          :: string() | undefined
}).

-record(svc_blockchain_merkle_quorum, {
  quorum = []        :: list({string(), integer()})
}).