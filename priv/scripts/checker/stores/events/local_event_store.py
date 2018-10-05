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
Local event record store.
"""
import os
import json
import checker as ch
from .abstract_event_store import EventStore


class LocalEventStore(EventStore):
    """
    Local event record store.
    """
    def __init__(self, args):
        super(LocalEventStore, self).__init__(__name__, args)
        self.uri = os.path.join(args.ev_uri, args.ev_col)
        self.event_counts = {}
        self.prime_ev_col()

        self.logger.debug("Store uri: %s", self.uri)

    def get_events(self, owner, txn):
        """
        Gets events corresponding to a particular owner and transaction.
        """
        with open(os.path.join(self.uri, owner, txn), "r") as events:
            eventlist = []
            for event_ in events.readlines():
                event = json.loads(event_.strip())
                eventlist.append(event)

            self.logger.debug("Events: %s", str(eventlist))
            return eventlist

    def events_count(self):
        """
        Gets a full event count. Used for test purposes only.
        """
        count = 0
        for events_path in [os.path.join(evpath, evfile) for
                            evpath in [os.path.join(self.uri, owner) for
                                       owner in os.listdir(self.uri)] for
                            evfile in os.listdir(evpath)]:
            count += sum(1 for _line in open(
                os.path.join(self.uri, events_path)))
        return count

    def pop_events(self, txn, events):
        """
        Reduces the number of events outstanding for a particular transaction.
        """
        ev_cnt = self.event_counts[txn] - len(events)
        if ev_cnt < 1:
            self.event_counts.pop(txn)
        else:
            self.event_counts[txn] = ev_cnt

        self.logger.debug("Event Count: %d", ev_cnt)
        return ev_cnt

    def is_event_txn(self, owner, txn):
        """
        Determines whether the given transaction has corresponding events.
        The result should be True, else we have missing events.
        """
        is_txn = os.path.exists(
            os.path.join(
                self.uri, owner, txn))
        self.logger.debug("Is event txn: %s", str(is_txn))

        return is_txn

    def events_left(self):
        """
        Determines the number of transactions with events yet to be verified.
        """
        ev_left = self.event_counts.keys()
        self.logger.info("Event Counts: %s", str(self.event_counts))
        return ev_left

    def prime_ev_col(self):
        """
        Primes the number of event counts for each transaction of interest.
        """
        owners = [(os.path.join(self.uri, owner), owner)
                  for owner in os.listdir(self.uri)]

        ev_txns_ = [(os.path.join(ownerpath, ev_file), owner, ev_file) for
                    (ownerpath, owner) in owners for
                    ev_file in os.listdir(ownerpath) if
                    not self.args.owner or self.args.owner == owner]

        ev_txns = [(ev_path, _owner, ev_txn) for
                   (ev_path, _owner, ev_txn) in ev_txns_ if
                   not self.args.node or
                   json.loads(
                       open(ev_path).readline())[ch.BLOCKWRITER] ==
                   self.args.node]
        self.logger.debug(ev_txns)

        for (ev_path, _owner, ev_txn) in ev_txns:
            ev_count = sum(1 for _line in open(ev_path, "r"))
            if ev_count > 0:
                self.event_counts[ev_txn] = ev_count
        self.logger.info("Event Counts: %s", str(self.event_counts))

    def drop_ev_col(self):
        """
        Drops the temporary collection used to store events.
        """
        pass
