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

        -- ── Color math ────────────────────────────────────────────────
        local function hex2rgb(hex)
          hex = hex:gsub("^#", "")
          return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
        end

        local function rgb2hex(r, g, b)
          local function f(v)
            return string.format("%02x", math.max(0, math.min(255, math.floor(v + 0.5))))
          end
          return "#" .. f(r) .. f(g) .. f(b)
        end

        local function rgb2hsl(r, g, b)
          r, g, b = r / 255, g / 255, b / 255
          local max, min = math.max(r, g, b), math.min(r, g, b)
          local l = (max + min) / 2
          local h, s = 0, 0
          if max ~= min then
            local d = max - min
            s = l > 0.5 and d / (2 - max - min) or d / (max + min)
            if max == r then
              h = (g - b) / d + (g < b and 6 or 0)
            elseif max == g then
              h = (b - r) / d + 2
            else
              h = (r - g) / d + 4
            end
            h = h / 6
          end
          return h, s, l
        end

        local function hsl2rgb(h, s, l)
          local function hue(p, q, t)
            if t < 0 then t = t + 1 end
            if t > 1 then t = t - 1 end
            if t < 1 / 6 then return p + (q - p) * 6 * t end
            if t < 1 / 2 then return q end
            if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
            return p
          end
          local r, g, b
          if s == 0 then
            r, g, b = l, l, l
          else
            local q = l < 0.5 and l * (1 + s) or l + s - l * s
            local p = 2 * l - q
            r, g, b = hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3)
          end
          return r * 255, g * 255, b * 255
        end

        -- Shift hue by degrees; adjust saturation/lightness by deltas.
        local function tweak(hex, dhue, ds, dl)
          local r, g, b = hex2rgb(hex)
          local h, s, l = rgb2hsl(r, g, b)
          h = (h + dhue / 360) % 1
          s = math.max(0, math.min(1, s + ds))
          l = math.max(0, math.min(1, l + dl))
          local rr, gg, bb = hsl2rgb(h, s, l)
          return rgb2hex(rr, gg, bb)
        end

        -- Hue-locked helper: keep wallpaper saturation/lightness but force hue for semantics.
        -- Ensures warnings are always yellow and success always green, on any wallpaper.
        -- Desaturate + slightly darken so colors are soft on dark bg (not neon/eye-hurting).
        local function hue_from(hex, target_hue, ds, dl)
          local r, g, b = hex2rgb(hex)
          local h, s, l = rgb2hsl(r, g, b)
          s = math.max(0, math.min(1, s + (ds or -0.10)))
          l = math.max(0, math.min(1, l + (dl or -0.06)))
          local rr, gg, bb = hsl2rgb(target_hue / 360, s, l)
          return rgb2hex(rr, gg, bb)
        end

        -- ── Matugen scheme (wallpaper-derived) ────────────────────────
        local base = {
          bg         = "{{ colors.background.default.hex }}",
          bg_subtle  = "{{ colors.surface_container_low.default.hex }}",
          bg_raised  = "{{ colors.surface_container.default.hex }}",
          bg_select  = "{{ colors.surface_container_high.default.hex }}",
          fg         = "{{ colors.on_background.default.hex }}",
          fg_dim     = "{{ colors.on_surface_variant.default.hex }}",
          fg_muted   = "{{ colors.outline.default.hex }}",
          primary    = "{{ colors.primary.default.hex }}",
          secondary  = "{{ colors.secondary.default.hex }}",
          tertiary   = "{{ colors.tertiary.default.hex }}",
          error      = "{{ colors.error.default.hex }}",
        }

        -- ── Palette ───────────────────────────────────────────────────
        --  Syntax hues are rotated from primary but with lower lightness
        --  for eye comfort (was +0.04-0.06, now +0.02-0.03). Semantic
        --  colors are hue-locked: red stays red, yellow stays yellow,
        --  green stays green — on any wallpaper — but s/l still from
        --  wallpaper so they harmonize and aren't harsh. Matches Zed.
        local c = {
          -- Backgrounds
          bg        = base.bg,
          bg_subtle = base.bg_subtle,
          bg_raised = base.bg_raised,
          bg_select = base.bg_select,

          -- Foregrounds
          fg        = base.fg,
          fg_dim    = base.fg_dim,
          fg_muted  = base.fg_muted,

          -- Syntax hues (eye-friendly lightness)
          cyan      = base.primary, -- functions & methods
          violet    = tweak(base.primary, 30, 0.10, 0.02), -- keywords
          soft_cyan = tweak(base.primary, -30, 0.10, 0.02), -- types & classes
          green     = tweak(base.primary, -90, 0.14, -0.02), -- strings
          orange    = tweak(base.primary, -200, 0.12, 0.02), -- numbers
          teal      = tweak(base.primary, -50, 0.12, 0.03), -- constants
          gold      = tweak(base.primary, -170, 0.10, 0.04), -- imports
          steel     = tweak(base.primary, -15, -0.15, -0.10), -- builtins
          lavender  = tweak(base.primary, 45, 0.08, 0.04), -- attributes
          -- Semantic – hue-locked, wallpaper-aware, soft on dark bg
          red       = tweak(base.error, -2, -0.07, -0.05), -- error red (softened matugen error)
          warn      = hue_from(base.primary, 44, -0.09, -0.07), -- warning amber/yellow (always yellow)
          yellow    = hue_from(base.primary, 44, -0.09, -0.07), -- alias
          success   = hue_from(base.primary, 142, -0.10, -0.07), -- success green (always green)
          hint_green = tweak(hue_from(base.primary, 142, -0.10, -0.07), 0, -0.12, 0.02), -- muted hint green
          -- keep compatibility: warn alias == yellow
          -- UI chrome
          border    = "{{ colors.surface_container_highest.default.hex }}",
          hint      = "{{ colors.outline_variant.default.hex }}",
        }

        -- ── Base ──────────────────────────────────────────────────────
        hl(0, "Normal", { fg = c.fg, bg = c.bg })
        hl(0, "NormalFloat", { fg = c.fg, bg = c.bg_raised })
        hl(0, "NormalNC", { fg = c.fg_dim, bg = c.bg })
        hl(0, "EndOfBuffer", { fg = c.bg })

        -- ── Syntax ────────────────────────────────────────────────────
        hl(0, "Comment", { fg = c.fg_muted, italic = true })
        hl(0, "Constant", { fg = c.teal })
        hl(0, "String", { fg = c.green })
        hl(0, "Character", { fg = c.green })
        hl(0, "Number", { fg = c.orange })
        hl(0, "Float", { fg = c.orange })
        hl(0, "Boolean", { fg = c.orange, bold = true })

        hl(0, "Identifier", { fg = c.fg })
        hl(0, "Function", { fg = c.cyan, bold = true })

        hl(0, "Statement", { fg = c.violet })
        hl(0, "Conditional", { fg = c.violet, bold = true })
        hl(0, "Repeat", { fg = c.violet, bold = true })
        hl(0, "Label", { fg = c.violet })
        hl(0, "Keyword", { fg = c.violet, bold = true })
        hl(0, "Exception", { fg = c.red, bold = true })
        hl(0, "Operator", { fg = c.fg_dim })

        hl(0, "PreProc", { fg = c.gold })
        hl(0, "Include", { fg = c.gold })
        hl(0, "Define", { fg = c.gold })
        hl(0, "Macro", { fg = c.gold })

        hl(0, "Type", { fg = c.soft_cyan, bold = true })
        hl(0, "StorageClass", { fg = c.violet })
        hl(0, "Structure", { fg = c.soft_cyan })
        hl(0, "Typedef", { fg = c.soft_cyan })

        hl(0, "Special", { fg = c.steel })
        hl(0, "SpecialChar", { fg = c.steel })
        hl(0, "Tag", { fg = c.violet })
        hl(0, "Delimiter", { fg = c.fg_dim })
        hl(0, "SpecialComment", { fg = c.steel, italic = true })

        hl(0, "Error", { fg = c.red, bold = true })
        hl(0, "Todo", { fg = c.bg, bg = c.cyan, bold = true })
        hl(0, "Underlined", { fg = c.green, underline = true })

        -- ── Treesitter ────────────────────────────────────────────────
        hl(0, "@variable", { fg = c.fg })
        hl(0, "@variable.builtin", { fg = c.steel, italic = true })
        hl(0, "@variable.parameter", { fg = c.fg_dim })
        hl(0, "@variable.member", { fg = c.fg })

        hl(0, "@constant", { fg = c.teal })
        hl(0, "@constant.builtin", { fg = c.teal, bold = true })
        hl(0, "@constant.macro", { fg = c.gold })

        hl(0, "@string", { fg = c.green })
        hl(0, "@string.escape", { fg = c.gold })
        hl(0, "@string.special", { fg = c.green })

        hl(0, "@number", { fg = c.orange })
        hl(0, "@boolean", { fg = c.orange, bold = true })

        hl(0, "@function", { fg = c.cyan, bold = true })
        hl(0, "@function.builtin", { fg = c.steel, bold = true })
        hl(0, "@function.method", { fg = c.cyan })
        hl(0, "@function.method.call", { fg = c.cyan })
        hl(0, "@function.macro", { fg = c.gold })
        hl(0, "@constructor", { fg = c.soft_cyan })

        hl(0, "@keyword", { fg = c.violet, bold = true })
        hl(0, "@keyword.import", { fg = c.gold })
        hl(0, "@keyword.return", { fg = c.violet, italic = true })
        hl(0, "@keyword.operator", { fg = c.violet })
        hl(0, "@keyword.function", { fg = c.violet, bold = true })

        hl(0, "@type", { fg = c.soft_cyan, bold = true })
        hl(0, "@type.builtin", { fg = c.soft_cyan })
        hl(0, "@type.qualifier", { fg = c.violet })

        hl(0, "@attribute", { fg = c.lavender })
        hl(0, "@namespace", { fg = c.steel })
        hl(0, "@module", { fg = c.steel })
        hl(0, "@label", { fg = c.violet })
        hl(0, "@operator", { fg = c.fg_dim })
        hl(0, "@punctuation.bracket", { fg = c.fg_dim })
        hl(0, "@punctuation.delimiter", { fg = c.fg_dim })
        hl(0, "@comment", { fg = c.fg_muted, italic = true })
        hl(0, "@comment.todo", { fg = c.bg, bg = c.cyan, bold = true })

        -- Markup (markdown etc.)
        hl(0, "@markup.heading", { fg = c.cyan, bold = true })
        hl(0, "@markup.strong", { fg = c.fg, bold = true })
        hl(0, "@markup.italic", { fg = c.fg_dim, italic = true })
        hl(0, "@markup.link", { fg = c.green, underline = true })
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
        hl(0, "IncSearch", { fg = c.bg, bg = c.violet, bold = true })
        hl(0, "CurSearch", { fg = c.bg, bg = c.violet, bold = true })

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
        hl(0, "Directory", { fg = c.violet })
        hl(0, "NonText", { fg = c.hint })
        hl(0, "Whitespace", { fg = c.hint })
        hl(0, "SpecialKey", { fg = c.hint })
        hl(0, "Conceal", { fg = c.fg_muted })

        hl(0, "SpellBad", { undercurl = true, sp = c.red })
        hl(0, "SpellWarn", { undercurl = true, sp = c.warn })

        -- ── Diagnostics ───────────────────────────────────────────────
        -- Semantic: red=error, yellow=warning, green=success, blue=info, muted green=hint
        hl(0, "DiagnosticError", { fg = c.red })
        hl(0, "DiagnosticWarn", { fg = c.warn })
        hl(0, "DiagnosticInfo", { fg = c.cyan })
        hl(0, "DiagnosticHint", { fg = c.hint_green })
        hl(0, "DiagnosticOk", { fg = c.success })
        hl(0, "DiagnosticUnderlineError", { undercurl = true, sp = c.red })
        hl(0, "DiagnosticUnderlineWarn", { undercurl = true, sp = c.warn })
        hl(0, "DiagnosticUnderlineInfo", { undercurl = true, sp = c.cyan })
        hl(0, "DiagnosticUnderlineHint", { undercurl = true, sp = c.hint_green })
        hl(0, "DiagnosticUnderlineOk", { undercurl = true, sp = c.success })
        hl(0, "DiagnosticVirtualTextError", { fg = c.red, bg = c.bg_raised })
        hl(0, "DiagnosticVirtualTextWarn", { fg = c.warn, bg = c.bg_raised })
        hl(0, "DiagnosticVirtualTextInfo", { fg = c.cyan, bg = c.bg_raised })
        hl(0, "DiagnosticVirtualTextHint", { fg = c.hint_green, bg = c.bg_raised })
        hl(0, "DiagnosticVirtualTextOk", { fg = c.success, bg = c.bg_raised })
        hl(0, "DiagnosticSignError", { fg = c.red })
        hl(0, "DiagnosticSignWarn", { fg = c.warn })
        hl(0, "DiagnosticSignInfo", { fg = c.cyan })
        hl(0, "DiagnosticSignHint", { fg = c.hint_green })
        hl(0, "DiagnosticSignOk", { fg = c.success })

        -- ── Git ───────────────────────────────────────────────────────
        hl(0, "GitSignsAdd", { fg = c.success })
        hl(0, "GitSignsChange", { fg = c.teal })
        hl(0, "GitSignsDelete", { fg = c.red })
        hl(0, "DiffAdd", { bg = "{{ colors.surface_container_high.default.hex }}" })
        hl(0, "DiffChange", { bg = "{{ colors.tertiary_container.default.hex }}" })
        hl(0, "DiffDelete", { bg = "{{ colors.error_container.default.hex }}" })
        hl(0, "DiffText", { bg = "{{ colors.primary_container.default.hex }}" })

        -- ── LSP semantic tokens ───────────────────────────────────────
        hl(0, "@lsp.type.function", { link = "@function" })
        hl(0, "@lsp.type.method", { link = "@function.method" })
        hl(0, "@lsp.type.keyword", { link = "@keyword" })
        hl(0, "@lsp.type.type", { link = "@type" })
        hl(0, "@lsp.type.class", { link = "@type" })
        hl(0, "@lsp.type.interface", { fg = c.soft_cyan, italic = true })
        hl(0, "@lsp.type.variable", { link = "@variable" })
        hl(0, "@lsp.type.parameter", { link = "@variable.parameter" })
        hl(0, "@lsp.type.property", { fg = c.fg })
        hl(0, "@lsp.type.namespace", { link = "@namespace" })
        hl(0, "@lsp.type.enum", { fg = c.soft_cyan })
        hl(0, "@lsp.type.enumMember", { fg = c.green })
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
        hl(0, "NvimTreeFolderName", { fg = c.violet })
        hl(0, "NvimTreeFolderIcon", { fg = c.violet })
        hl(0, "NvimTreeOpenedFolderName", { fg = c.cyan, bold = true })
        hl(0, "NvimTreeRootFolder", { fg = c.cyan, bold = true })
        hl(0, "NvimTreeGitDirty", { fg = c.warn })
        hl(0, "NvimTreeGitNew", { fg = c.success })

        -- ── Indent guides ─────────────────────────────────────────────
        hl(0, "IblIndent", { fg = c.hint })
        hl(0, "IblScope", { fg = c.border })

        -- ── Which-key ─────────────────────────────────────────────────
        hl(0, "WhichKey", { fg = c.cyan })
        hl(0, "WhichKeyGroup", { fg = c.violet })
        hl(0, "WhichKeyDesc", { fg = c.fg_dim })
      end,
    },
  },
}
