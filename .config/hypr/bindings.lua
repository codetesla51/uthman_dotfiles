-- Personal keybindings (from bindings.conf).
--
-- Note on `unbind`: hyprlang is whitespace-sensitive, so the old file had to
-- spell some unbinds twice (`,X` and `, X`) to be sure they matched. Lua takes a
-- single canonical form ("MOD + KEY"), so those duplicates collapse — which
-- removes the bug class that caused the SUPER SHIFT S screenshot mix-up.
--
-- `unbind` removes binds registered earlier in this same config load, i.e. the
-- vendored defaults sourced before this file.

-- quickshell IPC helper: matches `sh -c "quickshell -p ~/.config/quickshell ipc call <arg>"`.
local function qs(arg)
  return 'sh -c "quickshell -p ~/.config/quickshell ipc call ' .. arg .. '"'
end

-- ── Application bindings ──────────────────────────────────────────────────
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("uwsm-app -- kitty"), { description = "Terminal" })
hl.bind("SUPER + SHIFT + F", hl.dsp.exec_cmd("uwsm-app -- thunar"), { description = "File manager" })
-- Firefox is the default xdg handler, so `xdg-open <url>` resolved to it anyway —
-- it just forced a URL on every launch. Bind firefox directly.
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("uwsm-app -- firefox"), { description = "Browser" })
hl.bind("SUPER + SHIFT + ALT + B", hl.dsp.exec_cmd("uwsm-app -- firefox --private-window"), { description = "Browser (private)" })

-- Killed vendor zoom-in (SUPER CTRL Z): key-repeat turns a slip into runaway
-- zoom. Reset survives in vendor defaults.
hl.unbind("SUPER + CTRL + Z")

hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("uwsm-app -- spotify"), { description = "Music" })
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("uwsm-app -- zed"), { description = "Editor" })
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd("uwsm-app -- obsidian -disable-gpu --enable-wayland-ime"), { description = "Obsidian" })

-- Web apps open chromeless (Chrome --app style) via ffapp: ffapp <name> <url> [title-regex]
hl.bind("SUPER + SHIFT + A", hl.dsp.exec_cmd("ffapp chatgpt https://chatgpt.com ChatGPT"), { description = "ChatGPT" })
hl.bind("SUPER + SHIFT + ALT + A", hl.dsp.exec_cmd("ffapp grok https://grok.com Grok"), { description = "Grok" })
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("ffapp heycal https://app.hey.com/calendar/weeks/ Calendar"), { description = "Calendar" })
hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd([[ffapp heymail https://app.hey.com "IMBOX|HEY"]]), { description = "Email" })
hl.bind("SUPER + SHIFT + Y", hl.dsp.exec_cmd("ffapp youtube https://youtube.com/ YouTube"), { description = "YouTube" })
hl.bind("SUPER + SHIFT + ALT + G", hl.dsp.exec_cmd("ffapp whatsapp https://web.whatsapp.com/ WhatsApp"), { description = "WhatsApp" })
hl.bind("SUPER + SHIFT + CTRL + G", hl.dsp.exec_cmd("ffapp messages https://messages.google.com/web/conversations Messages"), { description = "Google Messages" })
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd([[ffapp photos https://photos.google.com/ "Google Photos"]]), { description = "Google Photos" })
hl.bind("SUPER + SHIFT + X", hl.dsp.exec_cmd([[ffapp x https://x.com/ "\\bX\\b"]]), { description = "X" })
hl.bind("SUPER + SHIFT + ALT + X", hl.dsp.exec_cmd([[ffapp x https://x.com/compose/post "\\bX\\b"]]), { description = "X Post" })

-- Overwrite existing bindings (Omarchy Menu was on Super + Space).
hl.unbind("SUPER + ALT + SPACE")

-- Safety: Print must never launch an action. The keyboard/greeter can emit a
-- spurious Print while another key is held. Screenshot binds use explicit letter
-- keys; these unbinds also reject any Print combinations vendor defaults may add.
for _, mod in ipairs({ "", "SHIFT", "ALT", "SUPER", "SUPER + CTRL", "SUPER + SHIFT",
                       "SUPER + SHIFT + ALT", "SUPER + SHIFT + CTRL", "SUPER + SHIFT + CTRL + ALT" }) do
  hl.unbind(mod == "" and "PRINT" or (mod .. " + PRINT"))
end

-- Screenshots use letter keys only. FIX 2026-10-16: pretty must not sit on
-- SUPER SHIFT S — Hyprland runs *every* bind on a combo in creation order, so it
-- shared the key with utilities' `shot full` and both fired. Moved to W.
hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("shot ocr"), { description = "OCR from screenshot" })
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("shot pretty"), { description = "Pretty screenshot" })

-- ── Personal launcher / quickshell panels ─────────────────────────────────
-- bind + sh -c avoids an IPC race / description delay on a single press.
for _, key in ipairs({ "SUPER + SPACE", "SUPER + ALT + SPACE", "SUPER + H", "SUPER + U",
                       "SUPER + C", "SUPER + ALT + B" }) do
  hl.unbind(key)
end
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(qs("launcher toggle")))
hl.bind("SUPER + H", hl.dsp.exec_cmd(qs("wifi toggle")))
hl.bind("SUPER + U", hl.dsp.exec_cmd(qs("sysmon toggle")))
hl.bind("SUPER + ALT + C", hl.dsp.exec_cmd(qs("pomodoro toggle")))
hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd(qs("lyrics toggle")))
hl.bind("SUPER + ALT + B", hl.dsp.exec_cmd(qs("battery toggle")))

-- Personal emoji picker: rofi
hl.unbind("SUPER + CTRL + E")
hl.bind("SUPER + CTRL + E", hl.dsp.exec_cmd("uwsm-app -- ~/.config/rofi/emoji.sh"), { description = "Emoji picker" })

-- Personal clipboard manager: rofi + cliphist
hl.unbind("SUPER + CTRL + V")
hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd(qs("clipboard toggle")))

-- Sticky shelf — fire a pinned snippet straight to the clipboard from any app,
-- no panel. Slot 1 is the oldest sticky.
for i = 1, 9 do
  hl.bind("SUPER + ALT + " .. i, hl.dsp.exec_cmd(qs("sticky copy " .. i)))
end

-- Pin current clipboard to the sticky shelf, from any app, no window
hl.bind("SUPER + CTRL + P", hl.dsp.exec_cmd(qs("sticky pin")))

-- Personal keybindings browser: rofi
hl.unbind("SUPER + K")
hl.bind("SUPER + K", hl.dsp.exec_cmd(qs("keybinds toggle")))

-- PDF Viewer — SUPER ALT N (SUPER J reverted to focus down)
hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd(qs("pdfviewer toggle")))

-- Meetcap recorder — SUPER ALT M
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(qs("meetcap toggle")))

-- Wallshelf — Wallhaven browser. Unbind first: the vendor theme-background menu
-- sits on this exact combo.
hl.unbind("SUPER + CTRL + SPACE")
hl.bind("SUPER + CTRL + SPACE", hl.dsp.exec_cmd(qs("wallshelf toggle")))

-- Workspace manager — SUPER ALT O
hl.bind("SUPER + ALT + U", hl.dsp.exec_cmd(qs("plugins toggle")))
hl.bind("SUPER + ALT + O", hl.dsp.exec_cmd(qs("wsview toggle")))

-- ── Notifications ─────────────────────────────────────────────────────────
hl.bind("SUPER + COMMA", hl.dsp.exec_cmd(qs("notifications toggle")), { description = "Notification center" })
hl.bind("SUPER + SHIFT + COMMA", hl.dsp.exec_cmd(qs("notifications toggleDnd")), { description = "Toggle do not disturb" })
hl.unbind("SUPER + CTRL + COMMA")
hl.unbind("SUPER + ALT + COMMA")
hl.unbind("SUPER + SHIFT + ALT + COMMA")

hl.unbind("SUPER + E")
hl.unbind("SUPER + N")
hl.unbind("SUPER + ALT + V")
hl.bind("SUPER + E", hl.dsp.exec_cmd(qs("theme toggle")))
hl.bind("SUPER + ALT + G", hl.dsp.exec_cmd(qs("themeedit toggle")))
hl.bind("SUPER + N", hl.dsp.exec_cmd(qs("fastfetch toggle")))

-- ── fn-row media keys → quickshell OSD ────────────────────────────────────
-- Kill the duplicate Omarchy/swayosd binds (which used bindeld without a space
-- after the comma). Canonical Lua keys mean one unbind per combo now.
for _, key in ipairs({ "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute",
                       "XF86AudioMicMute", "XF86MonBrightnessUp", "XF86MonBrightnessDown" }) do
  hl.unbind(key)
end
for _, key in ipairs({ "SHIFT + XF86MonBrightnessUp", "SHIFT + XF86MonBrightnessDown",
                       "ALT + XF86AudioRaiseVolume", "ALT + XF86AudioLowerVolume",
                       "ALT + XF86MonBrightnessUp", "ALT + XF86MonBrightnessDown" }) do
  hl.unbind(key)
end

local function osd(keys, desc, arg)
  hl.bind(keys, hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell ipc call media " .. arg), { description = desc })
end
osd("XF86AudioRaiseVolume", "Volume up", "volup")
osd("XF86AudioLowerVolume", "Volume down", "voldown")
osd("XF86AudioMute", "Mute toggle", "volmute")
osd("XF86AudioMicMute", "Mic mute toggle", "micmute")
osd("XF86MonBrightnessUp", "Brightness up", "briup")
osd("XF86MonBrightnessDown", "Brightness down", "bridown")
osd("SHIFT + XF86MonBrightnessUp", "Brightness maximum", "brimax")
osd("SHIFT + XF86MonBrightnessDown", "Brightness minimum", "brimin")
osd("ALT + XF86AudioRaiseVolume", "Volume up precise", "volup")
osd("ALT + XF86AudioLowerVolume", "Volume down precise", "voldown")

-- ── Screen recording ──────────────────────────────────────────────────────
-- gpu-screen-recorder local toggle, saves to ~/Videos/Recordings
hl.bind("SUPER + R", hl.dsp.exec_cmd("uwsm-app -- record"), { description = "Screen record toggle" })

-- ── Power menu ────────────────────────────────────────────────────────────
-- Unbind both the vendor System menu (SUPER ESCAPE) and SUPER+L's lock; the two
-- ESCAPE spellings are kept because the old config treated them as distinct keys.
hl.unbind("SUPER + ESCAPE")
hl.unbind("SUPER + Escape")
hl.unbind("XF86PowerOff")
hl.bind("SUPER + Escape", hl.dsp.exec_cmd(qs("power toggle")))

-- ── Power — shutdown (SUPER+SHIFT+Q) ──────────────────────────────────────
-- Reboot bind removed: too easy to fat-finger. Use the power menu.
hl.bind("SUPER + SHIFT + Q", hl.dsp.exec_cmd("systemctl poweroff"), { description = "Shut down" })
hl.unbind("SUPER + SHIFT + R")

-- ── Logout (SUPER+SHIFT+L) ────────────────────────────────────────────────
-- Direct session end, no menu. uwsm owns the session, so use its stop verb
-- instead of hyprctl exit; it tears down the systemd user units cleanly.
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("uwsm stop"), { description = "Log out" })

-- ── Control Center — regular Hyprland window (SUPER ALT P) ────────────────
hl.unbind("SUPER + ALT + P")
hl.unbind("SUPER + ALT + T")
hl.unbind("SUPER + ALT + K")
hl.bind("SUPER + ALT + P", hl.dsp.exec_cmd(qs("controlcenter toggle")))
hl.bind("SUPER + ALT + T", hl.dsp.exec_cmd(qs("screentime toggle")))
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd(qs("phonebridge toggle")))
hl.bind("SUPER + ALT + E", hl.dsp.exec_cmd(qs("earbuds toggle")))
hl.bind("SUPER + ALT + D", hl.dsp.exec_cmd(qs("drives toggle")))
hl.bind("SUPER + ALT + Y", hl.dsp.exec_cmd(qs("watchcat toggle")))

-- ── Tiling layout — SUPER ALT Z cycles dwindle → master → scrolling ───────
-- vendor/bindings/tiling.lua binds `layout-toggle` on SUPER L, but this file
-- unbinds SUPER L for the lock screen, which left the script orphaned.
hl.bind("SUPER + ALT + Z", hl.dsp.exec_cmd("layout-toggle"), { description = "Cycle tiling layout" })

-- Full reload of quickshell + hyprland (kill+restart quickshell so every module re-reads)
hl.bind("SUPER + HOME", hl.dsp.exec_cmd([[sh -c "hyprctl reload >/dev/null 2>&1; pkill -x quickshell; sleep 0.3; setsid quickshell -p ~/.config/quickshell >/dev/null 2>&1 &"]]))

-- ── Bar side toggle — SUPER SHIFT SPACE leaves the middle island ──────────
hl.bind("SUPER + SHIFT + SPACE", hl.dsp.exec_cmd(qs("bar toggle")))

-- ── Island style — flips Dynamic Island against the trapezoid tab ────────
hl.bind("SUPER + ALT + SPACE", hl.dsp.exec_cmd(qs("bar toggleIsland")), { description = "Island style" })

-- ── Package Manager — Hyprland window (SUPER+I) ──────────────────────────
hl.unbind("SUPER + I")
hl.bind("SUPER + I", hl.dsp.exec_cmd(qs("pkgman toggle")))

-- ── Lock screen — hyprlock (SUPER+L) ─────────────────────────────────────
hl.unbind("SUPER + L")
hl.bind("SUPER + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"), { description = "Lock screen" })
