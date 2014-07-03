#!/usr/bin/env python

import threading

def cycle_burner():
    while True:
        meh = 84908230489 % 323422

for i in range(3):
    thread = threading.Thread(target=cycle_burner)
    print "Starting a thread"
    thread.start()
