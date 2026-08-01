#!/bin/bash

# Get currently playing media via playerctl
if command -v playerctl &> /dev/null; then
    status=$(playerctl status 2>/dev/null)
    
    if [ "$status" = "Playing" ]; then
        artist=$(playerctl metadata artist 2>/dev/null)
        title=$(playerctl metadata title 2>/dev/null)
        
        if [ -n "$artist" ] && [ -n "$title" ]; then
            # Truncate if too long
            combined="$artist - $title"
            if [ ${#combined} -gt 50 ]; then
                combined="${combined:0:47}..."
            fi
            echo "󰎈  $combined"
        fi
    fi
fi