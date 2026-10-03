# TODO

## ~~PhoneBridge~~ — done

Connected and verified 2026-10-02. Probe is 9/9 PASS.

The phone's wifi IP is **192.168.165.198:5555** (itel A663LC). Earlier it
looked like "the router" in a ping scan — it was the phone, on the same
subnet as the laptop all along. Only `init.sh` had never been re-run against
it, so the config still carried the stale `192.168.98.30` from an old network.

Kept working after the timeout fix:

- `~/phonebridge/phonebridge` — every adb call bounded (connect 8s, shell
  30s, push/pull 300s); `TimeoutExpired` → exit 124 so existing error paths
  handle it
- `init.sh:31` — `timeout 8 adb connect`
- `PhoneBridge.qml` — 15s `discoveryWatchdog` kills a hung connect/list and
  clears `busy`, which previously latched `true` and blocked all refreshes

### Gotcha

`init.sh` writes `device`/`target` from whatever adb sees first. Run it while
cabled and it records the USB serial (`10665403B6010710`), which dies on
unplug. Re-run it **unplugged** to keep the wifi target.

## Monitor scale — needs a logout to settle

`.config/hypr/monitors.conf` says scale `1` (1920x1080, integer 1:1) with
`GDK_SCALE,1` to match.

Live session still reports `1.2` — leftover runtime override from testing,
not a config bug. Reboot or re-login to pick up `1.0`.

Note: `1.15` was never going to work. Hyprland only accepts scales that divide
1920x1080 into whole pixels; `1920/1.15 = 1669.57`, so it silently snapped to
`1.2`. Reachable scales on this panel: **1.0, 1.2, 1.25, 1.5, 1.6, 2.0**.
`MonitorSettings.qml` already restricts its picker to exactly that set.