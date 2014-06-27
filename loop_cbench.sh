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
    -r Restart OpenDaylight between each CBench run
EOF
}


loop_no_restart()
{
    # Repeatedly run CBench against ODL without restarting ODL
    ./cbench.sh -o
    while :; do
        ./cbench.sh -r
    done
}


loop_with_restart()
{
    # Repeatedly run CBench against ODL without restarting ODL
    ./cbench.sh -o
    while :; do
        # Flags mean run CBench, kill ODL, start ODL
        ./cbench.sh -rko
    done
}


# If executed with no options
if [ $# -eq 0 ]; then
    echo "Looping CBench against ODL without restarting ODL between runs"
    loop_no_restart
fi


while getopts ":hr" opt; do
    case "$opt" in
        h)
            # Help message
            usage
            exit $EX_OK
            ;;
        r)
            # Restart ODL between each CBench run
            loop_with_restart
            ;;
        *)
            usage
            exit $EX_USAGE
    esac
done
