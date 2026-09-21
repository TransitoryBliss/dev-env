-- A minimal starting point; replace it with your own config. This folder is
-- linked to ~/.config/nvim, so edits apply without a rebuild.
--
-- Plugin managers work as usual. Language servers come from Nix (the
-- devEnv.languages flags), not Mason: Mason's binaries don't run on NixOS.

vim.g.mapleader = " "
vim.o.number = true
vim.o.relativenumber = true
vim.o.signcolumn = "yes"
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.clipboard = "unnamedplus" -- over SSH this uses OSC 52, i.e. your local clipboard

-- Start each language server whose binary is installed.
local servers = {
	gopls = { cmd = { "gopls" }, filetypes = { "go", "gomod", "gowork" }, root_markers = { "go.mod", ".git" } },
	ts_ls = {
		cmd = { "typescript-language-server", "--stdio" },
		filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
		root_markers = { "package.json", "tsconfig.json", ".git" },
	},
	lua_ls = { cmd = { "lua-language-server" }, filetypes = { "lua" }, root_markers = { ".git" } },
}

for name, config in pairs(servers) do
	if vim.fn.executable(config.cmd[1]) == 1 then
		vim.lsp.config(name, config)
		vim.lsp.enable(name)
	end
end
