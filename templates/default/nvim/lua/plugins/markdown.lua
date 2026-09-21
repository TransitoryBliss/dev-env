return {
	"MeanderingProgrammer/render-markdown.nvim",
	-- nvim-web-devicons is already pulled in by fzf-lua/oil/lualine, so it is
	-- used as the icon provider rather than adding mini.nvim for that alone.
	dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
	---@module 'render-markdown'
	---@type render.md.UserConfig
	opts = {
		latex = { enabled = false }, -- needs a latex parser and utftex/latex2text
	},
}
