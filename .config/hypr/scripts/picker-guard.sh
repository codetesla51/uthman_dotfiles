#!/bin/bash
# picker-guard — last line of defence against screen-capture overlays.
#
# A stuck or chattering key can fire a capture bind repeatedly. Each spawn
# (slurp / hyprpicker / satty) grabs the pointer and freezes a copy of the
# screen; stack enough of them and the display is solid white with no way out
# except a TTY. This runs for the first 90s of a session:
#   1. clears overlays left over from a previous session
#   2. wipes any burst of capture overlays, since more than one is never
#      intentional (a normal screenshot is exactly one)
# Exits on its own so it costs nothing after login.
pkill -x slurp 2>/dev/null
pkill -x hyprpicker 2>/dev/null
pkill -x satty 2>/dev/null

for _ in $(seq 1 90); do
    sleep 1
    # pgrep takes a single pattern, so count each overlay type and sum them
    count=$( (pgrep -x slurp; pgrep -x hyprpicker; pgrep -x satty) 2>/dev/null | wc -l )
    if [ "$count" -gt 1 ]; then
        pkill -x slurp 2>/dev/null
        pkill -x hyprpicker 2>/dev/null
        pkill -x satty 2>/dev/null
    fi
done
