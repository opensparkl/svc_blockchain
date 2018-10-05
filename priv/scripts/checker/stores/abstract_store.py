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
Abstract store
"""
import logging


class Store():
    """
    Abstract class for chain block stores.
    """
    def __init__(self, name, args):
        self.logger = logging.getLogger(name)
        self.args = args

    def get_logger(self):
        """
        Get store logger
        :return: logger
        """
        return self.logger

    def get_args(self):
        """
        Get args supplied to store
        :return: args
        """
        return self.args
