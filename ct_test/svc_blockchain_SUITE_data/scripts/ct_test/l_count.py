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

Test support module for counting local events and blockchain blocks.
"""
import sys
import checker as ch
import logging
from ct_test import Args


def main():
    """
    Calls into the common chain checking logic to get block and event counts.
    """
    chaindir = sys.argv[1]
    node = sys.argv[2]

    args = Args(
        bc_uri=chaindir,
        ev_uri=chaindir,
        bc_type='local',
        ev_type='local',
        bc_col='blockchain',
        ev_col='events',
        ev_db=None,
        bc_db=None,
        owner=None,
        node=None
    )

    eventstore = ch.LocalEventStore(args)
    blockstore = ch.LocalBlockStore(args)
    blockstore.set_chain(node, 'blockchain')
    resultmsg = str(blockstore.block_count()) + ":" + \
                str(eventstore.events_count())
    sys.stdout.write(resultmsg)

logging.basicConfig(
    filename="/tmp/l_count.py.log",
    filemode='w',
    format='%(asctime)s,%(msecs)d %(name)s %(levelname)s' +
    '%(message)s line:%(lineno)d',
    datefmt='%H:%M:%S',
    level=logging.INFO)

main()
