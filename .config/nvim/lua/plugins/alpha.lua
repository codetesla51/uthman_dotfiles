-- Alpha dashboard — uses ~/.config/branding (100x49 art) as header
return {
  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    opts = function()
      local dashboard = require("alpha.themes.dashboard")
      -- read branding file
      local branding_path = vim.fn.expand("~/.config/branding")
      local header = {}
      if vim.fn.filereadable(branding_path) == 1 then
        local lines = vim.fn.readfile(branding_path)
        -- trim empty top/bottom, keep art
        while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end
        while #lines > 0 and lines[1]:match("^%s*$") do table.remove(lines, 1) end
        -- alpha expects a table of strings, one per line
        header = lines
      else
        header = {
          "  OLADELE USMAN",
          "  codetesla51 — Arch • Hyprland",
        }
      end
      dashboard.section.header.val = header
      dashboard.section.header.opts = { hl = "Title", position = "center" }
      dashboard.section.buttons.val = {
        dashboard.button("f", "  Find File", ":lua Snacks.dashboard.pick('files') <CR>"),
        dashboard.button("n", "  New File", ":ene <BAR> startinsert <CR>"),
        dashboard.button("r", "  Recent Files", ":lua Snacks.dashboard.pick('oldfiles') <CR>"),
        dashboard.button("g", "  Find Text", ":lua Snacks.dashboard.pick('live_grep') <CR>"),
        dashboard.button("c", "  Config", ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')}) <CR>"),
        dashboard.button("q", "  Quit", ":qa<CR>"),
      }
      dashboard.section.footer.val = ""
      dashboard.opts.opts.noautocmd = true
      return dashboard
    end,
    config = function(_, dashboard)
      require("alpha").setup(dashboard.opts)
    end,
  },
}
