#!/bin/bash

# Check if using dunst or mako
if command -v dunstctl &> /dev/null; then
    count=$(dunstctl count waiting)
    history=$(dunstctl count history)
    total=$((count + history))
elif command -v makoctl &> /dev/null; then
    count=$(makoctl list | jq length 2>/dev/null || echo 0)
    total=$count
else
    exit 0
fi

if [ "$total" -gt 0 ]; then
    echo "  $total"
else
    echo ""
fi