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

Test support module for checking local events against local blockchain.
"""
import sys
import checker as ch
import logging
from ct_test import Args


def main():
    """
    Calls into the common chain checking logic to check chain integrity.
    """
    node_ = sys.argv[2]
    owner_ = sys.argv[3]

    if owner_ == 'undefined':
        owner_ = None

    if node_ == 'undefined':
        node_ = None

    args = Args(
        bc_uri=sys.argv[1],
        ev_uri=sys.argv[1],
        bc_type='local',
        ev_type='local',
        bc_col='blockchain',
        ev_col='events',
        ev_db=None,
        bc_db=None,
        owner=owner_,
        node=node_
    )

    chcheck = ch.Checker(args, False)
    chcheck.do_checking()
    sys.stdout.write(str(chcheck))


logging.basicConfig(
    filename="/tmp/l_check.py.log",
    filemode='w',
    format='%(asctime)s,%(msecs)d %(name)s %(levelname)s' +
    '%(message)s line:%(lineno)d',
    datefmt='%H:%M:%S',
    level=logging.INFO)

main()
