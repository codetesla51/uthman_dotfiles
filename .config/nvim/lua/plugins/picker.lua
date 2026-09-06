-- Picker — file picker with branding header (reads ~/.config/branding)
local branding_path = vim.fn.expand("~/.config/branding")
local branding_lines = {}
if vim.fn.filereadable(branding_path) == 1 then
  branding_lines = vim.fn.readfile(branding_path)
  while #branding_lines > 0 and branding_lines[#branding_lines]:match("^%s*$") do table.remove(branding_lines) end
  while #branding_lines > 0 and branding_lines[1]:match("^%s*$") do table.remove(branding_lines, 1) end
  if #branding_lines > 8 then
    local trimmed = {}
    for i = 1, 8 do table.insert(trimmed, branding_lines[i]) end
    branding_lines = trimmed
  end
end
local first_line = ""
if #branding_lines > 0 then
  first_line = branding_lines[1]:gsub("^%s+", ""):gsub("%s+$", "")
  if #first_line > 40 then first_line = first_line:sub(1, 40) end
end
local has_branding = #branding_lines > 0

return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        prompt = has_branding and "  " .. first_line .. " ▸ " or " ",
        layouts = {
          branding = {
            layout = {
              box = "vertical",
              border = "rounded",
              width = 0.8,
              height = 0.8,
              {
                win = "input",
                height = 1,
                border = "rounded",
                title = has_branding and "  " .. first_line .. "  " or " {title} ",
                title_pos = "center",
              },
              {
                box = "horizontal",
                {
                  win = "list",
                  border = "none",
                },
                {
                  win = "preview",
                  width = 0.6,
                  border = "rounded",
                },
              },
            },
          },
        },
        sources = {
          files = { layout = { preset = "branding" } },
          grep = { layout = { preset = "branding" } },
          oldfiles = { layout = { preset = "branding" } },
        },
      },
    },
  },
}
