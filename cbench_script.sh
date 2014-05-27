#!/usr/bin/env sh
# Script for running automated CBench regression tests

EX_USAGE=64
EX_CBENCH_NOT_FOUND=65
EX_ODL_NOT_FOUND=66
EX_OK=0
EX_ERR=1

BASE_DIR=$HOME
NUM_SWITCHES=16
NUM_MACS=100000
TESTS_PER_SWITCH=20
MS_PER_TEST=1000
OSGI_PORT=2400

# Print usage message
usage()
{
cat << EOF
Usage $0 [options]

Setup and run CBench and OpenDaylight

OPTIONS:
    -h Show this message
    -r Run CBench against OpenDaylight
    -c Install CBench
    -i Install ODL from last sucessful build
    -I Install ODL from source
    -o Run ODL from last sucessful build
    -O Run ODL from source
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
        return $EX_CBENCH_NOT_FOUND
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
    cd $BASE_DIR
    git clone https://github.com/andi-bigswitch/oflops.git

    # CBench requires the OpenFlow source code, clone it
    git clone git://gitosis.stanford.edu/openflow.git
    of_dir="$PWD/openflow"

    # Build the oflops/configure file
    cd oflops
    ./boot.sh

    # Build oflops
    ./configure --with-openflow-src-dir=$of_dir
    make
    sudo make install
    cd $BASE_DIR

    if ! cbench_installed; then
        echo "Failed to install CBench" >&2
        exit $EX_ERR
    else
        echo "Successfully installed CBench"
        return $EX_OK
    fi
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
    # TODO: Return avg to Jenkins
}

install_opendaylight()
{
    # Installs latest build of the OpenDaylight controller
    # Remove old unzipped controller code
    if [ -d "$BASE_DIR/opendaylight" ]; then
        rm -rf $BASE_DIR/opendaylight
    fi
    # Remove old zipped controller code
    if [ -f $BASE_DIR/distributions-base-0.1.2-SNAPSHOT-osgipackage.zip ]; then
        rm -f $BASE_DIR/distributions-base-0.1.2-SNAPSHOT-osgipackage.zip
    fi

    # Install required packages
    sudo yum install -y java-1.7.0-openjdk unzip wget which

    # Grab last successful build
    wget -P $BASE_DIR 'https://jenkins.opendaylight.org/integration/job/integration-project-centralized-integration/lastSuccessfulBuild/artifact/distributions/base/target/distributions-base-0.1.2-SNAPSHOT-osgipackage.zip'
    unzip -d $BASE_DIR $BASE_DIR/distributions-base-0.1.2-SNAPSHOT-osgipackage.zip

    # Make some plugin changes that are apparently required for CBench
    PLUGIN_DIR=$BASE_DIR/opendaylight/plugins
    wget -P $PLUGIN_DIR 'https://jenkins.opendaylight.org/openflowplugin/job/openflowplugin-merge/lastSuccessfulBuild/org.opendaylight.openflowplugin$drop-test/artifact/org.opendaylight.openflowplugin/drop-test/0.0.3-SNAPSHOT/drop-test-0.0.3-SNAPSHOT.jar'
    rm $PLUGIN_DIR/org.opendaylight.controller.samples.simpleforwarding-0.4.2-SNAPSHOT.jar
    rm $PLUGIN_DIR/org.opendaylight.controller.arphandler-0.5.2-SNAPSHOT.jar

    # TODO: Change controller log level to ERROR. Confirm this is necessary.
}

start_opendaylight()
{
    # Starts the OpenDaylight controller
    cd $BASE_DIR/opendaylight
    # The -start flag makes OSGi listen on port 2400
    ./run.sh -start -of13 -Xms1g -Xmx4g &
    odl_pid=$!
    # TODO: Calibrate sleep time
    sleep 120
    issue_odl_config
}

issue_odl_config()
{
    # Give dropAllPackets command via telnet to OSGi
    # This is a bit of a hack, but it's the only method I know of
    # See: https://ask.opendaylight.org/question/146/issue-non-interactive-gogo-shell-command/
    sudo yum install telnet -y
    echo "dropAllPacketsRpc on" | telnet 127.0.0.1 $OSGI_PORT
}

stop_opendaylight()
{
    # Kills the ODL process if we started it here
    if [ -n $odl_pid ]; then
        kill $odl_pid
    else
        echo "Warning: OpenDaylight was unexpectedly not running" >&2
    fi
}

cleanup()
{
    # Removes ODL and the ZIP archive we extracted it from
    rm -rf $BASE_DIR/opendaylight
    rm -rf $BASE_DIR/distributions-base-0.1.2-SNAPSHOT-osgipackage.zip
}

# If executed with no options
if [ $# -eq 0 ]; then
    echo "No options given. Installing ODL+CBench and running test."
    install_cbench
    install_opendaylight
    start_opendaylight
    issue_odl_config
    run_cbench
    stop_opendaylight
    exit $EX_OK
fi


while getopts ":hrciod" opt; do
    case "$opt" in
        h)
            # Help message
            usage
            exit $EX_OK
            ;;
        r)
            # Run CBench against OpenDaylight
            start_opendaylight
            issue_odl_config
            run_cbench
            stop_opendaylight
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
            start_opendaylight
            echo "Use \`pkill java\` to stop OpenDaylight"
            ;;
        d)
            # Delete local ODL code
            cleanup
            ;;
        *)
            usage
            exit $EX_USAGE
    esac
done
