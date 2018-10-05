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
Chain checker cli front-end logic.
"""
import sys
import logging
import argparse
from os.path import expanduser, join
import checker as ch

logging.basicConfig(
    filename="/tmp/check.py.log",
    filemode='w',
    format='%(asctime)s,%(msecs)d %(name)s %(levelname)s' +
    '%(message)s line:%(lineno)d',
    datefmt='%H:%M:%S',
    level=logging.DEBUG)

MONGO_URI = 'mongodb://sparkl:sparkl@127.0.0.1:27017/sparkl'
MONGO_DB = 'sparkl'
MONGO_EVCOL = 'events'
MONGO_BCCOL = 'blockchain'

LOCAL_URI = join(expanduser("~"), '.blockchain', 'local')


def main():
    """
    Parses arguments, setting appropriate defaults, and then invokes
    checking.
    """
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description="""
        SPARKL Chain Checking Tool.
        Examples:
        For local blockchain and local events, do:
            python -m checker
        For local blockchain and mongo events, do:
            python -m checker --evtype=mongodb
        For mongo blockchain and mongo events, do:
            python -m checker --evtype=mongodb --bctype=mongodb

        where:
            for local, defaults are:
                evuri = bcuri = {local_uri}

            for mongo, defaults are:
                evuri = bcuri = {mongo_uri}
                evdb = bcdb = {mongo_db}
                evcol = {mongo_evcol}
                bccol = {mongo_bccol}.
           """.format(
               local_uri=LOCAL_URI,
               mongo_uri=MONGO_URI,
               mongo_db=MONGO_DB,
               mongo_evcol=MONGO_EVCOL,
               mongo_bccol=MONGO_BCCOL))

    parser.add_argument(
        "--evuri", action="store", dest="ev_uri",
        help="events db uri, for non-local")
    parser.add_argument(
        "--evdb", action="store", dest="ev_db", default=MONGO_DB,
        help="events db, for non-local")
    parser.add_argument(
        "--evcol", action="store", dest="ev_col", default=MONGO_EVCOL,
        help="events db col, for non-local")
    parser.add_argument(
        "--evtype", action="store", dest="ev_type",
        default=ch.LOCAL_DBTYPE, help="events db type")
    parser.add_argument(
        "--bcuri", action="store", dest="bc_uri",
        help="blockchain db uri, for non-local")
    parser.add_argument(
        "--bcdb", action="store", dest="bc_db", default=MONGO_DB,
        help="blockchain db, for non-local")
    parser.add_argument(
        "--bccol", action="store", dest="bc_col", default=MONGO_BCCOL,
        help="blockchain db col, for non-local")
    parser.add_argument(
        "--bctype", action="store", dest="bc_type",
        default=ch.LOCAL_DBTYPE, help="blockchain db type")
    parser.add_argument(
        "--user", action="store", dest="owner",
        help="user filter (defaults to all users)")
    parser.add_argument(
        "--node", action="store", dest="node",
        help="node filter (defaults to all nodes)")

    args = parser.parse_args()

    if not args.bc_uri:
        if args.bc_type == ch.LOCAL_DBTYPE:
            args.bc_uri = LOCAL_URI
        elif args.bc_type == ch.MONGO_DBTYPE:
            args.bc_uri = MONGO_URI

    if not args.ev_uri:
        if args.ev_type == ch.LOCAL_DBTYPE:
            args.ev_uri = LOCAL_URI
        elif args.ev_type == ch.MONGO_DBTYPE:
            args.ev_uri = MONGO_URI

    chcheck = ch.Checker(args)
    chcheck.do_checking()

    if chcheck.counts.result:
        print("Blocks Checked: " + str(chcheck.counts.get_checked()))
        print("Blocks Bubbled: " + str(chcheck.counts.get_bubbled()))
        print("Blocks Skipped: " + str(chcheck.counts.get_skipped()))
        print("Blocks Referenced: " + str(chcheck.counts.get_refd()))
        sys.exit(0)
    else:
        sys.exit(1)


main()
