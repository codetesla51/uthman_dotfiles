-- Dashboard — small text, name first
return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = [[
  OLADELE USMAN
  codetesla51 — Arch • Hyprland
]],
        },
        sections = {
          { section = "keys", gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
    },
  },
}
