-- Extra autostart processes (from autostart.conf).
--
-- Wrapped in the hyprland.start event: a top-level hl.exec_cmd() runs at config
-- parse time — including during `Hyprland --verify-config` and on every
-- `hyprctl reload` — which would re-spawn all of these. `exec-once` means
-- "once at startup", which is exactly the hyprland.start handler.
hl.on("hyprland.start", function()
  hl.exec_cmd("wl-paste --watch cliphist store")
  hl.exec_cmd("awww-daemon")
  hl.exec_cmd([[sh -c "sleep 0.5; awww img \"$(readlink ~/.config/theme/current/background)\" --transition-type none"]])
  hl.exec_cmd("~/.local/bin/matugen-cursor")
  hl.exec_cmd("quickshell -p ~/.config/quickshell")
  hl.exec_cmd("pkill -x swayosd-server")
  -- Wipe runaway capture overlays (slurp/hyprpicker) if a key ever sticks at login
  hl.exec_cmd("~/.config/hypr/scripts/picker-guard.sh")
end)
