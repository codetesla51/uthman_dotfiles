#!/bin/bash

zone=""
for z in /sys/class/thermal/thermal_zone*; do
  if [[ "$(cat "$z/type" 2>/dev/null)" == "x86_pkg_temp" ]]; then
    zone="$z"
    break
  fi
done

if [[ -z "$zone" ]]; then
  echo '{"text": ""}'
  exit 0
fi

temp=$(awk '{printf "%.0f", $1/1000}' "$zone/temp" 2>/dev/null)
cls=""
icon="󰈐"
if [[ "$temp" -ge 85 ]]; then
  cls="critical"
  icon="󰈇"
elif [[ "$temp" -ge 70 ]]; then
  cls="warning"
fi

echo "{\"text\":\"${icon} ${temp}°C\",\"tooltip\":\"CPU ${temp}°C\",\"class\":\"${cls}\"}"
