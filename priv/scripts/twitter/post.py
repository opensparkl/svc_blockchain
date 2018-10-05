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

Push status update message to Twitter.
E.g., used by merkle tree blockchain logic to push latest hashes to Twitter.
"""
import os
import sys
import logging
from twython import Twython

LOGGER = logging.getLogger(__name__)

SPARKL_TWURL = "https://twitter.com/HashesSparkl/status/{id_str}"


logging.basicConfig(
    filename="/tmp/twitter.log",
    filemode='w',
    format='%(asctime)s,%(msecs)d %(name)s %(levelname)s' +
    '%(message)s line:%(lineno)d',
    datefmt='%H:%M:%S',
    level=logging.DEBUG)


def onopen(service):
    """
    On service open.
    """
    app_key = os.environ.get('TWITTER_APPKEY')
    app_secret = os.environ.get('TWITTER_APPSECRET')
    oauth_key = os.environ.get('TWITTER_OAUTHKEY')
    oauth_secret = os.environ.get('TWITTER_OAUTHSECRET')

    print(app_key, app_secret, oauth_key, oauth_secret)

    twitter_ = Twython(
        app_key, app_secret, oauth_key, oauth_secret)

    service.impl = {
        "Mix/Impl/PostStatus": lambda r, c: post_status(r, c, twitter_)}


def post_status(request, callback, twitter):
    """
    Push status message to Twitter
    """
    status = request["data"]["status"]
    LOGGER.debug(status)
    try:
        response = twitter.update_status(status=status)
        twurl = SPARKL_TWURL.format(id_str=response.get('id_str'))
        LOGGER.debug(twurl)

        callback({
            "reply": "Ok",
            "data": {
                "url": twurl}})
    except Exception as exc:
        callback({
            "reply": "Error",
            "data": {
                "reason": repr(exc)}})


if __name__ == '__main__':
    APP_KEY = os.environ.get('TWITTER_APPKEY')
    APP_SECRET = os.environ.get('TWITTER_APPSECRET')
    OAUTH_KEY = os.environ.get('TWITTER_OAUTHKEY')
    OAUTH_SECRET = os.environ.get('TWITTER_OAUTHSECRET')

    print(APP_KEY, APP_SECRET, OAUTH_KEY, OAUTH_SECRET)

    TWITTER = Twython(APP_KEY, APP_SECRET, OAUTH_KEY, OAUTH_SECRET)
    RESP = TWITTER.update_status(status=sys.argv[1])
    print(SPARKL_TWURL.format(id_str=RESP.get('id_str')))
