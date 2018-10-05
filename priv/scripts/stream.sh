#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# @copyright 2018 SPARKL Limited. All Rights Reserved.
# @author <ahfarrell@sparkl.com> Andrew Farrell
#
# Simple script for grabbing stream output
#
if [ -z "$1" ]; then
    BLOCKCHAINPRIV=~/sse_core/apps/svc_blockchain/priv
else
    BLOCKCHAINPRIV=$1
fi
echo Blockchain path: ${BLOCKCHAINPRIV}
cd ${BLOCKCHAINPRIV}
sparkl connect http://localhost:8001
sparkl login admin@localhost postoffice
STREAMOUT_FILE=/tmp/streamout.log sparkl service --path scripts Scratch/Primes/Blockchain/Streaming stream
