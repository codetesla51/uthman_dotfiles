-- Picker — file picker with branding header (direct text)
local branding_first = "▒██             ▒██░"
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        prompt = "  " .. branding_first .. " ▸ ",
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
                title = "  " .. branding_first .. "  ",
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
