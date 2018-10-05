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

Verify message signature script using ed25519 keys.
"""
import binascii
import sys
import json
import ed25519


def verify():
    """
    Verify ed25519 message signature.
    """
    if len(sys.argv) != 4:
        result = {
            'error':
                'Expected 3 args: msg, signed, and public key'}
    else:
        try:
            msg = sys.argv[1].encode()
            signed_b = binascii.a2b_base64(
                sys.argv[2])
            pub_b = binascii.a2b_base64(
                sys.argv[3])
            pub_ = ed25519.VerifyingKey(
                pub_b)

            verify_ = True
            try:
                pub_.verify(
                    signed_b, msg)
            except ed25519.BadSignatureError:
                verify_ = False

            result = {
                'verify': verify_}

        except Exception as exc:
            result = {
                'error': str(exc)}

    return result


sys.stdout.write(
    json.dumps(
        verify()))
