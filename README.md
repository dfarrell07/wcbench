## Wrapped CBench (WCBench)

CBench, wrapped in stuff that makes it useful.

### Overview

CBench is a somewhat classic SDN controller benchmark tool. It blasts a controller with OpenFlow packet-in messages and counts the rate of flow mod messages returned. WCBench consumes CBench as a library, then builds a robust test automation, stats collection and stats analysis/graphing system around it.

WCBench currently only supports the OpenDaylight SDN controller, but it would be fairly easy to add support for other controllers. Community contributions are encouraged!

### Usage

#### Usage Overview

The help outputs produced by `./wcbench.sh -h`, `./loop_wcbench.sh -h` and `stats.py -h` are quite useful:

```
Usage ./wcbench.sh [options]

Setup and/or run CBench and/or OpenDaylight.

OPTIONS:
    -h Show this message
    -c Install CBench
    -t <time> Run CBench for given number of minutes
    -r Run CBench against OpenDaylight
    -i Install ODL from last sucessful build
    -p <processors> Pin ODL to given number of processors
    -o Run ODL from last sucessful build
    -k Kill OpenDaylight
    -d Delete local ODL and CBench code
```

```
Usage ./loop_wcbench.sh [options]

Run WCBench against OpenDaylight in a loop.

OPTIONS:
    -h Show this help message
    -l Loop WCBench runs without restarting ODL
    -r Loop WCBench runs, restart ODL between runs
    -t <time> Run WCBench for a given number of minutes
    -p <processors> Pin ODL to given number of processors
```

```
usage: stats.py [-h] [-S]
                [-s {five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} [{five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} ...]]
                [-G]
                [-g {five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} [{five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} ...]]

Compute stats about CBench data

optional arguments:
  -h, --help            show this help message and exit
  -S, --all-stats       compute all stats
  -s {five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} [{five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} ...], --stats {five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} [{five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} ...]
                        compute stats on specified data
  -G, --all-graphs      graph all data
  -g {five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} [{five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} ...], --graphs {five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} [{five_load,ram,steal_time,one_load,iowait,fifteen_load,runtime,flows} ...]
                        graph specified data
```

#### Usage Details: wcbench.sh

Most of the work in WCBench happens in `wcbench.sh`. It's the bit that directly wraps CBench, automates CBench/ODL installation, collects system stats, starts/stops ODL, and runs CBench against ODL.

In more detail, the `wcbench.sh` script supports:

* Trivially cloning, building and installing CBench via the [oflops repo](https://github.com/andi-bigswitch/oflops).
* Changing a set of CBench params (MS_PER_TEST, TEST_PER_SWITCH and CBENCH_WARMUP) to easily set the overall length of a CBench run in minutes. Long CBench runs typically produce results with a lower standard deviation.
* Running CBench against an instance of OpenDaylight. The CBench and ODL processes can be on the same machine or different machines. Change the `CONTROLLER_IP` and `CONTROLLER_PORT` variables in `wcbench.sh` to point CBench at the correct ODL process. To run against a local ODL process that's on the default port, set `CONTROLLER_IP="localhost"` and `CONTROLLER_PORT=6633`. To run CBench against a remote ODL process, set `CONTROLLER_IP` to the IP address of the machine running ODL and `CONTROLLER_PORT` to the port ODL is listening on. Obviously the two machines have to have network connectivity with each other. Additionally, since WCBench connects to the remote machine to pull system stats, the remote machine needs to have sshd running and properly configured. The local machine should have it's `~/.ssh/config` file and public keys setup such that `ssh $SSH_HOSTNAME` works without a password or RSA unknown-key prompt. To do this, setup something like the following in `~/.ssh/config`:

```
Host cbench
    Hostname 209.132.178.170
    User fedora
    IdentityFile /home/daniel/.ssh/id_rsa_nopass
    StrictHostKeyChecking no
```

As you likely know, `ssh-copy-id` can help you setup your system to connect with the remote box via public key crypto. If you don't have keys setup for public key crypto, Google for guides (very out of scope). Finally, note that the `SSH_HOSTNAME` var in `wcbench.sh` must be set to the exact same value given on the `Host` line above.
* Trivially installing/configuring ODL from the last successful build (via an Integration team Jenkins job).
* Pinning the OpenDaylight process to a given number of CPU cores. This is useful for ensuring that ODL is properly pegged, working as hard as it can with given resource limits. It can also expose bad ODL behavior that comes about when the process is pegged.
* Running OpenDaylight and issuing all of the required configuration. Note that the `ODL_STARTUP_DELAY` variable in `wcbench.sh` might need some attention when running on a new system. If ODL takes longer than this value (in seconds) to start, `wcbench.sh` will attempt to issue the required configuration via telnet to the OSGi console before ODL can accept the configuration changes. This will result in fairly obvious error messages dumped to stdout. If you see these, increase the `ODL_STARTUP_DELAY` time. Alternatively, you can manually issue the required configuration after ODL starts by connecting to the OSGi console via telnet and issuing `dropAllPacketsRpc on`. See the `issue_odl_config` function in `wcbench.sh` for more info. Note that there's an open issue to make this config process more robust ([Issue #6](issue_odl_config)). Community contributions solicited!
* Stopping the OpenDaylight process. This is done cleanly via the `run.sh` script, not `kill` or `pkill`.
* Cleaning up everything changed by the `wcbench.sh` script, including deleting ODL and CBench sources and binaries.


#### Usage Details: loop_wcbench.sh

The `loop_wcbench.sh` script is a fairly simple wrapper around `wcbench.sh` ("I hear you like wrappers, so I wrapped your wrapper in a wrapper"). Its reason for existing is to enable long series of repeated WCBench runs. As described in the [WCBench Results](https://github.com/dfarrell07/cbench_regression#wcbench-results) section, these results will be stored in a CSV file and can be analyzed with `stats.py`, as described in the [Usage Details: stats.py](https://github.com/dfarrell07/cbench_regression#usage-details-statspy) section. Doing many WCBench runs allows trends over time to be observed (like decreasing perf or increasing RAM). More results can also yield more representative stats.

In more detail, the `loop_wcbench.sh` script supports:

* Repeatedly running WCBench against ODL without restarting ODL between runs. This test revealed the perf degradation over time described in [bug 1395](https://bugs.opendaylight.org/show_bug.cgi?id=1395).
* Repeatedly running WCBench against ODL, restarting ODL between runs. This acted as a control when finding [bug 1395](https://bugs.opendaylight.org/show_bug.cgi?id=1395), as restarting ODL runs mitigated perf decreases. 
* Pass run length info to WCBench, causing WCBench runs to last for the given number of minutes. Note that longer runs seem to result in lower standard deviation flows/sec results.
* Pin ODL to a given number of processors. This is basically a thin hand-off to `wcbench.sh`. As mentioned above, pinning ODL allows it to be testing while the process is properly pegged.

#### Usage Details: stats.py

TODO

### WCBench Results

TODO
