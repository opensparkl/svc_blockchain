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

Push status update message to Twitter.
E.g., used by merkle tree blockchain logic to push latest hashes to Twitter.
"""
import os
import logging
import requests
from blockcypher import double_ripemd160

LOGGER = logging.getLogger(__name__)

BC_URL = "https://api.blockcypher.com/v1/bcy/test/txs/data?token={token}"
TXN_URL = "https://api.blockcypher.com/v1/bcy/test/txs/{hash}" \
          "?limit=50&includeHex=true"

logging.basicConfig(
    filename="/tmp/blockcypher.log",
    filemode='w',
    format='%(asctime)s,%(msecs)d %(name)s %(levelname)s' +
    '%(message)s line:%(lineno)d',
    datefmt='%H:%M:%S',
    level=logging.DEBUG)


def onopen(service):
    """
    On service open.
    """
    bc_token = os.environ.get('BLOCKCYPHER_TOKEN')

    service.impl = {
        "Mix/Impl/PostHash": lambda r, c: post_hash(r, c, bc_token)}


def post_hash(request, callback, bc_token):
    """
    Push hash message to Blockcypher
    """
    hash_ = request["data"]["hash"]
    LOGGER.debug(hash_)
    try:
        hash_160 = double_ripemd160(hash_)
        LOGGER.debug(hash_160)

        bc_url = BC_URL.format(token=bc_token)
        LOGGER.debug(bc_url)

        payload = {'data': hash_160}
        txn_hash = requests.post(bc_url, data=payload).json()['hash']
        txn_url = TXN_URL.format(
            hash=txn_hash)
        LOGGER.debug(txn_hash)

        callback({
            "reply": "Ok",
            "data": {
                "url": txn_url,
                "hash160": hash_160}})
    except Exception as exc:
        callback({
            "reply": "Error",
            "data": {
                "reason": repr(exc)}})
