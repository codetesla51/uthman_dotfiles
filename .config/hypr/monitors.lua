-- Monitor setup (from monitors.conf).

-- GDK_SCALE must match the monitor scale below, or GTK apps double-scale.
hl.env("GDK_SCALE", "1")

-- Straight 1x setup for a low-resolution display (1080p).
hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "auto", scale = 1 })
