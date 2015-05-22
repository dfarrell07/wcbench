#!/usr/bin/env sh
# Helper script to run WCBench tests in a loop, used for testing
# Script assumes it lives in the same dir as wcbench.sh

# Exit codes
EX_USAGE=64
EX_OK=0

# Output verbose debug info (true) or not (anything else)
VERBOSE=false

###############################################################################
# Prints usage message
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
###############################################################################
usage()
{
    cat << EOF
Usage $0 [options]

Run WCBench against OpenDaylight in a loop.

OPTIONS:
    -h Show this help message
    -v Output verbose debug info
    -l <num_runs> Loop WCBench given number of times without restarting ODL
    -r <num_runs> Loop WCBench given number of times, restart ODL between runs
    -t <time> Run WCBench for a given number of minutes
    -p <processors> Pin ODL to given number of processors
EOF
}

###############################################################################
# Starts ODL, optionally pinning it to a given number of processors
# Globals:
#   processors
#   VERBOSE
# Arguments:
#   None
# Returns:
#   WCBench exit status
###############################################################################
start_odl()
{
    if "$VERBOSE" = true; then
        if [ -z $processors ]; then
            # Start ODL, don't pass processor info
            echo "Starting ODL, not passing processor info"
            ./wcbench.sh -vo
        else
            # Start ODL, pinning it to given number of processors
            echo "Pinning ODL to $processors processor(s)"
            ./wcbench.sh -vp $processors -o
        fi
    else
        if [ -z $processors ]; then
            # Start ODL, don't pass processor info
            echo "Starting ODL, not passing processor info"
            ./wcbench.sh -o
        else
            # Start ODL, pinning it to given number of processors
            echo "Pinning ODL to $processors processor(s)"
            ./wcbench.sh -p $processors -o
        fi
    fi
}

###############################################################################
# Run WCBench against ODL, optionally passing a WCBench run time
# Globals:
#   run_time
#   VERBOSE
# Arguments:
#   None
# Returns:
#   WCBench exit status
###############################################################################
run_wcbench()
{
    if "$VERBOSE" = true; then
        if [ -z $run_time ]; then
            # Flag means run WCBench
            echo "Running WCBench, not passing run time info"
            ./wcbench.sh -vr
        else
            # Flags mean use $run_time WCBench runs, run WCBench
            echo "Running WCBench with $run_time minute(s) run time"
            ./wcbench.sh -vt $run_time -r
        fi
    else
        if [ -z $run_time ]; then
            # Flag means run WCBench
            echo "Running WCBench, not passing run time info"
            ./wcbench.sh -r
        else
            # Flags mean use $run_time WCBench runs, run WCBench
            echo "Running WCBench with $run_time minute(s) run time"
            ./wcbench.sh -t $run_time -r
        fi
    fi
}

###############################################################################
# Run WCBench against ODL a given number of times without restarting ODL
# Globals:
#   None
# Arguments:
#   The number of times to run WCBench against ODL
# Returns:
#   Exit status of run_wcbench
###############################################################################
loop_no_restart()
{
    num_runs=$1
    echo "Looping WCBench without restarting ODL"
    for (( runs_done = 0; runs_done < $num_runs; runs_done++ )); do
        echo "Starting run $(expr $runs_done + 1) of $num_runs"
        start_odl

        # Do this last so fn returns same exit code
        run_wcbench
    done
}

###############################################################################
# Run WCBench against ODL a given number of times, restart ODL between runs
# Globals:
#   VERBOSE
# Arguments:
#   The number of times to run WCBench against ODL
# Returns:
#   WCBench exit status
###############################################################################
loop_with_restart()
{
    num_runs=$1
    echo "Looping WCBench, restarting ODL each run"
    for (( runs_done = 0; runs_done < $num_runs; runs_done++ )); do
        echo "Starting run $(expr $runs_done + 1) of $num_runs"
        start_odl
        run_wcbench

        # Stop ODL. Do this last so fn returns same exit code.
        if "$VERBOSE" = true; then
            ./wcbench.sh -vk
        else
            ./wcbench.sh -k
        fi
    done
}

# If executed with no options
if [ $# -eq 0 ]; then
    usage
    exit $EX_USAGE
fi

# Used to output help if no valid action results from arguments
action_taken=false

# Parse options given from command line
while getopts ":hvl:p:r:t:" opt; do
    case "$opt" in
        h)
            # Help message
            usage
            exit $EX_OK
            ;;
        v)
            # Output debug info verbosely
            VERBOSE=true
            ;;
        l)
            # Loop without restarting ODL between WCBench runs
            num_runs=${OPTARG}

            if [[ $num_runs -lt 1 ]]; then
                echo "Doing less than 1 run doesn't make sense"
                exit $EX_USAGE
            else
                echo "Will run WCBench against ODL $num_runs time(s)"
            fi

            # Kick off testing loop
            loop_no_restart $num_runs
            action_taken=true
            ;;
        p)
            # Pin a given number of processors
            # Note that this option must be given before -o (start ODL)
            processors=${OPTARG}
            if [ $processors -lt 1 ]; then
                echo "Can't pin ODL to less than one processor"
                exit $EX_USAGE
            fi
            ;;
        r)
            # Restart ODL between each WCBench run
            num_runs=${OPTARG}

            if [[ $num_runs -lt 1 ]]; then
                echo "Doing less than 1 run doesn't make sense"
                exit $EX_USAGE
            else
                echo "Will run WCBench against ODL $num_runs time(s)"
            fi

            # Kick off testing loop
            loop_with_restart $num_runs
            action_taken=true
            ;;
        t)
            # Set length of WCBench run in minutes
            run_time=${OPTARG}
            ;;
        *)
            # Print usage message
            usage
            exit $EX_USAGE
    esac
done

# Output help message if no valid action was taken
if ! "$action_taken" = true; then
    usage
    exit $EX_USAGE
fi
