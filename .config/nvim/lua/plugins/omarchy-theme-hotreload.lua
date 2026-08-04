return {
	{
		name = "theme-hotreload",
		dir = vim.fn.stdpath("config"),
		lazy = false,
		priority = 1000,
		config = function()
			local function apply_theme()
				package.loaded["plugins.theme"] = nil

				local ok, theme_spec = pcall(require, "plugins.theme")
				if not ok then
					return
				end

				-- Clear all highlight groups before applying new theme
				vim.cmd("highlight clear")
				if vim.fn.exists("syntax_on") then
					vim.cmd("syntax reset")
				end
				vim.o.background = "dark"

				-- Unload theme plugin modules to force full reload
				local theme_plugin_name = nil
				for _, spec in ipairs(theme_spec) do
					if spec[1] and spec[1] ~= "LazyVim/LazyVim" then
						theme_plugin_name = spec.name or spec[1]
						break
					end
				end
				if theme_plugin_name then
					local plugin = require("lazy.core.config").plugins[theme_plugin_name]
					if plugin then
						local plugin_dir = plugin.dir .. "/lua"
						require("lazy.core.util").walkmods(plugin_dir, function(modname)
							package.loaded[modname] = nil
							package.preload[modname] = nil
						end)
					end
				end

				-- Find and apply the new colorscheme
				for _, spec in ipairs(theme_spec) do
					if spec[1] == "LazyVim/LazyVim" and spec.opts and spec.opts.colorscheme then
						local colorscheme = spec.opts.colorscheme
						if type(colorscheme) == "function" then
							colorscheme()
						else
							require("lazy.core.loader").colorscheme(colorscheme)
							pcall(vim.cmd.colorscheme, colorscheme)
						end
						break
					end
				end

				-- Reload transparency settings
				local transparency_file = vim.fn.stdpath("config") .. "/plugin/after/transparency.lua"
				if vim.fn.filereadable(transparency_file) == 1 then
					vim.cmd.source(transparency_file)
				end

				-- Trigger UI updates for various plugins
				vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
				vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
				vim.cmd("redraw!")
			end

			vim.api.nvim_create_autocmd("User", {
				pattern = "LazyReload",
				callback = function()
					vim.schedule(apply_theme)
				end,
			})

			vim.api.nvim_create_user_command("OmarchyReloadTheme", function()
				vim.schedule(apply_theme)
			end, {})
		end,
	},
}
