#!/bin/bash

out=$(timeout 10 omarchy-update-available 2>/dev/null)

if [[ "$out" == *"update available"* ]] && [[ "$out" != *"v4.0.0"* ]]; then
  echo "{\"text\":\"󰇥\",\"tooltip\":\"${out} — click to update\",\"class\":\"pending\"}"
else
  echo '{"text":""}'
fi
