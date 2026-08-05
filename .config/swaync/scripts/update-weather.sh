#!/bin/bash

config="/home/uthman/dotfiles/.config/swaync/config.json"
weather=$(omarchy-weather-status 2>/dev/null)

if [[ -z "$weather" || "$weather" == "Weather unavailable" ]]; then
  weather="󰖪  Weather unavailable"
fi

python3 - "$config" "$weather" <<'EOF'
import json, sys
path, text = sys.argv[1], sys.argv[2]
cfg = json.load(open(path))
cfg["widget-config"]["label#weather"]["text"] = text
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
EOF

swaync-client -R
