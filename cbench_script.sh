#!/usr/bin/env sh
# Script for running automated CBench regression tests
# TODO: Support latency and throughput modes
# TODO: Support for running against other controllers

# For remote runs, you must have .ssh/config setup such that `ssh $SSH_HOSTMANE` works w/o pw
# Example host setup in .ssh/config:
# Host cbench
#     Hostname 209.132.178.170
#     User fedora
#     IdentityFile /home/daniel/.ssh/id_rsa_nopass
#     StrictHostKeyChecking no

# Exit codes
EX_USAGE=64
EX_NOT_FOUND=65
EX_OK=0
EX_ERR=1

# Params for CBench test and ODL config
NUM_SWITCHES=16
NUM_MACS=100000
#TESTS_PER_SWITCH=20  # Commented out to speed up testing
TESTS_PER_SWITCH=2
MS_PER_TEST=1000
OSGI_PORT=2400
ODL_STARTUP_DELAY=90
ODL_RUNNING_STATUS=0
ODL_STOPPED_STATUS=255
ODL_BROKEN_STATUS=1
CONTROLLER="OpenDaylight"
CONTROLLER_IP="localhost"
#CONTROLLER_IP="172.18.14.26"
CONTROLLER_PORT=6633
SSH_HOSTNAME="cbenchc"

# Array that stores results in indexes defined by cols array
declare -a results
# The order of these array values determines column order in RESULTS_FILE
cols=(run_num cbench_avg start_time end_time controller_ip human_time
      num_switches num_macs tests_per_switch ms_per_test steal_time
      total_ram used_ram free_ram cpus one_min_load five_min_load
      fifteen_min_load controller)

# TODO doc
# See this for explanation of horrible-looking quoting: http://goo.gl/PMI5ag
declare -A stats_cmds
stats_cmds=([total_ram]='free -m | awk '"'"'/^Mem:/{print $2}'"'"''
            [used_ram]='free -m | awk '"'"'/^Mem:/{print $3}'"'"''
            [free_ram]='free -m | awk '"'"'/^Mem:/{print $4}'"'"''
            [cpus]='nproc'
            [one_min_load]='uptime | awk -F'"'"'[a-z]:'"'"' '"'"'{print $2}'"'"' | awk -F "," '"'"'{print $1}'"'"' | tr -d " "'
            [five_min_load]='uptime | awk -F'"'"'[a-z]:'"'"' '"'"'{print $2}'"'"' | awk -F "," '"'"'{print $2}'"'"' | tr -d " "'
            [fifteen_min_load]='uptime | awk -F'"'"'[a-z]:'"'"' '"'"'{print $2}'"'"' | awk -F "," '"'"'{print $3}'"'"' | tr -d " "'
            [steal_time]='cat /proc/stat | awk '"'"'NR==1 {print $9}'"'"'')

# Paths used in this script
BASE_DIR=$HOME
OF_DIR=$BASE_DIR/openflow
OFLOPS_DIR=$BASE_DIR/oflops
ODL_DIR=$BASE_DIR/opendaylight
ODL_ZIP="distributions-base-0.1.2-SNAPSHOT-osgipackage.zip"
ODL_ZIP_PATH=$BASE_DIR/$ODL_ZIP
PLUGIN_DIR=$ODL_DIR/plugins
RESULTS_FILE=$BASE_DIR/"results.csv"
CBENCH_LOG=$BASE_DIR/"cbench.log"

usage()
{
    # Print usage message
    cat << EOF
Usage $0 [options]

Setup and run CBench and OpenDaylight

OPTIONS:
    -h Show this message
    -r Run CBench against OpenDaylight
    -c Install CBench
    -i Install ODL from last sucessful build
    -o Run ODL from last sucessful build
    -k Kill OpenDaylight
    -d Delete local ODL code
EOF
}

cbench_installed()
{
    # Checks if CBench is installed
    if command -v cbench &>/dev/null; then
        echo "CBench is installed"
        return $EX_OK
    else
        echo "CBench is not installed"
        return $EX_NOT_FOUND
    fi
}

install_cbench()
{
    # Installs CBench, including its dependencies
    # This function is idempotent
    # This has been tested on fresh cloud versions of Fedora 20 and CentOS 6.5
    # Note that I'm not currently building oflops/netfpga-packet-generator-c-library (optional)
    if cbench_installed; then
        return $EX_OK
    fi

    # Install required packages
    echo "Installing CBench dependences"
    sudo yum install -y net-snmp-devel libpcap-devel autoconf make automake libtool libconfig-devel git &> /dev/null

    # Clone repo that contains CBench
    echo "Cloning CBench repo"
    git clone https://github.com/andi-bigswitch/oflops.git $OFLOPS_DIR &> /dev/null

    # CBench requires the OpenFlow source code, clone it
    echo "Cloning openflow source code"
    git clone git://gitosis.stanford.edu/openflow.git $OF_DIR &> /dev/null

    # Build the oflops/configure file
    old_cwd=$PWD
    cd $OFLOPS_DIR
    echo "Building oflops/configure file"
    ./boot.sh &> /dev/null

    # Build oflops
    echo "Building CBench"
    ./configure --with-openflow-src-dir=$OF_DIR &> /dev/null
    make &> /dev/null
    sudo make install &> /dev/null
    cd $old_cwd

    # Validate that the install worked
    if ! cbench_installed; then
        echo "Failed to install CBench" >&2
        exit $EX_ERR
    else
        echo "Successfully installed CBench"
        return $EX_OK
    fi
}

next_run_num()
{
    # Get the number of the next run
    # Assumes that the file hasn't had rows removed by a human
    # Check if there's actually a results file
    if [ ! -s $RESULTS_FILE ]; then
        echo 0
        return
    fi

    # There should be one header row, then rows starting with 0, counting up
    num_lines=`wc -l $RESULTS_FILE | awk '{print $1}'`
    echo $(expr $num_lines - 1)
}

name_to_index()
{
    # Convert results column name to column index
    name=$1
    for (( i = 0; i < ${#cols[@]}; i++ )); do
        if [ "${cols[$i]}" = $name ]; then
            echo $i
            return
        fi
    done
}

get_local_system_stats()
{
    # Collect stats about local system
    #results[$(name_to_index "total_ram")]=$( ${stats_cmds[total_ram]} )
    #results[$(name_to_index "used_ram")]=$(${stats_cmds[used_ram]})
    #results[$(name_to_index "free_ram")]=$(${stats_cmds[free_ram]})
    results[$(name_to_index "cpus")]=$( ${stats_cmds[cpus]} )
    #results[$(name_to_index "one_min_load")]=$(${stats_cmds[one_min_load]})
    #results[$(name_to_index "five_min_load")]=$(${stats_cmds[five_min_load]})
    #results[$(name_to_index "fifteen_min_load")]=$(${stats_cmds[fifteen_min_load]})
    #results[$(name_to_index "steal_time")]=$(${stats_cmds[steal_time]})
}

get_remote_system_stats()
{
    # Collect stats about remote system
    results[$(name_to_index "total_ram")]=$(ssh $SSH_HOSTNAME "${stats_cmds[total_ram]}")
    results[$(name_to_index "used_ram")]=$(ssh $SSH_HOSTNAME "${stats_cmds[used_ram]}")
    results[$(name_to_index "free_ram")]=$(ssh $SSH_HOSTNAME "${stats_cmds[free_ram]}")
    results[$(name_to_index "cpus")]=$(ssh $SSH_HOSTNAME "${stats_cmds[cpus]}")
    results[$(name_to_index "one_min_load")]=$(ssh $SSH_HOSTNAME "${stats_cmds[one_min_load]}")
    results[$(name_to_index "five_min_load")]=$(ssh $SSH_HOSTNAME "${stats_cmds[five_min_load]}")
    results[$(name_to_index "fifteen_min_load")]=$(ssh $SSH_HOSTNAME "${stats_cmds[fifteen_min_load]}")
    results[$(name_to_index "steal_time")]=$(ssh $SSH_HOSTNAME "${stats_cmds[steal_time]}")
}

collect_results()
{
    # Collect results of CBench run
    # Store stats that have nothing to do with the system that's running ODL
    results[$(name_to_index "cbench_avg")]=$1
    results[$(name_to_index "start_time")]=$2
    results[$(name_to_index "end_time")]=$3
    results[$(name_to_index "run_num")]=$(next_run_num)
    results[$(name_to_index "human_time")]=`date`
    results[$(name_to_index "controller_ip")]=$CONTROLLER_IP
    results[$(name_to_index "num_switches")]=$NUM_SWITCHES
    results[$(name_to_index "num_macs")]=$NUM_MACS
    results[$(name_to_index "tests_per_switch")]=$TESTS_PER_SWITCH
    results[$(name_to_index "ms_per_test")]=$MS_PER_TEST
    results[$(name_to_index "controller")]=$CONTROLLER

    # Store local or remote stats
    if [ $CONTROLLER_IP = "localhost" ]; then
        get_local_system_stats
    else
        get_remote_system_stats
    fi
}

write_csv_row()
{
    # Accepts an array and writes it in CSV format to the results file
    declare -a array_to_write=("${!1}")
    i=0
    while [ $i -lt $(expr ${#array_to_write[@]} - 1) ]; do
        # Only use echo with comma and no newline for all but last col
        echo -n "${array_to_write[$i]}," >> $RESULTS_FILE
        let i+=1
    done
    # Finish CSV row with no comma and a newline
    echo "${array_to_write[$i]}" >> $RESULTS_FILE
}

run_cbench()
{
    # Runs the CBench test against the controller
    echo "Running CBench..."
    start_time=`date +%s`
    cbench_output=`cbench -c $CONTROLLER_IP -p $CONTROLLER_PORT -m $MS_PER_TEST -l $TESTS_PER_SWITCH -s $NUM_SWITCHES -M $NUM_MACS 2>&1`
    end_time=`date +%s`

    # Parse out average responses/sec, log/handle very rare unexplained errors
    # This logic can be removed if/when the root cause of this error is discovered and fixed
    cbench_avg=`echo "$cbench_output" | grep RESULT | awk '{print $8}' | awk -F'/' '{print $3}'`
    if [ -z "$cbench_avg" ]; then
        echo "WARNING: Rare error occurred: failed to parse avg. See $CBENCH_LOG." >&2
        echo "Run $(next_run_num) failed to record a CBench average. CBench details:" >> $CBENCH_LOG
        echo "$cbench_output" >> $CBENCH_LOG
    else
        echo "Average responses/second: $cbench_avg"
    fi

    # Write header if this is a fresh results file
    if [ ! -s $RESULTS_FILE ]; then
        echo "$RESULTS_FILE not found or empty, building fresh one" >&2
        write_csv_row cols[@]
    fi
    collect_results $cbench_avg $start_time $end_time
    write_csv_row results[@]

    # TODO: Integrate with Jenkins Plot Plugin
}

install_opendaylight()
{
    # Installs latest build of the OpenDaylight controller
    # Remove old controller code
    if [ -d $ODL_DIR ]
    then
        echo "Removing $ODL_DIR"
        rm -rf $ODL_DIR
    fi
    if [ -f $ODL_ZIP_PATH ]
    then
        echo "Removing $ODL_ZIP_PATH"
        rm -f $ODL_ZIP_PATH
    fi

    # Install required packages
    sudo yum install -y java-1.7.0-openjdk unzip wget &> /dev/null

    # Grab last successful build
    echo "Downloading last successful ODL build"
    wget -P $BASE_DIR "https://jenkins.opendaylight.org/integration/job/integration-master-project-centralized-integration/lastSuccessfulBuild/artifact/distributions/base/target/$ODL_ZIP" &> /dev/null
    echo "Unzipping last successful ODL build"
    unzip -d $BASE_DIR $ODL_ZIP_PATH &> /dev/null

    # Make some plugin changes that are apparently required for CBench
    echo "Downloading openflowplugin"
    wget -P $PLUGIN_DIR 'https://jenkins.opendaylight.org/openflowplugin/job/openflowplugin-merge/lastSuccessfulBuild/org.opendaylight.openflowplugin$drop-test/artifact/org.opendaylight.openflowplugin/drop-test/0.0.3-SNAPSHOT/drop-test-0.0.3-SNAPSHOT.jar' &> /dev/null
    echo "Removing simpleforwarding plugin"
    rm $PLUGIN_DIR/org.opendaylight.controller.samples.simpleforwarding-0.4.2-SNAPSHOT.jar
    echo "Removing arphandler plugin"
    rm $PLUGIN_DIR/org.opendaylight.controller.arphandler-0.5.2-SNAPSHOT.jar

    # TODO: Change controller log level to ERROR. Confirm this is necessary.
}

odl_installed()
{
    # Checks if OpenDaylight is installed
    if [ ! -d $ODL_DIR ]; then
        return $EX_NOT_FOUND
    fi
}

odl_status()
{
    # Checks if OpenDaylight is running
    # TOOD: Collapse back into odl_started
    # Assumes you've checked that ODL is installed
    old_cwd=$PWD
    cd $ODL_DIR
    ./run.sh -status &> /dev/null
    odl_status=$?
    cd $old_cwd
    echo $odl_status
}

odl_started()
{
    # Checks if OpenDaylight is running
    # Assumes you've checked that ODL is installed
    old_cwd=$PWD
    cd $ODL_DIR
    if [ $(odl_status) = 0 ]; then
        return $EX_OK
    else
        return $EX_NOT_FOUND
    fi
    cd $old_cwd
}

start_opendaylight()
{
    # Starts the OpenDaylight controller
    old_cwd=$PWD
    cd $ODL_DIR
    if odl_started; then
        echo "OpenDaylight is already running"
        return $EX_OK
    else
        echo "Starting OpenDaylight"
        ./run.sh -start $OSGI_PORT -of13 -Xms1g -Xmx4g &> /dev/null
    fi
    cd $old_cwd
    # TODO: Smarter block until ODL is actually up
    echo "Giving ODL $ODL_STARTUP_DELAY seconds to get up and running"
    while [ $ODL_STARTUP_DELAY -gt 0 ]; do
        sleep 10
        let ODL_STARTUP_DELAY=ODL_STARTUP_DELAY-10
        echo "$ODL_STARTUP_DELAY seconds remaining"
    done
    issue_odl_config
}

issue_odl_config()
{
    # Give dropAllPackets command via telnet to OSGi
    # This is a bit of a hack, but it's the only method I know of
    # See: https://ask.opendaylight.org/question/146/issue-non-interactive-gogo-shell-command/
    # TODO: There seems to be a timing-related bug here. More delay? Smarter check?
    if ! command -v telnet &>/dev/null; then
        sudo yum install -y telnet
    fi
    echo "Issuing \`dropAllPacketsRpc on\` command via telnet to localhost:$OSGI_PORT"
    # NB: Not using sleeps results in silent failures (cmd has no effect)
    (sleep 3; echo dropAllPacketsRpc on; sleep 3) | telnet localhost $OSGI_PORT
}

stop_opendaylight()
{
    # Stops OpenDaylight using run.sh
    old_cwd=$PWD
    cd $ODL_DIR
    if odl_started; then
        echo "Stopping OpenDaylight"
        ./run.sh -stop &> /dev/null
    else
        echo "OpenDaylight isn't running"
    fi
    cd $old_cwd
}

cleanup()
{
    # Removes ODL zipped/unzipped, openflow code, CBench code
    # TODO: Remove CBench binary
    # TODO: Break out into uninstall_odl, uninstall_cbench
    if [ -d $ODL_DIR ]; then
        echo "Removing $ODL_DIR"
        rm -rf $ODL_DIR
    fi
    if [ -f $ODL_ZIP_PATH ]; then
        echo "Removing $ODL_ZIP_PATH"
        rm -rf $ODL_ZIP_PATH
    fi
    if [ -d $OF_DIR ]; then
        echo "Removing $OF_DIR"
        rm -rf $OF_DIR
    fi
    if [ -d $OFLOPS_DIR ]; then
        echo "Removing $OFLOPS_DIR"
        rm -rf $OFLOPS_DIR
    fi
}

# If executed with no options
if [ $# -eq 0 ]; then
    echo "No options given. Installing ODL+CBench and running test."
    install_cbench
    install_opendaylight
    start_opendaylight
    run_cbench
    stop_opendaylight
    cleanup
    exit $EX_OK
fi


while getopts ":hrciokd" opt; do
    case "$opt" in
        h)
            # Help message
            usage
            exit $EX_OK
            ;;
        r)
            # Run CBench against OpenDaylight
            if [ $CONTROLLER_IP = "localhost" ]; then
                if ! odl_installed; then
                    echo "OpenDaylight isn't installed, can't run test"
                    exit $EX_ERR
                fi
                if ! odl_started; then
                    echo "OpenDaylight isn't started, can't run test"
                    exit $EX_ERR
                fi
                echo "Running CBench against ODL on localhost"
            else
                echo "Running CBench against ODL on $CONTROLLER_IP"
            fi
            run_cbench
            ;;
        c)
            # Install CBench
            install_cbench
            ;;
        i)
            # Install OpenDaylight from last successful build
            install_opendaylight
            ;;
        o)
            # Run OpenDaylight from last successful build
            if ! odl_installed; then
                echo "OpenDaylight isn't installed, can't start it"
                exit $EX_ERR
            fi
            start_opendaylight
            ;;
        k)
            # Kill OpenDaylight
            if ! odl_installed; then
                echo "OpenDaylight isn't installed, can't stop it"
                exit $EX_ERR
            fi
            if ! odl_started; then
                echo "OpenDaylight isn't started, can't stop it"
                exit $EX_ERR
            fi
            stop_opendaylight
            ;;
        d)
            # Delete local ODL code (zipped/unzipped), OFLOPS code, OF code
            cleanup
            ;;
        *)
            usage
            exit $EX_USAGE
    esac
done
