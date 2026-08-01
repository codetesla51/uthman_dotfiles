#!/bin/bash

# Get uptime (clean format)
uptime_sec=$(awk '{print int($1)}' /proc/uptime)
hours=$((uptime_sec / 3600))
mins=$(((uptime_sec % 3600) / 60))

if [ $hours -gt 0 ]; then
    uptime="${hours}h ${mins}m"
else
    uptime="${mins}m"
fi

echo "󰔚 $uptime"