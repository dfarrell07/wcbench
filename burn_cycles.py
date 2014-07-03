#!/usr/bin/env python

import threading

def cycle_burner():
    while True:
        blah = 9912313 * 34023840293
        meh = 84908230489 % 323422

threads = []
for i in range(3):
    thread = threading.Thread(target=cycle_burner)
    threads.append(thread)
    print "Starting a thread"
    thread.start()
