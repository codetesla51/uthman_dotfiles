-- Personal window rules (from windowrules.conf).
--
-- The bulk is a (title -> size) table for quickshell panels, which the old file
-- spelled out twice — once for class `quickshell` and once for `org.quickshell`.
-- The inner loop reproduces that. hl.window_rule() is order-independent here
-- because every rule matches a distinct class/title pair.

local panels = {
  { "System Monitor", 920, 640 },
  { "Monitors", 460, 620 },
  { "PhoneBridge", 460, 520 },
  { "Meetcap", 400, 500 },
  { "ThemeEditor", 460, 740 },
  { "Earbuds", 380, 420 },
  { "Bluetooth", 440, 560 },
  { "WhatsApp", 640, 720 },
  { "Hardware Health", 600, 640 },
  { "Dictionary", 560, 500 },
  { "WatchCat", 920, 440 },
  { "Control Center", 980, 720 },
  { "PDF Library", 960, 640 },
  { "Wallshelf", 980, 700 },
  { "Pomodoro", 400, 540 },
  { "GitHubDash", 760, 560 },
  { "QuickNotes", 460, 600 },
  { "Clipboard", 660, 730 },
  { "Grap", 600, 470 },
  { "Clock", 360, 408 },
}

for _, p in ipairs(panels) do
  local title, w, h = p[1], p[2], p[3]
  for _, class in ipairs({ "quickshell", "org.quickshell" }) do
    hl.window_rule({ match = { class = class, title = title }, float = true, center = true, size = { w, h } })
  end
end

-- Package Manager — the `quickshell` class deliberately lacks the float rule.
hl.window_rule({ match = { class = "quickshell", title = "Package Manager" }, center = true, size = { 980, 640 } })
hl.window_rule({ match = { class = "org.quickshell", title = "Package Manager" }, float = true, center = true, size = { 980, 640 } })

-- uthmanHabit — habit tracker, only the org.quickshell class, small window.
hl.window_rule({ match = { class = "org.quickshell", title = "uthmanHabit" }, float = true, center = true, size = { 700, 660 } })

-- Screensaver — kitty fullscreen, no decorations.
hl.window_rule({ match = { class = "org.screensaver" }, float = true, fullscreen = true })

-- Zathura — glass float. The opacity rule's 3rd value is the fullscreen one,
-- which keeps the glass when it covers the screen (deco fullscreen_opacity=1.0
-- would otherwise win).
hl.window_rule({
  match = { class = "^(org.pwmt.zathura)$" },
  float = true,
  center = true,
  size = { 1100, 750 },
  border_size = 0,
  opacity = "0.78 0.70 0.78",
})

-- mpv — centered floating popup.
hl.window_rule({ match = { class = "^(mpv)$" }, float = true, center = true, size = { 960, 540 } })

-- filemanager picker — centered floating popup, same treatment as mpv.
hl.window_rule({ match = { class = "^(com.codetesla51.filemanager.picker)$" }, float = true, center = true, size = { 960, 540 } })

-- Zen — no Hyprland border (glass chrome draws its own edges).
hl.window_rule({ match = { class = "zen" }, border_size = 0 })

-- Loupe — small centered image popup instead of a full window.
hl.window_rule({ match = { class = "org.gnome.Loupe" }, float = true, center = true, size = { 880, 680 } })

-- Zed — translucent editor. gen-zed-theme sets editor backgrounds to #rrggbbaa
-- and background.appearance=transparent, so the surface is see-through and the
-- global decoration.blur supplies the blur behind it. Without `opaque off`
-- Hyprland treats the window as opaque and skips the blur. (`blur`/`ignore_alpha`
-- are layer-rule-only and throw "invalid field type" as window rules.)
hl.window_rule({ match = { class = "dev.zed.Zed" }, opaque = false })
hl.window_rule({ match = { class = "zed" }, opaque = false })
