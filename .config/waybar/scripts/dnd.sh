#!/bin/bash

if [[ "$(swaync-client -D 2>/dev/null)" == "true" ]]; then
  echo '{"text":"󰂛","tooltip":"Notifications silenced — click to enable","class":"active"}'
else
  echo '{"text":""}'
fi
