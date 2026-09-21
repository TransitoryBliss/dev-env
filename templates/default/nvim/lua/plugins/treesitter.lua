-- nvim-treesitter's `main` branch: it only installs parsers and queries;
-- highlighting is Neovim's own and is switched on per buffer below.
-- Parsers are compiled locally (tree-sitter CLI and gcc come from Nix).
local parsers = {
	"bash",
	"css",
	"diff",
	"dockerfile",
	"gitcommit",
	"go",
	"gomod",
	"gosum",
	"gowork",
	"html",
	"javascript",
	"json",
	"lua",
	"make",
	"markdown",
	"markdown_inline",
	"nix",
	"python",
	"query",
	"regex",
	"rust",
	"sql",
	"toml",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
	"yaml",
}

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false, -- doesn't support lazy-loading
		build = ":TSUpdate",
		config = function()
			-- Installs asynchronously; already-installed parsers are skipped.
			require("nvim-treesitter").install(parsers)

			vim.api.nvim_create_autocmd("FileType", {
				callback = function(args)
					-- Fails quietly for filetypes without an installed parser.
					if pcall(vim.treesitter.start, args.buf) then
						vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})
		end,
	},
}
