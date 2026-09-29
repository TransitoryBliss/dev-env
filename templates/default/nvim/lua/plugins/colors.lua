-- The colorscheme follows devEnv.theme (users/me.nix): the base's dev-env-theme
-- plugin reads ~/.config/dev-env/theme.json and applies the matching
-- colorscheme with a transparent background, so the terminal's background
-- (written by herdr-attach from the same palette) shows through. With no theme
-- set, gruvbox. Before the first `make switch` the plugin isn't there yet, so
-- plain gruvbox too.
local spec = vim.fn.expand("~/.local/share/dev-env/theme.nvim/spec.lua")
if vim.uv.fs_stat(spec) then
	return loadfile(spec)({ fallback = "gruvbox" })
end

return {
	{
		"ellisonleao/gruvbox.nvim",
		priority = 1000,
		lazy = false,
		config = function()
			vim.cmd.colorscheme("gruvbox")
		end,
	},
}
