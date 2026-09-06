-- Alpha dashboard — small name first, fallback if snacks fails
return {
  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    opts = function()
      local dashboard = require("alpha.themes.dashboard")
      dashboard.section.header.val = {
        "  OLADELE USMAN",
        "  codetesla51 — Arch • Hyprland",
      }
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
