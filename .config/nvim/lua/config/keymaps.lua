-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- jk exits insert mode (fast, no Esc reach)
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })
