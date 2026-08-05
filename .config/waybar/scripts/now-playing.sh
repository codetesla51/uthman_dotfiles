#!/bin/bash

if ! command -v playerctl >/dev/null 2>&1; then
  echo '{"text": ""}'
  exit 0
fi

status=$(playerctl status 2>/dev/null)
if [[ "$status" != "Playing" && "$status" != "Paused" ]]; then
  echo '{"text": ""}'
  exit 0
fi

title=$(playerctl metadata --format '{{title}}' 2>/dev/null)
artist=$(playerctl metadata --format '{{artist}}' 2>/dev/null)
album=$(playerctl metadata --format '{{album}}' 2>/dev/null)
pos=$(playerctl position 2>/dev/null)
len=$(playerctl metadata mpris:length 2>/dev/null)

truncate() {
  local s="$1" n="$2"
  if (( ${#s} > n )); then
    s="${s:0:n-1}…"
  fi
  printf '%s' "$s"
}

title=$(truncate "$title" 30)
artist=$(truncate "$artist" 18)

escape_xml() {
  local s="$1"
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  printf '%s' "$s"
}

title=$(escape_xml "$title")
artist=$(escape_xml "$artist")
album=$(escape_xml "$album")

# progress bar
bar=""
if [[ -n "$pos" && -n "$len" && "$len" -gt 0 ]]; then
  pct=$(awk -v p="$pos" -v l="$(( len / 1000000 ))" 'BEGIN{r = l > 0 ? (p/l)*100 : 0; printf "%d", r}')
  pct=$(( pct > 100 ? 100 : pct < 0 ? 0 : pct ))
  filled=$(( pct * 10 / 100 ))
  bar=$(printf '%*s' "$filled" '')
  bar=${bar// /█}
  rest=$(printf '%*s' $((10 - filled)) '')
  rest=${rest// /░}
  bar+="$rest"
fi

if [[ "$status" == "Playing" ]]; then
  cls="playing"
  icon="󰝋"
  eq=("▁▂▃▄" "▄▃▂▁" "▂▄▁▃" "▃▁▄▂")
  state_file="/tmp/waybar-nowplaying-eq"
  if [[ -f "$state_file" ]]; then
    i=$(cat "$state_file" 2>/dev/null)
  else
    i=0
  fi
  i=$(( (i + 1) % 4 ))
  echo "$i" > "$state_file"
  eq="${eq[$i]}"
else
  cls="paused"
  icon="󰏤"
  eq=""
fi

label="$icon  $title"
[[ -n "$artist" ]] && label="$label  ·  $artist"
[[ -n "$eq" ]] && label="$label  $eq"
[[ -n "$bar" ]] && label="$label  $bar"

tooltip="$title"
[[ -n "$artist" ]] && tooltip="$tooltip  ·  $artist"
[[ -n "$album" ]] && tooltip="$tooltip\n󰀥  $album"
[[ -n "$bar" ]] && tooltip="$tooltip\n$bar"

jq -c -n --arg text "$label" --arg tooltip "$tooltip" --arg class "$cls" \
  '{text: $text, tooltip: $tooltip, class: $class}'
