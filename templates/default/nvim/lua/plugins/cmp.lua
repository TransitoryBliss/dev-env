-- No Copilot here: copilot.lua downloads its own language server (a 252 MB
-- zip needing `unzip`), and the AI work happens in pi/Claude Code instead.
-- Completion is LSP, snippets, path and buffer.
return {
	{
		"folke/lazydev.nvim",
		ft = "lua", -- only load on lua files
		opts = {
			library = {
				-- Load luvit types when the `vim.uv` word is found
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			},
		},
	},
	{
		"saghen/blink.cmp",
		dependencies = {
			"rafamadriz/friendly-snippets",
		},
		version = "1.*",
		---@module 'blink.cmp'
		---@type blink.cmp.Config
		opts = {
			appearance = {
				nerd_font_variant = "mono",
			},
			keymap = {
				preset = "super-tab",
			},
			completion = {
				menu = {
					draw = {
						columns = {
							{ "label",     "label_description", gap = 1 },
							{ "kind_icon", "kind" },
						},
					},
				},
				documentation = { auto_show = true, auto_show_delay_ms = 500 },
			},
			sources = {
				default = { "lazydev", "lsp", "path", "snippets", "buffer" },
				providers = {
					lazydev = {
						name = "LazyDev",
						module = "lazydev.integrations.blink",
						score_offset = 100,
					},
				},
			},
		},
		opts_extend = { "sources.default" },
	},
}
