-- Vendored Hyprland autostart (sanitized Omarchy copy).
--
-- IMPORTANT: this is wrapped in the `hyprland.start` event rather than run at
-- file scope. A top-level hl.exec_cmd() runs at *config parse* time — including
-- during `Hyprland --verify-config` and on every `hyprctl reload` — which would
-- re-spawn these processes. `exec-once` semantics are "run once at startup",
-- which is exactly what the hyprland.start handler gives.
hl.on("hyprland.start", function()
  hl.exec_cmd("uwsm-app -- hypridle")
  hl.exec_cmd("uwsm-app -- fcitx5 --disable notificationitem")
  hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

  -- Slow app launch fix -- set systemd vars
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")
end)
