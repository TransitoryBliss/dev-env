return {
	{
		-- Popup listing what a started key sequence can continue with.
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {},
	},
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		event = "VeryLazy",
		opts = {
			-- Derived from whatever colorscheme devEnv.theme picked.
			options = { theme = "auto" },
		},
	},
}
