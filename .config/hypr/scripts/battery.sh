#!/bin/bash

battery_path="/sys/class/power_supply/BAT0"
[ ! -d "$battery_path" ] && battery_path="/sys/class/power_supply/BAT1"

if [ -d "$battery_path" ]; then
    capacity=$(cat "$battery_path/capacity")
    status=$(cat "$battery_path/status")
    
    if [ "$status" = "Charging" ]; then
        icon="󱐋"
        text="<span foreground='#a6e3a1'>$icon $capacity%</span>"
    elif [ "$status" = "Full" ]; then
        icon="󰚥"
        text="<span foreground='#a6e3a1'>$icon $capacity%</span>"
    else
        if [ "$capacity" -ge 80 ]; then
            icon="󰁹"
        elif [ "$capacity" -ge 60 ]; then
            icon="󰂀"
        elif [ "$capacity" -ge 40 ]; then
            icon="󰁾"
        elif [ "$capacity" -ge 20 ]; then
            icon="󰁼"
        else
            icon="󰁺"
        fi
        text="$icon $capacity%"
    fi
    
    echo "$text"
else
    echo ""
fi
