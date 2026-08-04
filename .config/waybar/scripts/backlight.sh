#!/bin/bash

pct=$(brightnessctl -m 2>/dev/null | awk -F, 'NR==1{print $3; exit}')

if [[ -z "$pct" ]]; then
  echo '{"text": ""}'
  exit 0
fi

icon="󰃟"
if   [[ "$pct" -lt 10 ]]; then icon="󰃝"
elif [[ "$pct" -lt 35 ]]; then icon="󰃞"
fi

echo "{\"text\":\"${icon} ${pct}%\",\"tooltip\":\"Brightness ${pct}%\"}"
