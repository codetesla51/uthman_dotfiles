-- Vendored Hyprland input defaults (sanitized Omarchy copy).
-- Personal input.lua (loaded after this file) overrides kb_options and touchpad.
hl.config({
  input = {
    kb_layout = "us",
    kb_variant = "",
    kb_model = "",
    kb_options = "compose:caps", -- personal override sets compose:ralt
    kb_rules = "",
    follow_mouse = 1,
    sensitivity = 0, -- -1.0 .. 1.0, 0 means no modification
    touchpad = {
      natural_scroll = false,
    },
  },
  misc = {
    key_press_enables_dpms = true, -- key press will trigger wake
    mouse_move_enables_dpms = true, -- mouse move will trigger wake
  },
})
