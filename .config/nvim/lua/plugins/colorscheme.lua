-- Tokyonight kept as fallback (LazyVim default) for fresh clones before
-- the first matugen run. The active scheme comes from matugen.lua.
return {
  {
    "folke/tokyonight.nvim",
    opts = {
      style = "night",
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
  },
}
