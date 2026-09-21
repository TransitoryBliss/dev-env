-- Gruvbox, hard contrast: matches the terminal palette written by the shell
-- (modules/home/terminal.nix in the base).
return {
	{
		"ellisonleao/gruvbox.nvim",
		priority = 1000, -- load before everything else
		lazy = false,
		opts = {
			contrast = "hard",
			terminal_colors = true,
		},
	},
}
