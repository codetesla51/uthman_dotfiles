-- Personal look & feel (from looknfeel.conf). Colours come from the matugen
-- palette via theme.lua. hl.config() merges, so vendor/looknfeel.lua keys not
-- repeated here (e.g. blur.brightness/contrast, group.groupbar) are preserved.
local c = require("theme")

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 10,
    border_size = 1,
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
    blur = { enabled = true, size = 12, passes = 4, new_optimizations = true, xray = false, ignore_opacity = false, popups = true },
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

hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.1 } } })
hl.curve("smooth", { type = "bezier", points = { { 0.25, 1.0 }, { 0.5, 1.0 } } })
hl.curve("snappy", { type = "bezier", points = { { 0.4, 0.0 }, { 0.2, 1.0 } } })
hl.curve("bounce", { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1.0 } } })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "overshot", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "snappy", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "snappy" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 4, bezier = "smooth" })
hl.animation({ leaf = "border", enabled = true, speed = 8, bezier = "smooth" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 12, bezier = "smooth", style = "once" })
hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "smooth" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 4, bezier = "smooth" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "overshot", style = "slidefadevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "smooth", style = "slidevert" })
hl.animation({ leaf = "layers", enabled = true, speed = 4, bezier = "smooth", style = "slidefade" })
hl.animation({ leaf = "fadeLayers", enabled = true, speed = 3, bezier = "smooth" })

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
