return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        vim.cmd("highlight clear")
        if vim.fn.exists("syntax_on") then
          vim.cmd("syntax reset")
        end
        vim.o.background = "dark"

        local hl = vim.api.nvim_set_hl

        -- ── Palette ───────────────────────────────────────────────────
        --
        --  Each color owns exactly one syntactic role.
        --  Nothing shares a color — that's what makes code readable.
        --
        local c = {
          -- Backgrounds
          bg        = "#000000", -- true black
          bg_subtle = "#0a0e14", -- panels, sidebars
          bg_raised = "#0d1117", -- floats, popups
          bg_select = "#111a24", -- visual, cursorline

          -- Foregrounds
          fg        = "#cdd9e5", -- base text — slightly cool white
          fg_dim    = "#768a9e", -- punctuation, operators
          fg_muted  = "#3a4f63", -- line numbers, whitespace

          -- Blues & cyans — the accent family
          cyan      = "#39d5c7", -- functions & methods      (bright, eye-catching)
          blue      = "#5ab0f5", -- keywords                 (clear, authoritative)
          blue_soft = "#88b4d4", -- types & classes          (distinct but calmer)
          sky       = "#a8d8f0", -- strings                  (light, readable)
          teal      = "#2eb8a0", -- numbers & booleans       (saturated teal)
          steel     = "#4a8fa8", -- builtins, special vars   (deeper blue)

          -- Supporting accents
          lavender  = "#9ab8f0", -- attributes, decorators
          gold      = "#d4b896", -- imports, macros          (warm contrast)
          red       = "#f87171", -- errors & exceptions
          orange    = "#f0a070", -- warnings

          -- UI chrome
          border    = "#1a2a3a",
          hint      = "#1e3040",
        }

        -- ── Base ──────────────────────────────────────────────────────
        hl(0, "Normal", { fg = c.fg, bg = c.bg })
        hl(0, "NormalFloat", { fg = c.fg, bg = c.bg_raised })
        hl(0, "NormalNC", { fg = c.fg_dim, bg = c.bg })
        hl(0, "EndOfBuffer", { fg = c.bg })

        -- ── Syntax ────────────────────────────────────────────────────
        hl(0, "Comment", { fg = c.fg_muted, italic = true })
        hl(0, "Constant", { fg = c.sky })
        hl(0, "String", { fg = c.sky })
        hl(0, "Character", { fg = c.sky })
        hl(0, "Number", { fg = c.teal })
        hl(0, "Float", { fg = c.teal })
        hl(0, "Boolean", { fg = c.teal, bold = true })

        hl(0, "Identifier", { fg = c.fg })
        hl(0, "Function", { fg = c.cyan, bold = true })

        hl(0, "Statement", { fg = c.blue })
        hl(0, "Conditional", { fg = c.blue, bold = true })
        hl(0, "Repeat", { fg = c.blue, bold = true })
        hl(0, "Label", { fg = c.blue })
        hl(0, "Keyword", { fg = c.blue, bold = true })
        hl(0, "Exception", { fg = c.red, bold = true })
        hl(0, "Operator", { fg = c.fg_dim })

        hl(0, "PreProc", { fg = c.gold })
        hl(0, "Include", { fg = c.gold })
        hl(0, "Define", { fg = c.gold })
        hl(0, "Macro", { fg = c.gold })

        hl(0, "Type", { fg = c.blue_soft, bold = true })
        hl(0, "StorageClass", { fg = c.blue })
        hl(0, "Structure", { fg = c.blue_soft })
        hl(0, "Typedef", { fg = c.blue_soft })

        hl(0, "Special", { fg = c.steel })
        hl(0, "SpecialChar", { fg = c.steel })
        hl(0, "Tag", { fg = c.blue })
        hl(0, "Delimiter", { fg = c.fg_dim })
        hl(0, "SpecialComment", { fg = c.steel, italic = true })

        hl(0, "Error", { fg = c.red, bold = true })
        hl(0, "Todo", { fg = c.bg, bg = c.cyan, bold = true })
        hl(0, "Underlined", { fg = c.sky, underline = true })

        -- ── Treesitter ────────────────────────────────────────────────
        hl(0, "@variable", { fg = c.fg })
        hl(0, "@variable.builtin", { fg = c.steel, italic = true })
        hl(0, "@variable.parameter", { fg = c.fg_dim })
        hl(0, "@variable.member", { fg = c.fg })

        hl(0, "@constant", { fg = c.sky })
        hl(0, "@constant.builtin", { fg = c.teal, bold = true })
        hl(0, "@constant.macro", { fg = c.gold })

        hl(0, "@string", { fg = c.sky })
        hl(0, "@string.escape", { fg = c.steel })
        hl(0, "@string.special", { fg = c.steel })

        hl(0, "@number", { fg = c.teal })
        hl(0, "@boolean", { fg = c.teal, bold = true })

        hl(0, "@function", { fg = c.cyan, bold = true })
        hl(0, "@function.builtin", { fg = c.steel, bold = true })
        hl(0, "@function.method", { fg = c.cyan })
        hl(0, "@function.method.call", { fg = c.cyan })
        hl(0, "@function.macro", { fg = c.gold })
        hl(0, "@constructor", { fg = c.blue_soft })

        hl(0, "@keyword", { fg = c.blue, bold = true })
        hl(0, "@keyword.import", { fg = c.gold })
        hl(0, "@keyword.return", { fg = c.blue, italic = true })
        hl(0, "@keyword.operator", { fg = c.blue })
        hl(0, "@keyword.function", { fg = c.blue, bold = true })

        hl(0, "@type", { fg = c.blue_soft, bold = true })
        hl(0, "@type.builtin", { fg = c.blue_soft })
        hl(0, "@type.qualifier", { fg = c.blue })

        hl(0, "@attribute", { fg = c.lavender })
        hl(0, "@namespace", { fg = c.steel })
        hl(0, "@module", { fg = c.steel })
        hl(0, "@label", { fg = c.blue })
        hl(0, "@operator", { fg = c.fg_dim })
        hl(0, "@punctuation.bracket", { fg = c.fg_dim })
        hl(0, "@punctuation.delimiter", { fg = c.fg_dim })
        hl(0, "@comment", { fg = c.fg_muted, italic = true })
        hl(0, "@comment.todo", { fg = c.bg, bg = c.cyan, bold = true })

        -- Markup (markdown etc.)
        hl(0, "@markup.heading", { fg = c.cyan, bold = true })
        hl(0, "@markup.strong", { fg = c.fg, bold = true })
        hl(0, "@markup.italic", { fg = c.fg_dim, italic = true })
        hl(0, "@markup.link", { fg = c.sky, underline = true })
        hl(0, "@markup.raw", { fg = c.teal })

        -- ── UI ────────────────────────────────────────────────────────
        hl(0, "LineNr", { fg = c.fg_muted })
        hl(0, "CursorLineNr", { fg = c.cyan, bold = true })
        hl(0, "CursorLine", { bg = c.bg_select })
        hl(0, "CursorColumn", { bg = c.bg_select })
        hl(0, "ColorColumn", { bg = c.bg_raised })
        hl(0, "SignColumn", { fg = c.fg_muted, bg = c.bg })
        hl(0, "FoldColumn", { fg = c.hint, bg = c.bg })
        hl(0, "Folded", { fg = c.fg_dim, bg = c.bg_raised })

        hl(0, "Visual", { bg = c.bg_select })
        hl(0, "VisualNOS", { bg = c.bg_select })

        hl(0, "Search", { fg = c.bg, bg = c.cyan })
        hl(0, "IncSearch", { fg = c.bg, bg = c.blue, bold = true })
        hl(0, "CurSearch", { fg = c.bg, bg = c.blue, bold = true })

        hl(0, "MatchParen", { fg = c.teal, bold = true, underline = true })

        hl(0, "Pmenu", { fg = c.fg, bg = c.bg_raised })
        hl(0, "PmenuSel", { fg = c.bg, bg = c.cyan, bold = true })
        hl(0, "PmenuSbar", { bg = c.bg_raised })
        hl(0, "PmenuThumb", { bg = c.border })

        hl(0, "WildMenu", { fg = c.bg, bg = c.cyan })

        hl(0, "StatusLine", { fg = c.fg_dim, bg = c.bg_subtle })
        hl(0, "StatusLineNC", { fg = c.fg_muted, bg = c.bg_subtle })
        hl(0, "WinSeparator", { fg = c.border })
        hl(0, "VertSplit", { fg = c.border })

        hl(0, "TabLine", { fg = c.fg_muted, bg = c.bg_subtle })
        hl(0, "TabLineSel", { fg = c.cyan, bg = c.bg, bold = true })
        hl(0, "TabLineFill", { bg = c.bg_subtle })

        hl(0, "BufferLineBufferSelected", { fg = c.cyan, bold = true })
        hl(0, "BufferLineBufferVisible", { fg = c.fg_dim })
        hl(0, "BufferLineBuffer", { fg = c.fg_muted })

        hl(0, "Title", { fg = c.cyan, bold = true })
        hl(0, "Directory", { fg = c.blue })
        hl(0, "NonText", { fg = c.hint })
        hl(0, "Whitespace", { fg = c.hint })
        hl(0, "SpecialKey", { fg = c.hint })
        hl(0, "Conceal", { fg = c.fg_muted })

        hl(0, "SpellBad", { undercurl = true, sp = c.red })
        hl(0, "SpellWarn", { undercurl = true, sp = c.orange })

        -- ── Diagnostics ───────────────────────────────────────────────
        hl(0, "DiagnosticError", { fg = c.red })
        hl(0, "DiagnosticWarn", { fg = c.orange })
        hl(0, "DiagnosticInfo", { fg = c.sky })
        hl(0, "DiagnosticHint", { fg = c.teal })
        hl(0, "DiagnosticOk", { fg = c.teal })
        hl(0, "DiagnosticUnderlineError", { undercurl = true, sp = c.red })
        hl(0, "DiagnosticUnderlineWarn", { undercurl = true, sp = c.orange })
        hl(0, "DiagnosticUnderlineInfo", { undercurl = true, sp = c.sky })
        hl(0, "DiagnosticUnderlineHint", { undercurl = true, sp = c.teal })
        hl(0, "DiagnosticVirtualTextError", { fg = c.red, bg = c.bg_raised })
        hl(0, "DiagnosticVirtualTextWarn", { fg = c.orange, bg = c.bg_raised })
        hl(0, "DiagnosticVirtualTextInfo", { fg = c.sky, bg = c.bg_raised })
        hl(0, "DiagnosticVirtualTextHint", { fg = c.teal, bg = c.bg_raised })

        -- ── Git ───────────────────────────────────────────────────────
        hl(0, "GitSignsAdd", { fg = c.teal })
        hl(0, "GitSignsChange", { fg = c.sky })
        hl(0, "GitSignsDelete", { fg = c.red })
        hl(0, "DiffAdd", { bg = "#091a12" })
        hl(0, "DiffChange", { bg = "#091424" })
        hl(0, "DiffDelete", { bg = "#1a0909" })
        hl(0, "DiffText", { bg = "#0f2040" })

        -- ── LSP semantic tokens ───────────────────────────────────────
        hl(0, "@lsp.type.function", { link = "@function" })
        hl(0, "@lsp.type.method", { link = "@function.method" })
        hl(0, "@lsp.type.keyword", { link = "@keyword" })
        hl(0, "@lsp.type.type", { link = "@type" })
        hl(0, "@lsp.type.class", { link = "@type" })
        hl(0, "@lsp.type.interface", { fg = c.blue_soft, italic = true })
        hl(0, "@lsp.type.variable", { link = "@variable" })
        hl(0, "@lsp.type.parameter", { link = "@variable.parameter" })
        hl(0, "@lsp.type.property", { fg = c.fg })
        hl(0, "@lsp.type.namespace", { link = "@namespace" })
        hl(0, "@lsp.type.enum", { fg = c.blue_soft })
        hl(0, "@lsp.type.enumMember", { fg = c.sky })
        hl(0, "@lsp.type.decorator", { fg = c.lavender })
        hl(0, "@lsp.type.macro", { fg = c.gold })
        hl(0, "@lsp.type.comment", { link = "@comment" })

        -- ── Telescope ─────────────────────────────────────────────────
        hl(0, "TelescopeBorder", { fg = c.border })
        hl(0, "TelescopeNormal", { fg = c.fg, bg = c.bg_raised })
        hl(0, "TelescopePromptBorder", { fg = c.cyan })
        hl(0, "TelescopePromptNormal", { fg = c.fg, bg = c.bg_raised })
        hl(0, "TelescopePromptPrefix", { fg = c.cyan })
        hl(0, "TelescopeSelection", { fg = c.fg, bg = c.bg_select })
        hl(0, "TelescopeSelectionCaret", { fg = c.cyan })
        hl(0, "TelescopeMatching", { fg = c.cyan, bold = true })

        -- ── nvim-tree ─────────────────────────────────────────────────
        hl(0, "NvimTreeFolderName", { fg = c.blue })
        hl(0, "NvimTreeFolderIcon", { fg = c.blue })
        hl(0, "NvimTreeOpenedFolderName", { fg = c.cyan, bold = true })
        hl(0, "NvimTreeRootFolder", { fg = c.cyan, bold = true })
        hl(0, "NvimTreeGitDirty", { fg = c.orange })
        hl(0, "NvimTreeGitNew", { fg = c.teal })

        -- ── Indent guides ─────────────────────────────────────────────
        hl(0, "IblIndent", { fg = c.hint })
        hl(0, "IblScope", { fg = c.border })

        -- ── Which-key ─────────────────────────────────────────────────
        hl(0, "WhichKey", { fg = c.cyan })
        hl(0, "WhichKeyGroup", { fg = c.blue })
        hl(0, "WhichKeyDesc", { fg = c.fg_dim })
      end,
    },
  },
}
