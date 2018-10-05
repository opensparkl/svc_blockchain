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

Blockcypher merkle tree base functions.
"""
import hashlib
import logging
from time import sleep
import requests

MSG_DATA_RCV = "Data Output retrieved from Blockcypher: {output}"


def double_ripemd160(thing):
    """
    Applies double RIPEMD-160 hashing to a 'thing'.
    """
    ripemd = hashlib.new('ripemd160')
    ripemd.update(thing.encode())
    digest1 = ripemd.digest()

    ripemd = hashlib.new('ripemd160')
    ripemd.update(digest1)
    digest2 = ripemd.hexdigest()
    return digest2.lower()


def check_hash(url_, hash_):
    """
    Checks that the given double 256-hash exists at
    blockcypher url,
    when double ripemd160 is applied to the hash value.
    """
    try:
        logger = logging.getLogger(__name__)
        while True:
            resp = requests.get(url_)
            logger.debug(resp)
            logger.debug(resp.json())

            if resp.status_code != 429:  # too many requests
                break  # from while
            else:
                sleep(60)
        output = [o for o in resp.json()['outputs'] if o.get('data_hex')][0]
        hash160 = output['data_hex']
        hash160_ = double_ripemd160(hash_)
        logger.debug((hash160, hash160_))

        return hash160 == hash160_, MSG_DATA_RCV.format(output=output)
    except Exception as exc:
        return False, repr(exc)


if __name__ == '__main__':
    URL = "https://api.blockcypher.com/v1/bcy/test/txs/" \
          "c28f113562a0ef3c11ba3f393a5ea98bb91a197e7f00951f3ab8fa4a533f60cc?" \
          "limit=50&includeHex=true"
    HASH = "a8e26fa85a95a531ebd98b4454d17790430cc4a11ce157e2ad051f7c3c128ce8"
    print(check_hash(URL, HASH))
