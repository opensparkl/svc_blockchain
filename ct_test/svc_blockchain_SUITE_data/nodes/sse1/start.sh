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
# Copyright (c) 2018 SPARKL Limited. All Rights Reserved.
# Author <jacoby@sparkl.com> Jacoby Thwaites.
#
# Usage:
#   ./start.sh [console]
#
ROOT=`git rev-parse --show-toplevel`/../..
echo $ROOT
export ERL_LIBS=$ROOT/apps:$ROOT/opts:$ROOT/deps

if [ "$1" = "console" ]; then
  DETACHED=""
else
  DETACHED="-detached"
  rm -rf mnesia
fi
erl $DETACHED -args_file vm.args -config sys.config

