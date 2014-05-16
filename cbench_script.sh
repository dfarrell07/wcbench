#!/usr/bin/env sh
# Script for running automated CBench regression tests

EX_USAGE=64
EX_CBENCH_NOT_FOUND=65
EX_OK=0
EX_ERR=1

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
    # Note that I'm not currently building oflops/netfpga-packet-generator-c-library (optional)
    if cbench_installed; then
        return $EX_OK
    fi

    # Install required packages
    sudo yum install -y net-snmp-devel libpcap-devel autoconf automake libtool libconfig-devel git

    # Clone repo that contains CBench
    git clone https://github.com/andi-bigswitch/oflops.git

    # CBench requires the OpenFlow source code, clone it
    git clone git://gitosis.stanford.edu/openflow.git
    of_dir="$PWD/openflow"

    # Build the oflops/configure file
    cd oflops
    ./boot.sh

    # Build oflops
    # TODO: Git abs path
    ./configure --with-openflow-src-dir=$of_dir
    make
    sudo make install
    cd ..

    if ! cbench_installed; then
        echo "Failed to install CBench" >&2
        exit $EX_ERR
    else
        echo "Successfully installed CBench"
        return $EX_OK
    fi
}

install_cbench
