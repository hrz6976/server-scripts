#!/bin/bash

set -e

# Check memory usage
mem_usage=$(free | awk '/Mem/{print $3/$2 * 100.0}')

# If memory usage is above 98%, kill process with highest memory usage
if (( $(echo "$mem_usage > 98" | bc -l) )); then
    pid_cmd="ps aux --sort=-%mem | awk 'NR==2{print $2}'"
    pid=$(eval $pid_cmd)
    pname=$(ps -p $pid -o comm=)
    puser=$(ps -p $pid -o user=)
    kill -9 $pid
    logger "Killing process $pname with PID $pid due to high memory usage: $mem_usage %"
    # send a message to the user
    time=$(date)
    echo "[$time] Killing process $pname with PID $pid due to high memory usage: $mem_usage %" | wall -n -u $puser
fi