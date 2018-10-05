"""
Copyright (c) 2018 SPARKL Ltd. All Rights Reserved.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
Author <ahfarrell@sparkl.com> Andrew Farrell

SPARKL streaming chain check.
Mainly used for demo purposes.
Also shows how events and chain blocks can be accessed, as well as
their integrity verified.
"""
import threading
import queue as q
import logging
import json
import sys
import os
import checker as ch


LOGGER = logging.getLogger(__name__)

logging.basicConfig(
    filename="/tmp/stream.log",
    filemode='w',
    format='%(asctime)s,%(msecs)d %(name)s %(levelname)s' +
    '%(message)s line:%(lineno)d',
    datefmt='%H:%M:%S',
    level=logging.DEBUG)


def onopen(service):
    """
    On service open.
    """
    queue = q.Queue()

    service.impl = {
        "BlockForwarding/Impl/StreamEvent":
            lambda c: stream_event(queue, c),
        "BlockForwarding/Impl/StreamChainBlock":
            lambda c: stream_chainblock(queue, c)}

    stream_thread = threading.Thread(target=lambda: check_chain(queue))
    stream_thread.daemon = True
    stream_thread.start()

    redirect = os.environ.get('STREAMOUT_FILE')
    LOGGER.debug(redirect)
    if redirect:
        sys.stdout = open(redirect, 'a')


def stream_event(queue, consume):
    """
    Enqueue a streamed event.
    """
    LOGGER.debug(consume)

    event = consume["data"][ch.FIELD_EVENT]
    LOGGER.debug(event)

    queue.put((ch.FIELD_EVENT, json.loads(event)))


def stream_chainblock(queue, consume):
    """
    Enqueue a streamed chain block.
    """
    LOGGER.debug(consume)

    chainblock = consume["data"][ch.FIELD_CHAINBLOCK]
    LOGGER.debug(chainblock)

    queue.put((ch.FIELD_CHAINBLOCK, json.loads(chainblock)))


def check_chain(queue):
    """
    On-the-fly forward chain checking.
    """
    cache = {
        ch.FIELD_EVENT: {},
        ch.FIELD_CHAINBLOCK: {},
        ch.LASTBLOCKHASH: ch.UNDEFINED,
        ch.FIRSTBLOCK: None,
        ch.CHAIN: []
    }

    while True:
        what, data = queue.get()
        LOGGER.debug((what, data))

        if what == ch.FIELD_EVENT:
            txn_id = data[ch.TXN]

            txn_events = cache[ch.FIELD_EVENT].get(txn_id, [])
            txn_events.append(data)
            cache[ch.FIELD_EVENT][txn_id] = txn_events

        elif what == ch.FIELD_CHAINBLOCK:
            lastblockhash = data[ch.LASTBLOCKHASH]
            if lastblockhash != ch.UNDEFINED:
                cache[ch.CHAIN].append(lastblockhash)
            cache[ch.FIELD_CHAINBLOCK][lastblockhash] = data
            if not cache[ch.FIRSTBLOCK]:
                cache[ch.FIRSTBLOCK] = data

        advance_chaincheck(cache)
        sys.stdout.flush()


def advance_chaincheck(cache):
    """
    Advance chain checking as much as currently possible.
    """
    firstblock = cache[ch.FIRSTBLOCK]
    if not firstblock:
        return
    lastblockhash = cache[ch.LASTBLOCKHASH]
    LOGGER.debug(lastblockhash)

    while True:
        nextblock = cache[ch.FIELD_CHAINBLOCK].get(lastblockhash)
        if not nextblock and not firstblock == ch.UNDEFINED:
            nextblock = firstblock
        LOGGER.debug(nextblock)
        if nextblock:
            # we have received the next block in the chain
            genblockhash = block_chaincheck(cache, lastblockhash, nextblock)
            if genblockhash == lastblockhash:
                break  # from while
            else:
                lastblockhash = genblockhash
                firstblock = cache[ch.FIRSTBLOCK] = \
                    ch.UNDEFINED  # we have moved on from first
        else:
            break  # from while
    cache[ch.LASTBLOCKHASH] = lastblockhash


def block_chaincheck(cache, lastblockhash, chainblock):
    """
    Chain check a block.
    """
    txn_id = chainblock[ch.TXN]
    LOGGER.debug(txn_id)

    sig = chainblock[ch.SIGNED]

    # Generate the hash for the block
    genblockhash = ch.double_digest(
        ch.term_encode(chainblock))
    LOGGER.debug("Generated Block Hash: %s", genblockhash)

    event_ids = eventmap = None
    block_eventshash = eventshash = ch.UNDEFINED

    if not chainblock.get(ch.BUBBLEHASH):
        txn_id = chainblock[ch.TXN]
        events = cache[ch.FIELD_EVENT].get(txn_id, [])

        # sort events by IDX
        eventmap, event_ids = ch.Checker.g_sort_events(chainblock, events)

        # check individual events, and compile hash
        for eventid in event_ids:
            event = eventmap[eventid]
            _genhash, eventshash = \
                ch.Checker.g_check_event(event, eventshash)

        block_eventshash = chainblock.get(ch.EVENTSHASH)

        LOGGER.debug(block_eventshash)
        LOGGER.debug(eventshash)

        if eventshash != block_eventshash:
            return lastblockhash

        LOGGER.debug(chainblock)
        # verify signature
        ch.Checker.g_verify_sig(
            genblockhash,
            sig,
            chainblock[ch.BLOCKKEY])

    print("-{prefix} with transaction id: {txn}-".format(
        prefix=ch.M_BLOCK_ON_CHAIN,
        txn=txn_id))

    print(ch.M_CHECKING_TXN)

    # the block and its events are correct
    base_idx = eventmap[event_ids[0]][ch.IDX] - 1
    for eventid in event_ids:
        event = eventmap[eventid]
        idx = "{idx}.".format(idx=event[ch.IDX]-base_idx)
        sys.stdout.write("{idx:<4} PATH: {path}. ".format(
            idx=idx, path=event[ch.PATH]))
        fields = event[ch.DATA]
        for field in fields.keys():
            sys.stdout.write("{name}:{value}, ".format(
                name=field, value=fields[field]))
        print("\nEVENT ID: {id}, HASH: {hash}".format(
            id=event[ch.ID], hash=event[ch.EVENTHASH]))

    print("--GENERATED v CHAINED EVENTS HASH--")
    print("---{ev}".format(
        ev=eventshash))
    print("---{bl}".format(
        bl=block_eventshash))
    print("--SPARKL FOLDER SHA-256 HASH: {hash}".format(
        hash=chainblock[ch.MIXHASH]))
    print("--BLOCK SHA-256 HASH: {hash}".format(
        hash=genblockhash))

    print(ch.M_BLOCK_PASSED)

    return genblockhash
