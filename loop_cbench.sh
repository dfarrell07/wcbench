#!/usr/bin/env sh
# Helper script to run CBench tests in a loop, used for testing

# Exit codes
EX_USAGE=64
EX_OK=0

usage()
{
    # Print usage message
    cat << EOF
Usage $0 [options]

Run CBench against OpenDaylight in a loop.

OPTIONS:
    -h Show this help message
    -l Loop CBench runs without restarting ODL
    -r Loop CBench runs, restart ODL between runs
    -t Run CBench for a given number of minutes
EOF
}


loop_no_restart()
{
    # Repeatedly run CBench against ODL without restarting ODL
    # Start ODL
    ./cbench.sh -o
    while :; do
        if [ -z $run_time ]; then
            # Flag means run CBench
            ./cbench.sh -r
        else
            # Flags mean use $run_time CBench runs, run CBench
            ./cbench.sh -t $run_time -r
        fi
    done
}


loop_with_restart()
{
    # Repeatedly run CBench against ODL without restarting ODL
    # Start ODL
    ./cbench.sh -o
    while :; do
        if [ -z $run_time ]; then
            # Flags mean run CBench, kill ODL, start ODL
            ./cbench.sh -rko
        else
            # Flags mean use $run_time CBench runs, run CBench, kill ODL, start ODL
            ./cbench.sh -t $run_time -rko
        fi
    done
}


# If executed with no options
if [ $# -eq 0 ]; then
    usage
    exit $EX_USAGE
fi


while getopts ":hrt:" opt; do
    case "$opt" in
        h)
            # Help message
            usage
            exit $EX_OK
            ;;
        l)
            # Loop without restarting ODL between CBench runs
            echo "Looping CBench against ODL without restarting ODL between runs"
            loop_no_restart
            ;;
        r)
            # Restart ODL between each CBench run
            echo "Looping CBench against ODL, restarting ODL between runs"
            loop_with_restart
            ;;
        t)
            # Set length of CBench run in minutes
            run_time=${OPTARG}
            echo "Calls to cbench.sh will pass $run_time minute CBench run time"
            echo "Note that you need to give a loop flag after this flag"
            ;;
        *)
            usage
            exit $EX_USAGE
    esac
done
