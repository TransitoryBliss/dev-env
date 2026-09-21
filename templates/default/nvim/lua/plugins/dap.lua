-- nvim-dap with nvim-dap-view as the UI (nvim-dap-ui is unmaintained).
return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			"igorlfs/nvim-dap-view",
			"theHamsta/nvim-dap-virtual-text", -- shows variable values inline
			"leoluz/nvim-dap-go",
		},
		config = function()
			local dap = require("dap")
			local dapview = require("dap-view")

			require("nvim-dap-virtual-text").setup({})
			-- auto_toggle opens the UI when a session starts and closes it at the end.
			dapview.setup({ auto_toggle = true })
			require("dap-go").setup()

			-- Keybindings
			vim.keymap.set("n", "<F5>", function()
				dap.continue()
			end, { desc = "Start/Continue" })
			vim.keymap.set("n", "<F10>", function()
				dap.step_over()
			end, { desc = "Step Over" })
			vim.keymap.set("n", "<F11>", function()
				dap.step_into()
			end, { desc = "Step Into" })
			vim.keymap.set("n", "<F12>", function()
				dap.step_out()
			end, { desc = "Step Out" })
			vim.keymap.set("n", "<Leader>b", function()
				dap.toggle_breakpoint()
			end, { desc = "Toggle Breakpoint" })
			vim.keymap.set("n", "<Leader>B", function()
				dap.set_breakpoint(vim.fn.input("Condition: "))
			end, { desc = "Conditional Breakpoint" })
			vim.keymap.set("n", "<Leader>dr", function()
				dapview.jump_to_view("repl")
			end, { desc = "Open REPL" })
			vim.keymap.set("n", "<Leader>du", function()
				dapview.toggle()
			end, { desc = "Toggle DAP UI" })
		end,
	},
}
