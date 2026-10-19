-- Vendored Hyprland window-rule defaults (sanitized Omarchy copy).

-- Stop apps from maximizing themselves.
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- Tag all windows for default opacity (apps can opt out with a -default-opacity tag).
hl.window_rule({ match = { class = ".*" }, tag = "+default-opacity" })

-- Fix some dragging issues with XWayland.
hl.window_rule({
  match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
  no_focus = true,
})

-- Apply the default opacity now that apps have had a chance to opt out.
hl.window_rule({ match = { tag = "default-opacity" }, opacity = "0.985 0.96" })
