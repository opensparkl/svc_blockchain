"""
Copyright (c) 2018 SPARKL Limited. All Rights Reserved.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
Author <ahfarrell@sparkl.com> Andrew Farrell.

Maintains block counts for different kinds of block.
"""


class CheckerCounts():
    """
    Counts class.
    """
    def __init__(self):
        self.checked = 0
        self.bubbled = 0
        self.skipped = 0
        self.refd = 0
        self.result = False

    def __str__(self):
        return "{result}:{checked}:{bubbled}:{skipped}:{refd}".format(
            result=str(self.result).lower(),
            checked=str(self.checked),
            bubbled=str(self.bubbled),
            skipped=str(self.skipped),
            refd=str(self.refd))

    def get_result(self):
        """
        Returns checking result
        :return: result
        """
        return self.result

    def get_skipped(self):
        """
        Return number of skipped blocks
        :return: skipped
        """
        return self.skipped

    def get_checked(self):
        """
        Return number of checked blocks
        :return: checked
        """
        return self.checked

    def get_bubbled(self):
        """
        Return number of bubbled blocks
        :return: bubbled
        """
        return self.bubbled

    def get_refd(self):
        """
        Return number of externally referenced blocks
        :return: refd
        """
        return self.refd

    def incr_skipped(self):
        """
        Increments skipped count.
        """
        self.skipped += 1

    def incr_checked(self):
        """
        Increments checked count.
        """
        self.checked += 1

    def incr_bubbled(self):
        """
        Increments bubbled count.
        """
        self.bubbled += 1

    def incr_refd(self):
        """
        Increments externally referenced block count.
        """
        self.refd += 1
