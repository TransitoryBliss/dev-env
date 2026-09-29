-- lazy.nvim specs for dev-env-theme. Load from the private nvim config with
--   return loadfile(vim.fn.expand("~/.local/share/dev-env/theme.nvim/spec.lua"))(opts)
-- (the base links this directory there). opts go to setup(), e.g.
-- { fallback = "gruvbox" } for when no devEnv.theme is set, or
-- { transparent = false }. Every supported colorscheme plugin is
-- listed with lazy = true: lazy.nvim loads one only when `:colorscheme` asks for
-- it, so the unused ones are cloned once but never loaded. Their versions are
-- pinned in the private config's lazy-lock.json.
local opts = ... or {}
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local f = assert(io.open(dir .. "/families.json", "r"))
local families = vim.json.decode(f:read("*a"))
f:close()

local specs = {
	{
		dir = dir,
		name = "dev-env-theme",
		lazy = false,
		priority = 1000, -- before every other plugin, so they see the final colours
		config = function()
			require("dev-env-theme").setup(opts)
		end,
	},
}

local names = vim.tbl_keys(families)
table.sort(names)
for _, family in ipairs(names) do
	local plugin = families[family]
	table.insert(specs, { plugin.repo, name = plugin.name, lazy = true })
end

return specs
