-- Personal environment overrides (from envs.conf).
local HOME = os.getenv("HOME")

-- Put ~/.local/bin on PATH for everything Hyprland launches. Binds call `shot`,
-- `record`, `layout-toggle`, `ffapp`, ... by bare name, so this must come first.
hl.env("PATH", HOME .. "/.local/bin:" .. os.getenv("PATH"))
hl.env("SUDO_ASKPASS", HOME .. "/.local/bin/askpass")

-- Matugen-generated pointer; the theme script keeps its colour in sync.
-- Overrides the 24 set in vendor/envs.lua.
hl.env("HYPRCURSOR_THEME", "Matugen-Cursor")
hl.env("HYPRCURSOR_SIZE", "20")
hl.env("XCURSOR_THEME", "Matugen-Cursor")
hl.env("XCURSOR_SIZE", "20")
