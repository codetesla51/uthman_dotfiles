-- Hyprland palette for the Lua config (loaded by ~/.config/hypr/theme.lua).
-- Emitted by matugen from ~/.config/matugen/templates/hyprland-colors.lua.
-- Mirrors hyprland-colors.conf, but as a Lua table (Lua has no $variables).
return {
  background = "rgb({{ colors.background.default.hex_stripped }})",
  foreground = "rgb({{ colors.on_background.default.hex_stripped }})",
  primary    = "rgb({{ colors.primary.default.hex_stripped }})",
  secondary  = "rgb({{ colors.secondary.default.hex_stripped }})",
  tertiary   = "rgb({{ colors.tertiary.default.hex_stripped }})",
  error      = "rgb({{ colors.error.default.hex_stripped }})",
  surface    = "rgb({{ colors.surface.default.hex_stripped }})",
  outline    = "rgb({{ colors.outline.default.hex_stripped }})",
}
