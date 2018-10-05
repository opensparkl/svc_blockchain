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
Abstract event record store
"""
from ..abstract_store import Store


class EventStore(Store):
    """
    Abstract class for event record stores.
    """
    def get_events(self, owner, txn):
        """
        Gets events corresponding to a particular owner and transaction.
        """
        raise NotImplementedError("Not implemented")

    def events_count(self):
        """
        Gets a full event count. Used for test purposes only.
        """
        raise NotImplementedError("Not implemented")

    def pop_events(self, txn, events):
        """
        Reduces the number of events outstanding for a particular transaction.
        """
        raise NotImplementedError("Not implemented")

    def is_event_txn(self, owner, txn):
        """
        Determines whether the given transaction has corresponding events.
        The result should be True, else we have missing events.
        """
        raise NotImplementedError("Not implemented")

    def events_left(self):
        """
        Determines the number of transactions with events yet to be verified.
        """
        raise NotImplementedError("Not implemented")

    def prime_ev_col(self):
        """
        Primes the number of event counts for each transaction of interest.
        """
        raise NotImplementedError("Not implemented")

    def drop_ev_col(self):
        """
        Drops the temporary collection used to store events.
        """
        raise NotImplementedError("Not implemented")
