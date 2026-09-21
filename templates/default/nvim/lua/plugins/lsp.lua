-- Language servers are installed by Nix (see home/editor.nix and home/languages.nix),
-- not Mason: Mason's prebuilt binaries don't run on NixOS. A server is enabled only
-- when its binary is on PATH, so toggling a language flag is enough.
local servers = {
	lua_ls = "lua-language-server",
	pyright = "pyright-langserver",
	rust_analyzer = "rust-analyzer",
	ts_ls = "typescript-language-server",
	gopls = "gopls",
	yamlls = "yaml-language-server",
	nil_ls = "nil",
}

return {
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"saghen/blink.cmp",
		},
		config = function()
			vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })

			for server, cmd in pairs(servers) do
				if vim.fn.executable(cmd) == 1 then
					vim.lsp.enable(server)
				end
			end
		end,
	},
}
