-- Formatting (conform.nvim) and linting (nvim-lint), replacing none-ls.
-- The tools themselves come from Nix and are only present when the host turns
-- the language on (devEnv.languages.*), so every entry is gated on the binary
-- being on PATH: a missing tool is silently skipped rather than an error.
--
-- A plugin's name for a tool is not always the binary's: nvim-lint calls
-- golangci-lint `golangcilint`. Each entry is therefore { name, binary }, with
-- the binary defaulting to the name.
local function available(tools)
	local found = {}
	for _, tool in ipairs(tools) do
		local name = tool[1] or tool
		local binary = tool[2] or name
		if vim.fn.executable(binary) == 1 then
			table.insert(found, name)
		end
	end
	return found
end

local prettier_fts = {
	"javascript",
	"javascriptreact",
	"typescript",
	"typescriptreact",
	"json",
	"jsonc",
	"css",
	"html",
	"markdown",
	"yaml",
}

local eslint_fts = {
	"javascript",
	"javascriptreact",
	"typescript",
	"typescriptreact",
}

return {
	{
		"stevearc/conform.nvim",
		event = { "BufWritePre" },
		cmd = "ConformInfo",
		opts = function()
			local formatters_by_ft = {
				lua = available({ "stylua" }),
				go = available({ "goimports", "gofumpt" }),
				-- No nix formatter on purpose: nixfmt would reformat the existing
				-- .nix files here wholesale on the first save.
			}
			for _, ft in ipairs(prettier_fts) do
				formatters_by_ft[ft] = available({ "prettier" })
			end

			return {
				formatters_by_ft = formatters_by_ft,
				-- Falls back to the language server when no formatter is installed.
				format_on_save = {
					timeout_ms = 2000,
					lsp_format = "fallback",
				},
			}
		end,
	},
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPost", "BufNewFile", "BufWritePost" },
		config = function()
			local lint = require("lint")

			local linters_by_ft = {
				go = available({ { "golangcilint", "golangci-lint" } }),
			}
			for _, ft in ipairs(eslint_fts) do
				linters_by_ft[ft] = available({ "eslint_d" })
			end
			lint.linters_by_ft = linters_by_ft

			vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
				group = vim.api.nvim_create_augroup("nvim_lint", { clear = true }),
				callback = function()
					lint.try_lint()
				end,
			})
		end,
	},
}
