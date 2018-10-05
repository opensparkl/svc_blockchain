#!/usr/bin/python
"""
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
Copyright 2018 Sparkl Limited. All Rights Reserved.
Authors: Andrew Farrell <ahfarrell@sparkl.com>
Main checker class
"""
import sys
import os
import logging
import importlib
import binascii
import requests
import ed25519
import checker as ch


class Checker():
    """
    Chain checker functionality
    """
    def __init__(self, args, console=True):
        self.counts = ch.CheckerCounts()
        self.check_state = ch.CheckerState()

        self.console = console
        self.logger = logging.getLogger(__name__)

        self.args = args

        if args.node == ch.UNDEFINED:
            self.args.node = None

        if args.owner == ch.UNDEFINED:
            self.args.owner = None

        if args.ev_type == ch.LOCAL_DBTYPE:
            self.eventstore = ch.LocalEventStore(args)

        if args.bc_type == ch.LOCAL_DBTYPE:
            self.blockstore = ch.LocalBlockStore(args)

    def __str__(self):
        return str(self.counts)

    @staticmethod
    def g_verify_sig(refmsg, signed, pubkey):
        """
        Verifies supplied signature (signed) against ED25519 public key and
        message.
        :param refmsg: Reference message
        :param signed: Signature to check
        :param pubkey: ED25519 public key
        :return: True if signature is verified successfully.
        """
        if signed == ch.UNDEFINED:
            return

        signed_b = binascii.a2b_base64(
            signed)
        pub_b = binascii.a2b_base64(
            pubkey)
        pub_ = ed25519.VerifyingKey(
            pub_b)

        try:
            pub_.verify(
                signed_b, refmsg.encode())
        except ed25519.BadSignatureError:
            ch.error(
                ch.M_VERIFY_FAILED,
                [(ch.M_ON_REF, refmsg),
                 (ch.M_WITH_SIG, signed),
                 (ch.M_PUBKEY, pubkey)])

    def msg(self, message, crop=False):
        """
        Writes a message to stdout if 'console' is True
        :param message: Message to write
        :param crop: whether to crop the new-line
        """
        if self.console:
            sys.stdout.write(message)
            if not crop:
                sys.stdout.write("\n")
            sys.stdout.flush()

    def check_block(self):
        """
        Checks individual bubble or regular chain block.
        """
        if self.check_state.get_bubble_hash():
            # If the block has a 'hash' value inside it
            # (distinct from 'lastblockhash'), it is a bubbled block.
            # In this case, we save the bubbled hash to ensure that it
            # exists on its source blockchain also.
            #
            self.counts.incr_bubbled()
            bsrc = self.check_state.get_block_src()
            bclass = self.check_state.get_block_class()
            bhash = self.check_state.get_bubble_hash()
            self.check_state.bubbles.append(
                (bsrc, bclass, bhash))

            self.msg(ch.M_BUBBLE_DETAILS.format(
                prefix=ch.M_SKIPPED_BUBBLE_BLOCK,
                src=bsrc, chain=bclass, hash=bhash))
        else:
            # Regular block
            #
            txn = self.check_state.get_txn()
            self.msg("-{prefix} with transaction id: {txn}-".format(
                prefix=ch.M_BLOCK_ON_CHAIN,
                txn=txn))

            blockowner = self.check_state.get_block_owner()
            if self.args.owner and not blockowner == self.args.owner:
                self.counts.incr_skipped()
                self.msg(ch.M_SKIPPED_USER)
            else:
                self.counts.incr_checked()
                if self.eventstore.is_event_txn(
                        blockowner, txn):
                    # Check block
                    #
                    self.check_regular_block()
                else:
                    raise ch.CheckerException(ch.M_TXN_LEFT)
                self.check_refs()
                self.msg(ch.M_BLOCK_PASSED)

    def check_chain(self):
        """
        Checks a single chain against an event database.
        """

        while True:
            # Get next block
            self.check_state.prepare_block(self.blockstore)

            # Generate the hash for the block
            genblockhash = ch.double_digest(
                ch.term_encode(self.check_state.get_block()))
            self.logger.debug("Generated Block Hash: %s", genblockhash)

            self.check_state.append_bubble_hash(
                genblockhash)

            # Need to check the generated block hash matches the one we have
            # saved from the previously checked block (in checking the chain
            # backwards).
            #
            block_key = self.check_state.get_block_key()
            if self.check_state.get_block_hash():
                if not block_key == self.check_state.orig_key:
                    ch.error(
                        ch.M_KEYS_DIFF,
                        [(block_key, self.check_state.orig_key)])

                self.msg(ch.M_CHECKING_BLOCK_HASH, True)

                if not genblockhash == self.check_state.get_block_hash():
                    txn = self.check_state.get_txn()
                    ch.error(
                        ch.M_HASHES_NE,
                        [(ch.M_FOR_BLOCK, txn)])
                self.msg(ch.M_CHECK_PASSED)
            else:
                self.check_state.orig_key = block_key

            # Verify the signature on the block, using genblockhash
            #
            Checker.g_verify_sig(
                genblockhash,
                self.check_state.get_block_sig(),
                block_key)

            self.check_block()
            self.check_state.save_hash()
            self.check_state.save_genhash(genblockhash)

            if self.check_state.get_block_id() == ch.UNDEFINED:
                refhashes = self.check_state.get_refhashes()
                if refhashes:
                    ch.error(
                        ch.M_REFS_BAD,
                        [(ch.M_VERIFY_FAILED, refhashes)])
                return

    @staticmethod
    def g_dict_content(thing):
        """
        Extracts a dict of key/value pairs
        from content retrieved from svc_blockchain.
        """
        if not thing.get(ch.CONTENT):
            return None
        content = thing[ch.CONTENT]
        result = {}
        for item in content:
            result[item[ch.TAG]] = item.get(ch.CONTENT)
        return result

    @staticmethod
    def g_check_refs(refs, msg_, logger_):
        """
        Validates any external chain block references.
        """
        if os.getenv(ch.ENV_SKIP_REFTEST):
            return None, False

        add_refcnt = refhash = None
        if refs:
            refhash = refs[ch.REFHASH]
            urls = refs[ch.URLS]
            for url in urls.keys():
                msg_(ch.M_VERIFY_MTREE.format(url=url))
                ref = urls[url]
                logger_(ref)

                Checker.g_verify_sig(
                    refhash, ref[ch.SIGNED], ref[ch.BLOCKKEY])

                proof_url = ch.PROOF_URL.format(
                    url=url, signed=ref[ch.SIGNED])
                logger_(proof_url)

                try:
                    proof_ = requests.get(proof_url).json()
                    logger_(proof_)

                    proof = Checker.g_dict_content(proof_)
                    logger_(proof)

                    if not proof:
                        # this will only happen in 'streamed' mode,
                        # which will retry
                        return None, False

                    # Check that the sig given in the
                    # record of the push is valid wrt refhash
                    Checker.g_verify_sig(
                        proof[ch.PROOF][0],
                        proof[ch.SIGNED][0],
                        proof[ch.BLOCKKEY][0])

                    add_refcnt = Checker.g_check_epoch(
                        proof, url, ref, refhash, logger_, msg_)

                except requests.exceptions.ConnectionError:
                    msg_(ch.M_WARN_CONN_ERROR.format(url=proof_url))

        msg_(ch.M_VERIFY_MTREE_SUCCESS)
        return refhash, add_refcnt

    @staticmethod
    def g_check_epoch(proof, url, ref, refhash, logger_, msg_):
        """
        Checks an epoch record referenced in a block ref proof.
        """
        # 1. Fetch the epoch record
        epoch_idx = proof[ch.EPOCH][0]
        logger_(epoch_idx)
        msg_(ch.M_MT_EPOCH.format(epoch=epoch_idx))

        epoch_url = ch.EPOCH_URL.format(
            url=url, epoch=epoch_idx)
        logger_(epoch_url)

        epoch_ = requests.get(epoch_url).json()
        logger_(epoch_)

        epoch = Checker.g_dict_content(epoch_)
        logger_(epoch)

        proof_key = proof[ch.BLOCKKEY][0]
        epoch_key = epoch[ch.BLOCKKEY][0]
        logger_((proof_key, epoch_key))

        if epoch_key != proof_key:
            ch.error(
                ch.M_KEYS_DIFF,
                [(epoch_key, proof_key)])

        # 2.  Prove merkle path
        merkle_path = proof[ch.PROOF][0].split(',')
        logger_(merkle_path)

        path_root = merkle_path[-1].strip()
        epoch_root = epoch[ch.ROOT][0]
        logger_((path_root, epoch_root))

        if path_root != epoch_root:
            ch.error(ch.M_HASHES_NE, [(path_root, epoch_root)])

        epoch_leaves = [h[ch.SIGNED][0]
                        for h in [Checker.g_dict_content(h_)
                                  for h_ in epoch[ch.HASHES]]]
        logger_(epoch_leaves)

        curhash = ref[ch.SIGNED]
        leaf_idx = epoch_leaves.index(curhash)

        for phash_ in merkle_path[:-1]:
            phash = phash_.strip()
            if leaf_idx % 2 == 0:
                concat_hash = (curhash + phash).encode()
            else:
                concat_hash = (phash + curhash).encode()
            curhash = ch.double_digest(concat_hash)
            leaf_idx = int(leaf_idx / 2)

        logger_((path_root, curhash))
        if path_root != curhash:
            ch.error(ch.M_HASHES_NE, [(path_root, curhash)])

        # 3. Verify that the (sig, hash) pair are in hashes
        epoch_hashes = epoch[ch.HASHES]
        logger_(epoch_hashes)

        ehashes = {}
        for ehash_ in epoch_hashes:
            ehash = Checker.g_dict_content(ehash_)
            ehashes[ehash[ch.REFHASH][0]] = ehash[ch.SIGNED][0]
        logger_(ehashes)

        # 4. Verify that refhash is in the hashes of the epoch
        if refhash not in ehashes:
            ch.error(ch.M_REFHASH_MISSING, [(refhash, ehashes)])
        if ehashes[refhash] != ref[ch.SIGNED]:
            ch.error(ch.M_HASHES_NE,
                     [(ehashes[refhash], ref[ch.SIGNED])])

        # 5. Validate the epoch URLs
        return Checker.g_check_epoch_urls(epoch, logger_, msg_)

    @staticmethod
    def g_check_epoch_urls(epoch, logger_, msg_):
        """
        Validates that blockcypher, twitter, etc, refs contain
        the root hash of an epoch record.
        """
        add_refcnt = False
        epoch_urls = epoch[ch.URLS]
        epoch_root = epoch[ch.ROOT][0]
        logger_(epoch_urls)

        if epoch_urls:
            for eurl_ in epoch_urls:
                eurl = Checker.g_dict_content(eurl_)

                type_ = eurl[ch.TYPE][0]
                url = eurl[ch.URL][0]
                module = importlib.import_module(type_)
                hash_result = module.check_hash(url, epoch_root)

                msg_(ch.M_FETCHING.format(type_=type_, url=url))

                present = False
                output = None

                logger_((type_, present, output))

                if hash_result:
                    present, output = hash_result
                    if present:
                        msg_(ch.M_SUCCESS_URL_CHECK)
                        msg_(output)
                        add_refcnt = True
                    else:
                        msg_(ch.M_REFHASH_MISSING.format(url=url))
                else:
                    msg_(ch.M_WARN_URL_CHECK)
        return add_refcnt

    def check_refs(self):
        """
        Validates any external chain block references.
        """
        refs = self.check_state.get_refs()
        refhash, add_refcnt = \
            Checker.g_check_refs(refs, self.msg, self.logger.debug)
        if refhash:
            if add_refcnt:
                self.counts.incr_refd()
            self.check_state.add_refhash(refhash)

    def check_regular_block(self):
        """
        Checks an individual chain block.  Checks the running hash stored
        in it correponds to the hashes of the individual events
        - also checked.
        """
        self.msg(ch.M_CHECKING_TXN)
        txn = self.check_state.get_txn()

        eventmap, blockevents = Checker.g_sort_events(
            self.check_state.get_block(),
            self.eventstore.get_events(
                self.check_state.get_block_owner(),
                txn),
            self.logger.debug)
        self.logger.debug(blockevents)

        eventcnt = 0
        eventshash = ch.UNDEFINED
        for eventid in blockevents:
            event = eventmap[eventid]
            eventshash = self.check_event(event, eventshash)
            eventcnt += 1

        rem_eventcnt = self.eventstore.pop_events(
            txn, blockevents)
        if rem_eventcnt < 0:
            ch.error(ch.M_EVENTS_BAD, [(ch.M_FOR_TXN, txn)])

        self.msg(eventshash)

        block_eventshash = self.check_state.get_events_hash()

        if eventshash != block_eventshash:
            self.logger.debug(block_eventshash)
            self.logger.debug(eventshash)

            ch.error(ch.M_EVENTSHASH_BAD,
                     [(ch.M_FOR_TXN, txn),
                      (block_eventshash, eventshash)])

    @staticmethod
    def g_sort_events(chainblock, events, logger_=None):
        """
        Compiles events into event map based on their id, and returns
        them sorted by event id.
        :param events: raw events
        :return: pair: event map by event id, sorted list of event ids
        """
        sorting = []
        eventmap = {}

        firstevent = chainblock[ch.FIRSTEV]
        lastevent = chainblock[ch.LASTEV]

        if logger_:
            logger_((firstevent, lastevent, events))

        for event in events:
            evidx = event[ch.IDX]
            included = (firstevent > lastevent and
                        (evidx >= firstevent or evidx <= lastevent)) or \
                       (firstevent <= evidx <= lastevent)

            if included:
                eventmap[event[ch.ID]] = event
                sorting.append((event.get(ch.IDX), event))
        sorting.sort(key=lambda x: x[0])
        return eventmap, [event_[ch.ID] for (_key, event_) in sorting]

    @staticmethod
    def g_check_event(event, eventshash):
        """
        Checks a single event by validating its recorded hash.
        :param event: the event
        :param eventshash: the current running hash
        :return: updated running hash
        """
        evhash = event.pop(ch.EVENTHASH)
        evenc = ch.term_encode(event)
        genhash = ch.double_digest(evenc)
        event[ch.EVENTHASH] = evhash

        if genhash != evhash:
            ch.error(ch.M_HASHES_NE, [(ch.M_FOR_EVENT, event[ch.ID])])

        eventshash = eventshash + evhash
        eventshash = ch.double_digest(eventshash.encode())
        return genhash, eventshash

    def check_event(self, event, eventshash):
        """
        Checks a single event by validating its recorded hash.
        :param event: the event
        :param eventshash: the current running hash
        :return: updated running hash
        """
        genhash, eventshash = Checker.g_check_event(event, eventshash)
        self.logger.debug(genhash)
        self.logger.debug(eventshash)

        self.msg("{prefix:<14} {hash}".format(
            prefix=event[ch.ID], hash=genhash))
        return eventshash

    def clean_up(self):
        """
        Post-checking clean up, returns a 'failed' status.
        """
        self.eventstore.drop_ev_col()

    @staticmethod
    def g_filter_chains(chains, node_):
        """
        Filters set of available chains based on source node.
        :param chains: Chains available.
        :param node_: Node to filter on. Can be None to keep "all nodes".
        :return: Set of filtered chains.
        """
        return [(node, col) for
                (node, col) in chains if
                not node or not node_ or node == node_]

    def loop_chain_check(self):
        """
        Loop through the chains, checking each in turn
        """
        for chain in self.check_state.chains:
            self.check_state.init_chain()
            details = "type: {type}, uri: {uri}, db: {db}, col: {col} ---"
            self.msg("")
            self.msg(
                "-Checking CHAIN--------------------------------------------")
            self.msg("--- Events: {ev_details} ".format(
                ev_details=details.format(
                    type=self.args.ev_type, uri=self.args.ev_uri,
                    db=self.args.ev_db, col=self.args.ev_col)))
            self.msg("--- Blockchain: type: {bc_details} ".format(
                bc_details=details.format(
                    type=self.args.bc_type, uri=self.args.bc_uri,
                    db=self.args.bc_db, col=self.args.bc_col)))
            self.msg("")

            try:
                self.blockstore.set_chain(*chain)
            except IndexError:
                self.msg(ch.M_BC_ACCESS)
                raise ch.CheckerException()

            try:
                self.check_chain()
            except ch.CheckerException as check_exc:
                self.msg(ch.M_INVALID_CHAIN)
                self.msg(str(check_exc))
                raise ch.CheckerException()

    def do_checking(self):
        """
        Do chain checking! See: do_checking_.
        """
        try:
            self.do_checking_()
        except ch.CheckerException:
            self.clean_up()

    def do_checking_(self):
        """
        Do chain checking!
        """
        self.check_state.chains = Checker.g_filter_chains(
            self.blockstore.get_chains(), self.args.node)

        self.loop_chain_check()

        self.msg(ch.M_CHECKING_BUBBLES)
        for (bsrc, bclass, bhash) in self.check_state.bubbles:
            self.msg(ch.M_BUBBLE_DETAILS.format(
                prefix=ch.M_CHECKING_BLOCK_HASH,
                src=bsrc, chain=bclass, hash=bhash))

            if self.check_state.check_bubbled_hash(bsrc, bclass, bhash):
                self.msg(ch.M_CHECK_PASSED)
            else:
                self.msg(ch.M_INVALID_CHAIN)
                raise ch.CheckerException()

        events_left = self.eventstore.events_left()
        events_left_cnt = len(events_left)

        if events_left_cnt > 0:
            self.msg(ch.M_INVALID_CHAIN)
            self.msg(ch.M_TXN_LEFT)
            self.msg(str(events_left))
            raise ch.CheckerException()

        self.msg(ch.M_VALID_CHAIN)
        self.clean_up()
        self.counts.result = True
