-- Personal keyboard / touchpad (from input.conf).
hl.config({
  input = {
    kb_layout = "us",
    kb_options = "compose:ralt", -- overrides vendor's compose:caps
    repeat_rate = 40,
    repeat_delay = 600,
    numlock_by_default = true,
    touchpad = {
      natural_scroll = true,
      scroll_factor = 1,
    },
  },
})

-- Scroll nicely in the terminal. (This windowrule lives in input.conf, not
-- windowrules.conf, so it is kept here.)
hl.window_rule({ match = { class = "(Alacritty|kitty)" }, scroll_touchpad = 1.5 })
