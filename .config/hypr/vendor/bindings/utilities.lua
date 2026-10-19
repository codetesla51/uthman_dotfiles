-- Vendored utility binds (sanitized Omarchy copy, from utilities.conf).
-- Flag legend: bindld -> { locked, description }; bindl -> { locked };
-- binddr -> { description, release }.

-- Menus
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("walker-dmenu"), { description = "Launch apps" })
hl.bind("SUPER + CTRL + E", hl.dsp.exec_cmd("walker-dmenu -m symbols"), { description = "Emoji picker" })
hl.bind("SUPER + CTRL + C", hl.dsp.exec_cmd("omarchy-menu capture"), { description = "Capture menu" })
hl.bind("SUPER + CTRL + O", hl.dsp.exec_cmd("omarchy-menu toggle"), { description = "Toggle menu" })
hl.bind("SUPER + CTRL + H", hl.dsp.exec_cmd("omarchy-menu hardware"), { description = "Hardware menu" })
hl.bind("SUPER + ALT + SPACE", hl.dsp.exec_cmd("omarchy-menu"), { description = "Omarchy menu" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("omarchy-menu"), { description = "Omarchy menu" })
hl.bind("SUPER + ESCAPE", hl.dsp.exec_cmd("omarchy-menu system"), { description = "System menu" })
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("omarchy-menu system"), { locked = true, description = "Power menu" })
hl.bind("SUPER + K", hl.dsp.exec_cmd("omarchy-menu-keybindings"), { description = "Show key bindings" })
hl.bind("XF86Calculator", hl.dsp.exec_cmd("gnome-calculator"), { description = "Calculator" })

-- Aesthetics
hl.unbind("SUPER + SHIFT + SPACE")
hl.bind("SUPER + CTRL + SPACE", hl.dsp.exec_cmd("uwsm-app -- ~/.config/rofi/wall.sh"), { description = "Theme background menu" })
hl.bind("SUPER + SHIFT + CTRL + SPACE", hl.dsp.exec_cmd('sh -c "quickshell -p ~/.config/quickshell ipc call theme toggle"'), { description = "Theme menu" })
hl.bind("SUPER + BACKSPACE", hl.dsp.exec_cmd("winfx transparent"), { description = "Toggle window transparency" })
hl.bind("SUPER + SHIFT + BACKSPACE", hl.dsp.exec_cmd("winfx gaps"), { description = "Toggle window gaps" })
hl.bind("SUPER + CTRL + BACKSPACE", hl.dsp.exec_cmd("omarchy-hyprland-window-single-square-aspect-toggle"), { description = "Toggle single-window square aspect" })

-- Notifications
hl.bind("SUPER + CTRL + COMMA", hl.dsp.exec_cmd("omarchy-toggle-notification-silencing"), { description = "Toggle silencing notifications" })

-- Toggles
hl.bind("SUPER + CTRL + I", hl.dsp.exec_cmd("idle-toggle"), { description = "Toggle locking on idle" })
hl.bind("SUPER + CTRL + N", hl.dsp.exec_cmd("nightlight"), { description = "Toggle nightlight" })
hl.bind("SUPER + CTRL + DELETE", hl.dsp.exec_cmd("mon-toggle"), { description = "Toggle laptop display" })
hl.bind("SUPER + CTRL + ALT + DELETE", hl.dsp.exec_cmd("omarchy-hyprland-monitor-internal-mirror toggle"), { description = "Toggle laptop display mirroring" })
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("omarchy-hw-external-monitors && omarchy-hyprland-monitor-internal off"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("omarchy-hyprland-monitor-internal on"), { locked = true })

-- Captures. NOTE: screenshots are on explicit letter keys, never Print — a
-- spurious Print event from the hardware/greeter used to launch capture overlays.
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("shot full"), { description = "Screenshot fullscreen" })
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd("shot"), { description = "Screenshot (drag area)" })

-- File sharing
hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd("omarchy-menu share"), { description = "Share" })

-- Transcoding
hl.bind("SUPER + CTRL + PERIOD", hl.dsp.exec_cmd("omarchy-transcode"), { description = "Transcode" })

-- Reminders
hl.bind("SUPER + CTRL + R", hl.dsp.exec_cmd("omarchy-menu reminder-set"), { description = "Set reminder" })
hl.bind("SUPER + CTRL + ALT + R", hl.dsp.exec_cmd("omarchy-reminder show"), { description = "Show reminders" })
hl.bind("SUPER + SHIFT + CTRL + R", hl.dsp.exec_cmd("omarchy-reminder clear"), { description = "Clear reminders" })

-- Waybar-less information. The leading glyph is U+F43A (nerd-font calendar),
-- emitted as a \u escape so this source file stays ASCII.
hl.bind("SUPER + CTRL + ALT + T", hl.dsp.exec_cmd("notify-send -u low \"\u{F43A}    $(date +\"%A %H:%M  \u{00B7}  %d %B %Y  \u{00B7}  Week %V\")\""), { description = "Show time" })
hl.bind("SUPER + CTRL + ALT + B", hl.dsp.exec_cmd([[notify-send -u low "$(omarchy-battery-status)"]]), { description = "Show battery remaining" })
hl.bind("SUPER + CTRL + ALT + W", hl.dsp.exec_cmd([[notify-send -u low "$(omarchy-weather-status)"]]), { description = "Show weather" })

-- Control panels
hl.bind("SUPER + CTRL + A", hl.dsp.exec_cmd("omarchy-launch-audio"), { description = "Audio controls" })
hl.bind("SUPER + CTRL + B", hl.dsp.exec_cmd("omarchy-launch-bluetooth"), { description = "Bluetooth controls" })
hl.bind("SUPER + CTRL + W", hl.dsp.exec_cmd("omarchy-launch-wifi"), { description = "Wifi controls" })
hl.bind("SUPER + CTRL + T", hl.dsp.exec_cmd("uwsm-app -- kitty -e btop"), { description = "Activity" })

-- Dictation
hl.bind("SUPER + CTRL + X", hl.dsp.exec_cmd("voxtype record toggle"), { description = "Toggle dictation" })
hl.bind("F9", hl.dsp.exec_cmd("voxtype record start"), { description = "Start dictation (push-to-talk)" })
hl.bind("F9", hl.dsp.exec_cmd("voxtype record stop"), { release = true, description = "Stop dictation (push-to-talk)" })

-- Zoom. NOTE: with a Lua config `hyprctl keyword` takes the same key syntax as
-- the config; if these stop working, the equivalent is hl.get_config / hl.dispatch.
hl.bind("SUPER + CTRL + Z", hl.dsp.exec_cmd([[hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor -j | jq '.float + 1')]]), { description = "Zoom in" })
hl.bind("SUPER + CTRL + ALT + Z", hl.dsp.exec_cmd("hyprctl keyword cursor:zoom_factor 1"), { description = "Reset zoom" })

-- Lock system
hl.bind("SUPER + CTRL + L", hl.dsp.exec_cmd("lock"), { description = "Lock system" })
