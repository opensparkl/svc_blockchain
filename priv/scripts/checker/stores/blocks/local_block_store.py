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
Local chain block store.
"""
import os
import json
import checker as ch
from .abstract_block_store import BlockStore


class LocalBlockStore(BlockStore):
    """
    Local chain block store.
    """
    def __init__(self, args):
        super(LocalBlockStore, self).__init__(__name__, args)

        self.uri = os.path.join(args.bc_uri, args.bc_col)

        self.chain_files = []
        self.chain_class = None
        self.chain_node = None
        self.chain = {}
        self.logger.debug("Store uri: %s", self.uri)

    def get_chains(self):
        """
        Generates list of local chains available.
        """
        nodes = [node for node in os.listdir(self.uri)]
        chains = []
        for node in nodes:
            node_dir = os.path.join(self.uri, node)
            chains.extend([(node, cclass) for cclass in os.listdir(node_dir)])
        self.logger.debug("Chains: %s", str(chains))
        return chains

    def block_count(self):
        """
        Gets a block count for the currently set blocks.
        Used for test purposes only.
        """
        chain_dir = os.path.join(
            self.uri, self.chain_node, self.chain_class)
        count = 0
        for chain_file in self.chain_files:
            count += sum(
                1 for _line in open(os.path.join(chain_dir, chain_file)))
        return count

    def set_chain(self, node, cclass):
        """
        Set the current blocks.
        """
        self.chain_node = node
        self.chain_class = cclass

        chain_dir = os.path.join(self.uri, node, cclass)
        self.chain_files = sorted(os.listdir(chain_dir), key=int)
        self.logger.debug(self.chain_files)

    def get_block(self, blockid):
        """
        Gets a blocks block, given blockid.
        """
        last_block_id = self.refresh_chain(blockid)
        if not blockid:
            blockid = last_block_id

        block = self.chain[blockid][-1]
        self.logger.debug(block)

        if len(self.chain[blockid]) == 1:
            self.chain.pop(blockid)
        else:
            self.chain[blockid] = self.chain[blockid][0:-1]
        return block

    def refresh_chain(self, blockid):
        """
        Refreshes the current blocks from most recent
        blocks file not yet processed.
        """
        last_block_id = None

        chain_len = len(self.chain)
        self.logger.debug(blockid)
        self.logger.debug(str(self.chain.get(blockid)))
        self.logger.debug(chain_len)
        self.logger.debug(self.chain_files)

        if chain_len == 0:
            chain_file = self.chain_files[-1]
            self.chain_files = self.chain_files[:-1]

            with open(
                    os.path.join(
                        self.uri,
                        self.chain_node,
                        self.chain_class,
                        chain_file), "r") as blocks_:

                blocks = blocks_.readlines()
                if not blockid:
                    last_block_id = json.loads(blocks[-1])[ch.BLOCKID]

                for block_ in blocks:
                    block = json.loads(block_.strip())
                    blockid = block[ch.BLOCKID]
                    txn_blocks = self.chain.get(blockid, [])
                    txn_blocks.append(block)
                    self.chain[blockid] = txn_blocks

                self.logger.debug("Blocks: %s", str(self.chain))
        return last_block_id
