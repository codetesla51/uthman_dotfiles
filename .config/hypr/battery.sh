#!/bin/bash

# Battery status helper script.

battery_path="/sys/class/power_supply/BAT0"

if [ -d "$battery_path" ]; then
    capacity=$(cat "$battery_path/capacity")
    status=$(cat "$battery_path/status")
    
    # Choose icon based on battery level and status
    if [ "$status" = "Charging" ]; then
        icon="󰂄"
    elif [ "$capacity" -ge 90 ]; then
        icon="󰁹"
    elif [ "$capacity" -ge 80 ]; then
        icon="󰂂"
    elif [ "$capacity" -ge 60 ]; then
        icon="󰂀"
    elif [ "$capacity" -ge 40 ]; then
        icon="󰁾"
    elif [ "$capacity" -ge 20 ]; then
        icon="󰁼"
    else
        icon="󰁺"
    fi
    
    echo "$icon $capacity%"
else
    # No battery found (desktop)
    echo ""
fi