#!/usr/bin/env sh
# Script for running automated CBench regression tests

# Exit codes
EX_USAGE=64
EX_NOT_FOUND=65
EX_OK=0
EX_ERR=1

# Params for CBench test and ODL config
NUM_SWITCHES=16
NUM_MACS=100000
TESTS_PER_SWITCH=20
MS_PER_TEST=1000
OSGI_PORT=2400
ODL_STARTUP_DELAY=90
COL_ZERO_NAME="run_num"
COL_ONE_NAME="flows_per_second"


# Paths used in this script
BASE_DIR=$HOME
OF_DIR=$BASE_DIR/openflow
OFLOPS_DIR=$BASE_DIR/oflops
ODL_DIR=$BASE_DIR/opendaylight
ODL_ZIP="distributions-base-0.1.2-SNAPSHOT-osgipackage.zip"
ODL_ZIP_PATH=$BASE_DIR/$ODL_ZIP
PLUGIN_DIR=$ODL_DIR/plugins
RESULTS_FILE=$BASE_DIR/"results.csv"

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
    sudo yum install -y net-snmp-devel libpcap-devel autoconf make automake libtool libconfig-devel git

    # Clone repo that contains CBench
    git clone https://github.com/andi-bigswitch/oflops.git $OFLOPS_DIR

    # CBench requires the OpenFlow source code, clone it
    git clone git://gitosis.stanford.edu/openflow.git $OF_DIR

    # Build the oflops/configure file
    old_cwd=$PWD
    cd $OFLOPS_DIR
    ./boot.sh

    # Build oflops
    ./configure --with-openflow-src-dir=$OF_DIR
    make
    sudo make install
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
    if [ ! -s $RESULTS_FILE ]; then
        echo "$RESULTS_FILE not found or empty, building fresh one" >&2
        echo "$COL_ZERO_NAME,$COL_ONE_NAME" > $RESULTS_FILE
        return 0
    fi

    # Validate result file header format
    cat $RESULTS_FILE | head -n 1 | grep "^$COL_ZERO_NAME,$COL_ONE_NAME$" &> /dev/null
    if [ ! $? -eq 0 ]; then
        echo "Invalid header in $RESULTS_FILE, bailing" >&2
        exit $EX_ERR
    fi

    # Handle special case of header-only results file
    num_lines=`wc -l $RESULTS_FILE | awk '{print $1}'`
    if [ $num_lines -eq 1 ]; then
        return 0
    fi

    # Get the last run number, add one for next run number
    next_run_num=$(expr $(cat $RESULTS_FILE | cut -d, -f1 | tail -n 1) + 1)
    return $next_run_num
}

run_cbench()
{
    # Runs the CBench test against the controller
    # Ignore the first run, as it always seems to be very non-representative
    echo "First CBench run will be discarded, as it's non-representative."
    echo "Initial CBench run..."
    cbench -c localhost -p 6633 -m $MS_PER_TEST -l $TESTS_PER_SWITCH -s $NUM_SWITCHES -M $NUM_MACS &> /dev/null

    # Parse out average responses/second
    echo "Primary CBench run..."
    avg=`cbench -c localhost -p 6633 -m $MS_PER_TEST -l $TESTS_PER_SWITCH -s $NUM_SWITCHES -M $NUM_MACS 2>&1 \
        | grep RESULT | awk '{print $8}' | awk -F'/' '{print $3}'`
    echo "Average responses/second: $avg"

    # Store results in CVS format
    get_next_run_num
    run_num=$?
    echo "$run_num,$avg" >> $RESULTS_FILE

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
    wget -P $BASE_DIR "https://jenkins.opendaylight.org/integration/job/integration-project-centralized-integration/lastSuccessfulBuild/artifact/distributions/base/target/$ODL_ZIP" &> /dev/null
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

odl_started()
{
    # Checks if OpenDaylight is running
    # Assumes you've checked that ODL is installed
    cd $ODL_DIR
    if ./run.sh -status &> /dev/null; then
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
            if ! odl_installed; then
                echo "OpenDaylight isn't installed, can't run test"
                exit $EX_ERR
            fi
            if ! odl_started; then
                echo "OpenDaylight isn't started, can't run test"
                exit $EX_ERR
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
