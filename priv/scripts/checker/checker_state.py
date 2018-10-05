"""
Copyright (c) 2018 SPARKL Limited. All Rights Reserved.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
Author <ahfarrell@sparkl.com> Andrew Farrell.

Chainchecker State class
"""
import checker as ch


class CheckerState():
    """
    General state class.
    """
    def __init__(self):
        self.bubbles = self.chains = []
        self.hashes = {}
        self.block_state = self.orig_key = None
        self.refhashes = []
        self.genhashes = []

    def init_chain(self):
        """
        Initialises fresh chain block state.
        :return:
        """
        self.block_state = CheckerBlockState()

    def append_bubble_hash(self, block_hash):
        """
        Appends record of bubble hash for particular source node
        """
        # Append the generated hash to a list of saved hashes for blocks
        node_hashes = self.hashes.get(
            self.block_state.block_writer, {})
        chain_hashes = node_hashes.get(
            self.get_block_class(), [])
        chain_hashes.append(block_hash)
        node_hashes[self.get_block_class()] = chain_hashes
        self.hashes[self.block_state.block_writer] = node_hashes

    def check_bubbled_hash(self, bsrc, bclass, bhash):
        """
        Checks that a bubble hash exists in the given source chain.
        :return:
        """
        node_hashes = self.hashes.get(bsrc, {})
        chain_hashes = node_hashes.get(bclass, [])
        return bhash in chain_hashes

    def prepare_block(self, blockstore):
        """
        Prepare next block for checking.
        """
        block_ = blockstore.get_block(
            self.get_block_id())
        self.block_state.save_block(block_)

    def get_block(self):
        """
        Returns the original block, as dict.
        :return: block
        """
        return self.block_state.block

    def get_txn(self):
        """
        Returns txn id.
        :return: txn
        """
        return self.block_state.txn

    def get_bubble_hash(self):
        """
        Returns the hash property of a bubbled block, if present.  None
        otherwise.
        :return: bubble_hash
        """
        return self.block_state.bubble_hash

    def get_block_hash(self):
        """
        Returns the block hash given by 'lastblockhash' property of previously
        checked block.
        :return: block_hash
        """
        return self.block_state.block_hash

    def get_block_id(self):
        """
        Returns the block id given by 'lastblockid' property of previously
        checked block.
        :return: block_id
        """
        return self.block_state.block_id

    def get_block_class(self):
        """
        Returns the block class of block.
        :return: block_class
        """
        return self.block_state.block_class

    def get_block_key(self):
        """
        Returns the signing key of block.
        :return: block_key
        """
        return self.block_state.block_key

    def get_block_sig(self):
        """
        Returns the signature on the block (signed generated block hash)
        :return: block_sig
        """
        return self.block_state.block_sig

    def get_block_src(self):
        """
        Returns the block source for a bubbled chain block.
        :return: block_src
        """
        return self.block_state.block_src

    def get_block_owner(self):
        """
        Returns the owner (user) of a block.
        :return: block_owner
        """
        return self.block_state.block_owner

    def get_events_hash(self):
        """
        Returns the running event hash of a block.
        :return: events_hash
        """
        return self.block_state.events_hash

    def get_refs(self):
        """
        Returns the external references of a block.
        :return: refs
        """
        return self.block_state.refs

    def add_refhash(self, blockhash):
        """
        Adds a hash to outstanding ref block hashes.
        This should be empty by the end of checking.
        """
        self.refhashes.append(blockhash)

    def get_refhashes(self):
        """
        Gets outstanding ref block hashes.
        """
        return self.refhashes

    def save_genhash(self, genhash):
        """
        Saves generated hashes for purpose of checking
        whether the latest hash satisfies the head of the saved ref hashes.
        """
        self.genhashes.append(genhash)
        try:
            if not self.refhashes:
                return
            idx = self.genhashes.index(self.refhashes[0])
            self.refhashes = self.refhashes[1:]
            self.genhashes = self.genhashes[idx+1:]
        except ValueError:
            pass

    def save_hash(self):
        """
        Saves the lastblockhash, lastblockid of the current block for use
        next loop iteration.
        """
        self.block_state.save_hash()


class CheckerBlockState():
    """
    Block state class.
    """
    def __init__(self):
        self.block = self.block_hash = self.block_id = self.txn = None
        self.block_key = self.block_sig = self.bubble_hash = None
        self.block_writer = self.block_class = self.block_src = None
        self.block_owner = self.events_hash = self.refs = None

    def save_hash(self):
        """
        Saves the lastblockhash, lastblockid of the current block for use
        next loop iteration.
        """
        self.block_hash = self.block[ch.LASTBLOCKHASH]
        self.block_id = self.block[ch.LASTBLOCKID]

    def save_block(self, block):
        """
        Saves block state from original block in class properties, for
        convenience.
        """
        self.block = block
        self.txn = block.get(ch.TXN)
        self.block_key = block.get(ch.BLOCKKEY)
        self.block_sig = block.get(ch.SIGNED)
        self.bubble_hash = block.get(ch.BUBBLEHASH)
        self.block_writer = block.get(ch.BLOCKWRITER)
        self.block_class = block.get(ch.BLOCKCLASS)
        self.block_src = block.get(ch.BLOCKSRC)
        self.block_owner = block.get(ch.BLOCKOWNER)
        self.events_hash = block.get(ch.EVENTSHASH)
        self.refs = block.get(ch.REFS, {})
