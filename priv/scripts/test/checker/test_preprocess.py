"""
Copyright (c) 2018 SPARKL Limited. All Rights Reserved.sss
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
Author: <ahfarrell@sparkl.com> Andrew Farrell

Tests for validating appropriate event/block pre-processing
"""

import logging
from json import loads
from checker import preprocess


LOGGER = logging.getLogger(__name__)

PREPROCESSED = '[["class","blockchain"],["data",[]],' \
               '["eventhash","9ffb87bb6b3d134df1bc1080a' \
               '1fd274418e2d4340cde72e5b90fed2defbe06b0"],' \
               '["extra","added for the test   !"],' \
               '["id","N-4VK-WT6-66W4"],["idx",7038],' \
               '["meta",[[["name","YES"],["type","undefined"]]]],' \
               '["name","Yes"],["owner","admin@localhost"],' \
               '["path",' \
               '"admin@localhost/Scratch/Primes/Mix/CheckPrime/Yes"],' \
               '["ref","N-4VK-WT6-4LTX"],["subject","J-4VK-WT6-276"],' \
               '["tag","data_event"],' \
               '["timestamp",1525776274432],["txn","E-4VK-WT6-4LWL"],' \
               '["writer","ct_svc_blockchain@127.0.0.1"]]'


def test_preprocess():
    """
    Simple test covering all aspects of the pre-processing
    functionality for getting events/blocks
    into a canonical form for hashing.
    """
    event = '{"class":"blockchain","data":{},' \
            '"eventhash":"9ffb87bb6b3d134df1bc1080a' \
            '1fd274418e2d4340cde72e5b90fed2defbe06b0",' \
            '"id":"N-4VK-WT6-66W4","idx":7038,' \
            '"meta":[{"name":"YES","type":"undefined"}],"name":"Yes",' \
            '"owner":"admin@localhost",' \
            '"path":' \
            '"admin@localhost/Scratch/Primes/Mix/CheckPrime/Yes",' \
            '"ref":"N-4VK-WT6-4LTX","subject":"J-4VK-WT6-276",' \
            '"tag":"data_event",' \
            '"timestamp":1525776274432,"txn":"E-4VK-WT6-4LWL",' \
            '"writer":"ct_svc_blockchain@127.0.0.1",' \
            '"extra": "added for the test   !"}'
    preprocessed = preprocess(
        loads(event))

    LOGGER.debug(preprocessed)
    assert preprocessed == PREPROCESSED
