#!/bin/bash

icon=$(omarchy-weather-icon 2>/dev/null)
status=$(timeout 8 omarchy-weather-status 2>/dev/null)

if [[ -n "$status" && "$status" != "Weather unavailable" ]]; then
  place=$(printf '%s' "$status" | sed -E 's/^[^ ]+ +//; s/ *·.*//' | xargs)
  temp=$(printf '%s' "$status" | grep -oE '[0-9]+°C' | head -1)
  wind=$(printf '%s' "$status" | grep -oE '↗[0-9]+ ?(km/h|mph)|↘[0-9]+ ?(km/h|mph)|←[0-9]+ ?(km/h|mph)|→[0-9]+ ?(km/h|mph)|↑[0-9]+ ?(km/h|mph)|↓[0-9]+ ?(km/h|mph)|[0-9]+ ?(km/h|mph)|Calm' | head -1)

  text="${icon}  ${place}"
  [[ -n "$temp" ]] && text="${text}  ·  ${temp}"
  [[ -n "$wind" ]] && text="${text}  ·  ${wind}"

  printf '{"text":"%s","tooltip":"%s","class":""}\n' "$text" "$status"
else
  printf '{"text":"","class":"unavailable"}\n'
fi
