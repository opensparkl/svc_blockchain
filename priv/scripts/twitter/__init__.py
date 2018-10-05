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

Twitter merkle tree base functions.
"""
import requests


def check_hash(url, hash_):
    """
    Checks that the given double 256-hash exists at
    twitter url.
    """
    try:
        resp = requests.get(url)
        content = resp.text
        present = hash_ in content
        return present, ""
    except Exception:
        return None


if __name__ == '__main__':
    URL = "https://twitter.com/HashesSparkl/status/1008182155057360898"
    HASH = "a8e26fa85a95a531ebd98b4454d17790430cc4a11ce157e2ad051f7c3c128ce8"
    print(check_hash(URL, HASH))
