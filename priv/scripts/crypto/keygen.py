"""
@copyright (c) 2018 SPARKL Limited. All Rights Reserved.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
@author <ahfarrell@sparkl.com> Andrew Farrell.

Key gen script for ed25519 keys
"""
import binascii
import os
import sys
import json
import ed25519


def keygen():
    """
    Generate ed25519 public, private key pair.
    """
    try:
        priv_, pub_ = ed25519.create_keypair(
            entropy=os.urandom)

        priv_h = binascii.b2a_base64(
            priv_.to_bytes()).decode().rstrip()

        pub_h = binascii.b2a_base64(
            pub_.to_bytes()).decode().rstrip()

        result = {'publickey': pub_h,
                  'privatekey': priv_h}

    except Exception as exc:
        result = {
            'error': str(exc)}

    return result


sys.stdout.write(
    json.dumps(
        keygen()))
