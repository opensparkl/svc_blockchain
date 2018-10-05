"""
Copyright 2018 Sparkl Limited. All Rights Reserved.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
Authors: Andrew Farrell <ahfarrell@sparkl.com>
Common functions and definitions for various blockchain/event log types.
"""
import logging
import json
from hashlib import sha256
from ._checker import Checker
from .checker_exception import CheckerException
from .checker_counts import CheckerCounts
from .checker_state import CheckerState
from .stores import (
    LocalBlockStore,
    LocalEventStore,
)

# Common definitions
MONGO_DBTYPE = 'mongodb'
LOCAL_DBTYPE = 'local'
UNDEFINED = "undefined"
ID = "id"
PATH = "path"
DATA = "data"
TYPE = "type"
NAME = "name"
TXN = "txn"
MIXHASH = "mixhash"
BLOCKWRITER = 'writer'
BLOCKCLASS = 'class'
BLOCKOWNER = 'owner'
BLOCKID = 'id'
BLOCKIDX = 'idx'
EVENTSHASH = "eventshash"
BLOCK = "block"
SIGNED = 'sig'
BLOCKKEY = 'sigkey'
BUBBLEHASH = 'hash'
BLOCKSRC = 'src'
LASTBLOCKID = "lastblockid"
LASTBLOCKHASH = "lastblockhash"
FIRSTBLOCK = "firstblock"
TIME = "time"
ID_ = "_id"
IDX = 'idx'
FIRSTEV = 'first_event'
LASTEV = 'last_event'
EVENTHASH = "eventhash"
REFS = "refs"
REFHASH = "hash"
URLS = "urls"
URL = "url"
CONTENT = "content"
TAG = "tag"
PROOF = "proof"
EPOCH = "epoch"
ROOT = "root"
HASHES = "hashes"

EPOCH_URL = "{url}/svc_blockchain/epoch/{epoch}"
PROOF_URL = "{url}/svc_blockchain/proof/{signed}"

EV_DB = 'ev_db'
BC_DB = 'bc_db'
EV_COL = 'ev_col'
BC_COL = 'bc_col'
EV_URI = 'ev_uri'
BC_URI = 'bc_uri'

CHAIN_NODE = 'chain_node'
CHAIN_CLASS = 'chain_class'
CHAIN = 'blocks'

# Meta-data that should get removed from an event prior to hashing
SPARKL_METADATA = '__sparkl'

# A string that will not appear in the 'thing' being hashed.
WSP = '___wsp___sparkl___'

# Get logger for __name__.
LOGGER = logging.getLogger(__name__)

# Set this if no refs checking
ENV_SKIP_REFTEST = 'SKIP_REFTEST'

# SPARKL field names
FIELD_EVENT = 'event'
FIELD_CHAINBLOCK = 'chainblock'

# Messages
M_MT_EPOCH = "Merkle Tree Epoch: {epoch}"
M_FOR_BLOCK = "for block"
M_FOR_TXN = "for txn"
M_FOR_HASH = "for hash"
M_ON_REF = "on ref"
M_WITH_SIG = "with signature"
M_PUBKEY = "and key"
M_HASHES_NE = "Hashes not equal"
M_REFHASH_MISSING = "-- WARNING - Ref hash missing at {url}"
M_VERIFY_FAILED = "Verification failed"
M_KEYS_DIFF = "Signing keys on blockchain inconsistent"
M_TXN_LEFT = """
        Transactions in event database not on chain.
        You may wish to remove latest events and try again.
        Transactions include: """
M_BROKEN_CHAIN = "Broken chain - multiple chain fragments"
M_EVENTS_BAD = "Incorrect events"
M_REFS_BAD = "Bad external block reference/s"
M_EVENTSHASH_BAD = "Incorrect aggregate hash on txn events"

M_BLOCK_ON_CHAIN = "BLOCK IN CHAIN"
M_SKIPPED_USER = "-SKIPPED: DIFFERENT USER--"
M_SKIPPED_BUBBLE_BLOCK = "-SKIPPED: BUBBLED BLOCK (NO EVENTS)-"
M_CHECKING_BLOCK_HASH = "--CHECKING BLOCK HASH--"
M_CHECK_PASSED = "-CHECK PASSED-"
M_CHECKING_TXN = "--CHECKING TRANSACTION EVENTS IN BLOCK--"
M_BLOCK_PASSED = "-BLOCK PASSED-"
M_CHECKING_BUBBLES = "--CHECKING BUBBLE HASHES--"

M_INVALID_CHAIN = "\n-FAIL: Invalid chain.--- "
M_VALID_CHAIN = "\n-SUCCESS: Valid chain.---"
M_BUBBLE_DETAILS = "{prefix}\n--- from: {src}, chain: {chain}, " \
                      "with hash: {hash} ---"
M_FOR_EVENT = "for event"
M_BC_ACCESS = "\n-FAIL: Failed to access chain store.---"
M_EV_ACCESS = "\n-FAIL: Failed to access events store.---"
M_FETCHING = "**** Fetching {type_} proof from {url}"
M_WARN_CONN_ERROR = "---- WARNING: Connection error fetching url: {url}"
M_SUCCESS_URL_CHECK = "---- SUCCESS: Hash fetched from URL"
M_WARN_URL_CHECK = "---- WARNING: Cannot fetch hash from URL"
M_VERIFY_MTREE = "-- Verifying external merkletree ref url: {url} --"
M_VERIFY_MTREE_SUCCESS = " -- SUCCESS: Merkletree verification --"


def error(msg, extras):
    """
    Sets a message in an Exception instance, and raises it.
    """
    for pt1, pt2 in extras:
        msg += ", " + str(pt1) + ": " + str(pt2)
    raise CheckerException(msg)


def double_digest(thing):
    """
    Applies double SHA-256 hashing to a 'thing'.
    """
    LOGGER.debug(thing)
    digest = sha256(
        sha256(
            thing).digest()).hexdigest()
    digest = digest.lower()
    LOGGER.debug(digest)

    return digest


def preprocess(term_in):
    """
    Pre-processes a term (e.g. converting dicts into arrays)
    with the aim of getting it into a deterministic form when
    JSON-ified, and then converted to a string.  This final form is
    guaranteed to be the same as that generated by SPARKL for
    the equivalent Erlang term.  This allows us to repeat the double hashing
    carried out on events.
    """
    term_pp = preprocess_(term_in)
    term_out = json.dumps(
        term_pp).replace(" ", "").replace(WSP, " ")

    LOGGER.debug((term_in, term_out))

    return term_out


def preprocess_(term):
    """
    See preprocess/1.
    """
    if isinstance(term, dict):
        processed = []
        for key in sorted(term):
            processed.append([key, preprocess_(term[key])])
        return processed

    if isinstance(term, list):
        return [preprocess_(term_) for term_ in term]

    if term is None:
        return "null"

    if isinstance(term, str):
        return term.replace(" ", WSP)

    return term


def term_encode(term_):
    """
    Encodes a term, getting it ready for hashing.  See preprocess.
    """
    LOGGER.debug(term_)

    if term_.get(SPARKL_METADATA):
        term_.pop(SPARKL_METADATA)

    if term_.get(SIGNED):
        term_.pop(SIGNED)

    encoding = preprocess(term_).encode()
    LOGGER.debug(encoding)

    return encoding
