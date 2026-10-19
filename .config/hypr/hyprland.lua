-- Hyprland configuration — Lua entry point.
--
-- The presence of this file at *startup* selects the Lua config; hyprland.conf
-- is then ignored entirely. It is checked once at startup, so deleting it and
-- running `hyprctl reload` does NOT fall back to hyprland.conf — a full Hyprland
-- restart is required. (Rollback: remove ~/.config/hypr/hyprland.lua, restart.)
--
-- This mirrors the old hyprland.conf `source` order exactly. `require` caches by
-- name, so each module runs once. hl.config() merges across calls, so vendor
-- defaults and personal overrides layer correctly.

-- TEMP: full logs to stdout (→ journal via uwsm) so a failed login is captured
-- instead of the runtime-dir log being wiped on teardown. Remove after debugging.
hl.config({ debug = { enable_stdout_logs = true } })

-- ── Theme palette (was: source = ~/.config/theme/current/colors.conf) ─────
-- matugen emits the palette as a Lua table; theme.lua loads it (with a
-- hardcoded fallback). Loaded first so its cached table is ready for consumers.
require("theme")

-- ── Vendored defaults (standalone; sanitized Omarchy copies) ──────────────
require("vendor.autostart")
require("vendor.bindings.media")
require("vendor.bindings.clipboard")
require("vendor.bindings.tiling")
require("vendor.bindings.utilities")
require("vendor.envs")
require("vendor.looknfeel")
require("vendor.input")
require("vendor.windows")

-- ── Theme-specific rules (was: source = .../theme/current/hyprland.conf) ──
-- matugen may drop a per-theme Lua file here; missing is fine.
pcall(dofile, os.getenv("HOME") .. "/.config/theme/current/hyprland.lua")

-- ── Personal overrides ────────────────────────────────────────────────────
require("envs")
require("monitors")
require("monitors_override") -- quickshell Monitors panel target (last match wins)
require("input")
require("bindings")
require("looknfeel")
require("autostart")
require("windowrules")
