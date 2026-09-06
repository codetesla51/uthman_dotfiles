-- Wallpaper-synced theme (matugen-generated full colorscheme).
-- The template `~/.config/matugen/templates/neovim.lua` regenerates
-- `~/.config/theme/current/neovim.lua` on every wallpaper change, and that
-- file is itself a LazyVim plugin spec, so it is loaded directly.
-- Falls back to LazyVim's default (tokyonight) before the first regen.
local theme = vim.fn.expand("~/.config/theme/current/neovim.lua")
if vim.fn.filereadable(theme) == 1 then
  return dofile(theme)
end
return {}
