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
    -p <processors> Peg ODL to given number of processors
EOF
}


loop_no_restart()
{
    # Repeatedly run CBench against ODL without restarting ODL
    if [ -z $processors ]; then
        ./run.sh -start $OSGI_PORT -of13 -Xms1g -Xmx4g &> /dev/null
    else
        echo "Pinning ODL to $processors processor(s)"
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


while getopts ":lhrt:" opt; do
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
        p)
            # Peg a given number of processors
            # Note that this option must be given before -o (start ODL)
            processors=${OPTARG}
            if [ $processors -lt 1 ]; then
                echo "Can't peg ODL to less than one processor"
                exit $EX_USAGE
            fi
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
