#!/bin/bash

# Check if gpu-screen-recorder is running
if pgrep -f "^gpu-screen-recorder" > /dev/null; then
    # Recording is active
    echo "{\"text\":\"󰑊\", \"class\":\"recording\", \"tooltip\":\"Recording in progress\nLeft-click: Stop\nRight-click: Stop (w/ audio)\nMiddle-click: Stop (w/ webcam)\"}"
else
    # Not recording
    echo "{\"text\":\"󰻃\", \"class\":\"idle\", \"tooltip\":\"Start recording\nLeft-click: Basic recording\nRight-click: With desktop audio\nMiddle-click: With webcam\"}"
fi
