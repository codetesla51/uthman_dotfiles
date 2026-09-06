-- Dashboard — uses ~/.config/branding as startup ASCII (synced with screensaver/logo)
-- Reads the branding file directly, no chafa needed, falls back to Hollow Knight mask
local branding = vim.fn.expand("~/.config/branding")
local header = nil

if vim.fn.filereadable(branding) == 1 then
  local lines = vim.fn.readfile(branding)
  -- trim trailing empty lines for cleaner dashboard
  while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end
  while #lines > 0 and lines[1]:match("^%s*$") do table.remove(lines, 1) end
  if #lines > 0 then
    header = table.concat(lines, "\n")
  end
end

-- fallback to Hollow Knight mask if branding missing
if not header then
  local logo = "/usr/share/sddm/themes/elarun-custom/images/logo-white.png"
  if vim.fn.filereadable(logo) == 0 then
    logo = vim.fn.expand("~/dotfiles/sddm/elarun-custom/images/logo-white.png")
  end
  header = [[
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
  end
end

local sections = {
  { section = "keys", gap = 1, padding = 1 },
  { section = "startup" },
}

-- if we have a branding header, use it directly; if we fell back to chafa, use terminal section
if not header and vim.fn.executable("chafa") == 1 then
  local logo = "/usr/share/sddm/themes/elarun-custom/images/logo-white.png"
  if vim.fn.filereadable(logo) == 0 then logo = vim.fn.expand("~/dotfiles/sddm/elarun-custom/images/logo-white.png") end
  if vim.fn.filereadable(logo) == 1 then
    header = nil
    table.insert(sections, 1, {
      section = "terminal",
      cmd = "chafa -c none -f symbols -s 56x22 " .. vim.fn.shellescape(logo),
      height = 23,
      padding = 1,
    })
  end
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
