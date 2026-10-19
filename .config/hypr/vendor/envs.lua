-- Vendored Hyprland environment defaults (sanitized Omarchy copy).
--
-- The original wrapped two `source =` lines in `# hyprlang noerror true`:
--     source = ~/.config/theme/current/gum.env.conf
--     source = ~/.config/omarchy/current/theme/gum.env.conf
-- Neither file exists here, and hyprlang's `noerror` has no Lua equivalent
-- (dofile() on a missing path raises), so they are intentionally omitted.

-- Cursor size. Personal envs.lua overrides these to 20 (loaded after this file).
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force all apps to use Wayland
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Better support for screen sharing (Google Meet, Discord, etc)
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.config({ xwayland = { force_zero_scaling = true } })

-- Use an XCompose file. NOTE: kept as a literal "~/.XCompose" to match the old
-- hyprlang behaviour (Hyprland expanded $HOME but not ~), even though the file
-- does not currently exist.
hl.env("XCOMPOSEFILE", "~/.XCompose")

-- Don't show the update notice on first launch
hl.config({ ecosystem = { no_update_news = true } })
