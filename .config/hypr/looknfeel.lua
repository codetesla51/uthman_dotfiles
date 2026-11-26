-- Personal look & feel (from looknfeel.conf). Colours come from the matugen
-- palette via theme.lua. hl.config() merges, so vendor/looknfeel.lua keys not
-- repeated here (e.g. blur.brightness/contrast, group.groupbar) are preserved.
local c = require("theme")

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 10,
    border_size = 0,
    col = {
      active_border = { colors = { c.primary, c.secondary }, angle = 45 },
      inactive_border = c.outline,
    },
    layout = "dwindle",
    resize_on_border = true,
  },
  decoration = {
    rounding = 12,
    rounding_power = 2.4,
    blur = { enabled = true, size = 12, passes = 4, new_optimizations = false, xray = false, ignore_opacity = true, popups = true },
    shadow = { enabled = true, range = 28, render_power = 3, color = "rgba(00000066)", color_inactive = "rgba(00000025)" },
    active_opacity = 0.95,
    inactive_opacity = 0.86,
    fullscreen_opacity = 1.0,
    dim_inactive = true,
    dim_strength = 0.08,
  },
  dwindle = {
    preserve_split = true,
    smart_split = true,
    smart_resizing = true,
  },
  master = {
    new_status = "slave",
  },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    animate_manual_resizes = true,
    animate_mouse_windowdragging = true,
    focus_on_activate = true,
    mouse_move_enables_dpms = true,
    key_press_enables_dpms = true,
  },
})

-- ── Animations ────────────────────────────────────────────────────────────
hl.config({ animations = { enabled = true } })

-- Same motion language as the quickshell Bloom/Magnet preset: a gentle
-- 1.12 overshoot on entrance, ease-out on exit, and no hard stops.
hl.curve("magnet", { type = "bezier", points = { { 0.33, 1.12 }, { 0.58, 1.0 } } })
hl.curve("magnetSoft", { type = "bezier", points = { { 0.34, 1.06 }, { 0.64, 1.0 } } })
hl.curve("easeOut", { type = "bezier", points = { { 0.32, 0.72 }, { 0.0, 1.0 } } })
hl.curve("apple", { type = "bezier", points = { { 0.22, 1.0 }, { 0.36, 1.0 } } })

-- Windows pop in from 90% with a real overshoot, then settle quickly. Exits
-- collapse from 94% on a faster ease-out so closing never feels sluggish.
hl.animation({ leaf = "windows", enabled = true, speed = 2.8, bezier = "magnetSoft", style = "popin 92%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.0, bezier = "magnet", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.0, bezier = "easeOut", style = "popin 94%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 1.9, bezier = "magnetSoft" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.8, bezier = "apple" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.2, bezier = "easeOut" })
hl.animation({ leaf = "fade", enabled = true, speed = 1.7, bezier = "magnetSoft" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.0, bezier = "magnetSoft" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 1.8, bezier = "magnetSoft" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 2.0, bezier = "magnetSoft" })
hl.animation({ leaf = "border", enabled = true, speed = 2.8, bezier = "magnetSoft" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 5, bezier = "magnetSoft", style = "once" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.7, bezier = "magnet", style = "slidefadevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.4, bezier = "magnetSoft", style = "slidefadevert" })
hl.animation({ leaf = "layers", enabled = true, speed = 2.2, bezier = "magnetSoft" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 1.9, bezier = "magnetSoft", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.2, bezier = "easeOut", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.7, bezier = "magnetSoft" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.1, bezier = "easeOut" })

-- ── Frosted glass for quickshell surfaces ─────────────────────────────────
-- (island, panels, toasts). The old file spelled these as ~26 separate
-- layerrule lines; each pair here collapses to one rule with two effects.
local frosted = {
  "qs-bar", "qs-launcher", "qs-passprompt", "qs-nowplaying", "qs-notes",
  "qs-wifi", "qs-notify", "qs-toasts", "qs-lyrics", "qs-theme",
  "qs-osd", "quickshell",
}
for _, ns in ipairs(frosted) do
  hl.layer_rule({ match = { namespace = ns }, blur = true, ignore_alpha = 0.15 })
end

-- Hornet pet — only the PNG is visible: no window bg, blur or shadow.
hl.layer_rule({ match = { namespace = "qs-pet" }, blur = false, ignore_alpha = 0.01, no_anim = true, xray = true })
