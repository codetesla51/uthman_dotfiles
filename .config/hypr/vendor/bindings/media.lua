-- Vendored multimedia keys (sanitized Omarchy copy).
--
-- Flag legend (old hyprlang bind flags):
--   bindeld -> repeating + locked + description  => { repeating = true, locked = true, description = ... }
--   bindld  -> locked + description              => { locked = true, description = ... }
--
-- Many of these commands (omarchy-swayosd-client, omarchy-audio-input-mute,
-- omarchy-brightness-display) are not installed in a standalone setup. Personal
-- bindings.lua unbinds the volume/brightness keys and rebinds them to quickshell;
-- the keyboard-backlight / touchpad / playerctl / vol binds stay live.

local function rep(keys, desc, cmd)
  hl.bind(keys, hl.dsp.exec_cmd(cmd), { repeating = true, locked = true, description = desc })
end
local function lk(keys, desc, cmd)
  hl.bind(keys, hl.dsp.exec_cmd(cmd), { locked = true, description = desc })
end

rep("XF86AudioRaiseVolume", "Volume up", "omarchy-swayosd-client --output-volume raise")
rep("XF86AudioLowerVolume", "Volume down", "omarchy-swayosd-client --output-volume lower")
rep("XF86AudioMute", "Mute", "omarchy-swayosd-client --output-volume mute-toggle")
rep("XF86AudioMicMute", "Mute microphone", "omarchy-audio-input-mute")
rep("XF86MonBrightnessUp", "Brightness up", "omarchy-brightness-display +5%")
rep("XF86MonBrightnessDown", "Brightness down", "omarchy-brightness-display 5%-")
rep("SHIFT + XF86MonBrightnessUp", "Brightness maximum", "omarchy-brightness-display 100%")
rep("SHIFT + XF86MonBrightnessDown", "Brightness minimum", "omarchy-brightness-display 1%")
rep("XF86KbdBrightnessUp", "Keyboard brightness up", "bright kbd-up")
rep("XF86KbdBrightnessDown", "Keyboard brightness down", "bright kbd-down")
lk("XF86KbdLightOnOff", "Keyboard backlight cycle", "bright kbd-cycle")
lk("XF86TouchpadToggle", "Toggle touchpad", "touchpad toggle")
lk("XF86TouchpadOn", "Enable touchpad", "touchpad on")
lk("XF86TouchpadOff", "Disable touchpad", "touchpad off")

-- Precise 1% multimedia adjustments with the Alt modifier
rep("ALT + XF86AudioRaiseVolume", "Volume up precise", "omarchy-swayosd-client --output-volume +1")
rep("ALT + XF86AudioLowerVolume", "Volume down precise", "omarchy-swayosd-client --output-volume -1")
rep("ALT + XF86MonBrightnessUp", "Brightness up precise", "omarchy-brightness-display +1%")
rep("ALT + XF86MonBrightnessDown", "Brightness down precise", "omarchy-brightness-display 1%-")

-- Requires playerctl
lk("XF86AudioNext", "Next track", "playerctl next")
lk("XF86AudioPause", "Pause", "playerctl play-pause")
lk("XF86AudioPlay", "Play", "playerctl play-pause")
lk("XF86AudioPrev", "Previous track", "playerctl previous")

-- Switch audio output with Super + Mute
lk("SUPER + XF86AudioMute", "Switch audio output", "vol cycle-sink")
