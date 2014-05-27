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

opendaylight_installed()
{
    # Checks if OpenDaylight is installed in BASE_DIR
    cd $BASE_DIR
    # Ignoring symlink special case, don't care
    if [ -d "opendaylight" ]; then
        echo "OpenDaylight is installed"
        return $EX_OK
    else
        echo "OpenDaylight is not installed"
        return $EX_ODL_NOT_FOUND
    fi
}

build_odl_from_source()
{
    # TODO: Doc string
    # Remove old unzipped controller code
    if [ -d "$BASE_DIR/controller" ]; then
        rm -rf $BASE_DIR/controller
    fi

    # Install required packages
    sudo yum install -y java-1.7.0-openjdk maven

    # Grab source
    git clone https://git.opendaylight.org/gerrit/p/controller.git $BASE_DIR/controller

    # Build script to issue required non-interactive cmd to OSGi console
    echo "dropAllPacketsRpc on" > $BASE_DIR/configure_cbench.gosh

    # Build with maven
    cd $BASE_DIR/controller/opendaylight/distribution/opendaylight
    mvn clean install

    # Make some plugin changes that are apparently required for CBench
    PLUGIN_DIR=$BASE_DIR/controller/opendaylight/distribution/opendaylight/target/distribution.opendaylight-osgipackage/opendaylight/plugins
    wget -P $PLUGIN_DIR 'https://jenkins.opendaylight.org/openflowplugin/job/openflowplugin-merge/lastSuccessfulBuild/org.opendaylight.openflowplugin$drop-test/artifact/org.opendaylight.openflowplugin/drop-test/0.0.3-SNAPSHOT/drop-test-0.0.3-SNAPSHOT.jar'
}

start_odl_built_from_source()
{
    cd $BASE_DIR/controller/opendaylight/distribution/opendaylight/target/distribution.opendaylight-osgipackage/opendaylight
    ./run.sh &
    odl_pid=$!
    # TODO: Calibrate sleep time
    sleep 120
}

install_opendaylight()
{
    # Installs latest build of the OpenDaylight controller
    cd $BASE_DIR
    # Remove old unzipped controller code
    if [ -d "opendaylight" ]; then
        rm -rf opendaylight
    fi
    # Remove old zipped controller code
    if [ -f distributions-base-0.1.2-SNAPSHOT-osgipackage.zip ]; then
        rm -f distributions-base-0.1.2-SNAPSHOT-osgipackage.zip
    fi

    # Install required packages
    sudo yum install -y java-1.7.0-openjdk unzip wget which

    # Grab last successful build
    cd $BASE_DIR
    wget 'https://jenkins.opendaylight.org/integration/job/integration-project-centralized-integration/lastSuccessfulBuild/artifact/distributions/base/target/distributions-base-0.1.2-SNAPSHOT-osgipackage.zip'
    unzip distributions-base-0.1.2-SNAPSHOT-osgipackage.zip

    # Make some plugin changes that are apparently required for CBench
    cd opendaylight/plugins
    # This step is confirmed required
    wget 'https://jenkins.opendaylight.org/openflowplugin/job/openflowplugin-merge/lastSuccessfulBuild/org.opendaylight.openflowplugin$drop-test/artifact/org.opendaylight.openflowplugin/drop-test/0.0.3-SNAPSHOT/drop-test-0.0.3-SNAPSHOT.jar'
    # TODO: Confirm these steps are required
    rm org.opendaylight.controller.samples.simpleforwarding-0.4.2-SNAPSHOT.jar
    rm org.opendaylight.controller.arphandler-0.5.2-SNAPSHOT.jar

    # TODO: Change controller log level to ERROR. Confirm this is necessary.
}

start_opendaylight()
{
    # Starts the OpenDaylight controller
    cd $BASE_DIR/opendaylight
    ./run.sh -of13 -Xms1g -Xmx4g &
    odl_pid=$!
    # TODO: Calibrate sleep time
    sleep 120
    # TODO: Give `dropAllPacketsRpc on` cmd, likely via Gogo script. Confirmed necessary.
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

cleanup()
{
    # Removes ODL and the ZIP archive we extracted it from
    rm -rf $BASE_DIR/opendaylight
    rm -rf $BASE_DIR/distributions-base-0.1.2-SNAPSHOT-osgipackage.zip
    rm -rf $BASE_DIR/controller
}

# If executed with no options
if [ $# -eq 0 ]; then
    echo "No options given. Installing ODL+CBench and running test."
    install_cbench
    install_opendaylight
    start_opendaylight
    run_cbench
    stop_opendaylight
    exit $EX_OK
fi


while getopts ":hrciIoOd" opt; do
    case "$opt" in
        h)
            # Help message
            usage
            exit $EX_OK
            ;;
        r)
            # Run CBench against OpenDaylight
            start_opendaylight
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
        I)
            # Install OpenDaylight from source
            build_odl_from_source
            ;;
        o)
            # Run OpenDaylight from last successful build
            start_opendaylight
            echo "Use \`pkill java\` to stop OpenDaylight"
            ;;
        O)
            # Run OpenDaylight built from source
            start_odl_built_from_source
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
