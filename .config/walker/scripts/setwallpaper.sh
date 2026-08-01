#!/bin/bash
WALL="$1"
ln -nsf "$WALL" ~/.config/omarchy/current/background
pkill -x swaybg
setsid swaybg -i "$WALL" -m fill >/dev/null 2>&1 &
nohup /home/uthman/.local/bin/getTheme -t fidelity -m dark -c 0.1 "$WALL" >/dev/null 2>&1 &
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
