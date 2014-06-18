#!/usr/bin/env sh
# Script for running automated CBench regression tests
# TODO: Support latency and throughput modes
# TODO: Support for running against other controllers

# Exit codes
EX_USAGE=64
EX_NOT_FOUND=65
EX_OK=0
EX_ERR=1

# Params for CBench test and ODL config
NUM_SWITCHES=16
NUM_MACS=100000
#TESTS_PER_SWITCH=20
TESTS_PER_SWITCH=2
MS_PER_TEST=1000
OSGI_PORT=2400
ODL_STARTUP_DELAY=90
HEADER="run_num,flows_per_second,start_time,end_time,controller_ip"
# TODO: Remove verbose concept
VERBOSE=true
VERBOSE_HEADER="$HEADER,human_time,num_switches,num_macs,tests_per_switch,ms_per_test,steal_time,total_RAM,used_RAM,free_RAM,CPUs,1_min_load,5_min_load,15_min_load,odl_status,controller"
ODL_RUNNING_STATUS=0
ODL_STOPPED_STATUS=255
ODL_BROKEN_STATUS=1
CONTROLLER="OpenDaylight"

# Associative array that will store CBench result key:value pairs
declare -A results

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
CONTROLLER_IP="localhost"
#CONTROLLER_IP="172.18.14.26"

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

get_next_run_num()
{
    # Get the number of the next run, validate results file format
    # Build results file with column headers if it doesn't exist or it's empty
    # TODO: Break out header-related functionally
    if [ ! -s $RESULTS_FILE ]; then
        echo "$RESULTS_FILE not found or empty, building fresh one" >&2
        if [ $VERBOSE = true -a $CONTROLLER_IP = "localhost" ]; then
            echo $VERBOSE_HEADER > $RESULTS_FILE
        else
            echo $HEADER > $RESULTS_FILE
        fi
        echo 0
        return
    fi

    # Handle special case of header-only results file
    num_lines=`wc -l $RESULTS_FILE | awk '{print $1}'`
    if [ $num_lines -eq 1 ]; then
        echo 0
        return
    fi

    # Get the last run number, add one for next run number
    next_run_num=$(expr $(cat $RESULTS_FILE | cut -d, -f1 | tail -n 1) + 1)
    echo $next_run_num
}

get_local_system_stats()
{
    # Collect stats that provide system and CBench run details
    results[human_time]=`date`
    results[total_ram]=$(free -m | awk '/^Mem:/{print $2}')
    results[used_ram]=$(free -m | awk '/^Mem:/{print $3}')
    results[free_ram]=$(free -m | awk '/^Mem:/{print $4}')
    results[cpus]=`nproc`
    results[one_min_load]=`uptime | awk -F'[a-z]:' '{print $2}' | awk -F "," '{print $1}' | tr -d " "`
    results[five_min_load]=`uptime | awk -F'[a-z]:' '{print $2}' | awk -F "," '{print $2}' | tr -d " "`
    results[fifteen_min_load]=`uptime | awk -F'[a-z]:' '{print $2}' | awk -F "," '{print $3}' | tr -d " "`
    results[steal_time]=`cat /proc/stat | awk 'NR==1 {print $9}'`
    odl_status
    results[odl_status]=$?
}

get_remote_system_stats()
{
    # TODO: Build 
    echo "WARNING: Not implemented"
}

collect_results()
{
    # Collect results of CBench run and write them to a file
    # Store stats that are not dependent on local vs remote execution
    results[cbench_avg]=$1
    results[start_time]=$2
    results[end_time]=$3
    results[run_num]=$(get_next_run_num)
    results[controller_ip]=$CONTROLLER_IP
    results[num_switches]=$NUM_SWITCHES
    results[num_macs]=$NUM_MACS
    results[tests_per_switch]=$TESTS_PER_SWITCH
    results[ms_per_test]=$MS_PER_TEST
    results[controller]=$CONTROLLER

    # Store local or remote stats
    if [ $CONTROLLER_IP = "localhost" ]; then
        get_local_system_stats
    else
        get_remote_system_stats
    fi
}

write_results()
{
    # Write collected results to the results file
    # Bash associative arrays are unordered
    # We need to guarantee CSV file order, so we can't loop to print :(
    echo -n "${results[run_num]}," >> $RESULTS_FILE
    echo -n "${results[cbench_avg]}," >> $RESULTS_FILE
    echo -n "${results[start_time]}," >> $RESULTS_FILE
    echo -n "${results[end_time]}," >> $RESULTS_FILE
    echo -n "${results[controller_ip]}," >> $RESULTS_FILE
    echo -n "${results[human_time]}," >> $RESULTS_FILE
    echo -n "${results[num_switches]}," >> $RESULTS_FILE
    echo -n "${results[num_macs]}," >> $RESULTS_FILE
    echo -n "${results[tests_per_switch]}," >> $RESULTS_FILE
    echo -n "${results[ms_per_test]}," >> $RESULTS_FILE
    echo -n "${results[steal_time]}," >> $RESULTS_FILE
    echo -n "${results[total_ram]}," >> $RESULTS_FILE
    echo -n "${results[used_ram]}," >> $RESULTS_FILE
    echo -n "${results[free_ram]}," >> $RESULTS_FILE
    echo -n "${results[cpus]}," >> $RESULTS_FILE
    echo -n "${results[one_min_load]}," >> $RESULTS_FILE
    echo -n "${results[five_min_load]}," >> $RESULTS_FILE
    echo -n "${results[fifteen_min_load]}," >> $RESULTS_FILE
    echo -n "${results[odl_status]}," >> $RESULTS_FILE
    echo "${results[controller]}" >> $RESULTS_FILE
}

run_cbench()
{
    # Runs the CBench test against the controller
    echo "Running CBench..."
    start_time=`date +%s`
    cbench_output=`cbench -c $CONTROLLER_IP -p 6633 -m $MS_PER_TEST -l $TESTS_PER_SWITCH -s $NUM_SWITCHES -M $NUM_MACS 2>&1`
    end_time=`date +%s`

    # Parse out average responses/sec, log/handle very rare unexplained errors
    # This logic can be removed if/when the root cause of this error is discovered and fixed
    cbench_avg=`echo "$cbench_output" | grep RESULT | awk '{print $8}' | awk -F'/' '{print $3}'`
    if [ $cbench_avg = "" ]; then
        echo "WARNING: Rare error occurred: failed to parse avg. See $CBENCH_LOG." >&2
        echo "Run TODO_run_num failed to record a CBench average. CBench details:" >> $CBENCH_LOG
        echo "$cbench_output" >> $CBENCH_LOG
    else
        echo "Average responses/second: $cbench_avg"
    fi

    collect_results $cbench_avg $start_time $end_time
    write_results

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
    # Assumes you've checked that ODL is installed
    old_cwd=$PWD
    cd $ODL_DIR
    ./run.sh -status &> /dev/null
    odl_status=$?
    cd $old_cwd
    # TODO: Convert to use echo, not return
    return $odl_status
}

odl_started()
{
    # Checks if OpenDaylight is running
    # Assumes you've checked that ODL is installed
    old_cwd=$PWD
    cd $ODL_DIR
    if odl_status; then
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
