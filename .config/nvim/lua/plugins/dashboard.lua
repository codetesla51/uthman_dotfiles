-- Dashboard logo: the real Hollow Knight mask (same file as the SDDM
-- login logo), rendered live with chafa on every start. Falls back to
-- the pre-rendered ASCII below when chafa or the logo is missing.
-- Snacks centers the header; the terminal section is sized to chafa's
-- exact output (56x22) so nothing wraps or clobbers.
local logo = "/usr/share/sddm/themes/elarun-custom/images/logo-white.png"
if vim.fn.filereadable(logo) == 0 then
  logo = vim.fn.expand("~/dotfiles/sddm/elarun-custom/images/logo-white.png")
end

local sections = {
  { section = "keys", gap = 1, padding = 1 },
  { section = "startup" },
}
local header = [[
                  ┈      ╴
                ╺ ▕▏    ▝
               ╱  ╹      ╻
              ╱   ▎      ▝   ╷
             ╻   ▕       ▕▏   ╴
                 ▕       ▕▎   ┕
            ╽    ▕▏      ▕     ╻
            ▎     ╷      ╱     ▝
           ▕       ╸           ▕▏
           ▐         ╺          ▎
           ▕                   ▕▏
            ▎                  ┌
            ╹                  ┛
             ╻ ▗▄▂        ▃▅▖ ╱
                ▜█▇▖    ▗██▛ ╱
                 ▀██▎  ▕██▀
                  ╴▔    ▔╶
]]

if vim.fn.executable("chafa") == 1 and vim.fn.filereadable(logo) == 1 then
  header = nil
  table.insert(sections, 1, {
    section = "terminal",
    cmd = "chafa -c none -f symbols -s 56x22 " .. vim.fn.shellescape(logo),
    height = 23,
    padding = 1,
  })
end

return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = { header = header },
        sections = sections,
      },
    },
  },
}
