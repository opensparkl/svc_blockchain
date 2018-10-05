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

Signing script using ed25519 keys.
"""
import binascii
import sys
import json
import ed25519


def sign():
    """
    Sign msg with ed25519 private key.
    """
    if len(sys.argv) != 3:
        result = {'error': 'Expected 2 args: msg and private key'}
    else:
        try:
            msg = sys.argv[1].encode()
            priv_b = binascii.a2b_base64(
                sys.argv[2])
            priv_ = ed25519.SigningKey(
                priv_b)
            signed_ = priv_.sign(
                msg)
            signed = binascii.b2a_base64(
                signed_).decode().rstrip()
            result = {
                'signed': signed}

        except Exception as exc:
            result = {
                'error': str(exc)}

    return result


sys.stdout.write(
    json.dumps(
        sign()))
