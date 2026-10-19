-- Theme palette.
--
-- The old hyprland.conf did `source = ~/.config/theme/current/colors.conf`, which
-- defined hyprlang $variables ($primary, $secondary, ...). Lua has no $variables,
-- so matugen now emits the same palette as a Lua table
-- (matugen template `hyprland-colors.lua` -> ~/.config/theme/current/colors.lua)
-- and this module loads it. Consumer: looknfeel.lua (borders, group colours).
--
-- Returns a table of hyprland colour strings, e.g. { primary = "rgb(b8c8dd)" }.

local path = os.getenv("HOME") .. "/.config/theme/current/colors.lua"
local ok, palette = pcall(dofile, path)
if ok and type(palette) == "table" then
  return palette
end

-- Fallback so a missing/not-yet-generated palette can never break the config.
return {
  background = "rgb(131315)",
  foreground = "rgb(e4e2e3)",
  primary    = "rgb(b8c8dd)",
  secondary  = "rgb(c2c7d0)",
  tertiary   = "rgb(dfc29e)",
  error      = "rgb(ffb4ab)",
  surface    = "rgb(131315)",
  outline    = "rgb(94969c)",
}
