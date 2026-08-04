#!/bin/bash

out=$(timeout 10 omarchy-update-available 2>/dev/null)

if [[ "$out" == *"update available"* ]]; then
  echo "{\"text\":\"󰇥\",\"tooltip\":\"${out} — click to update\",\"class\":\"pending\"}"
else
  echo '{"text":""}'
fi
