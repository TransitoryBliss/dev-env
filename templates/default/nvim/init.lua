require("config.lazy")

vim.opt.clipboard = "unnamedplus"

vim.keymap.set("n", "<leader>f", ':lua require("oil").open()<CR>', { desc = "Open file explorer" })

vim.api.nvim_set_keymap("n", "<leader>o", "<cmd>Octo<cr>", { desc = "Octo" })
vim.api.nvim_set_keymap("n", "<C-p>", ':lua require("fzf-lua").files()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-f>", ':lua require("fzf-lua").live_grep()<CR>', { noremap = true, silent = true })

vim.cmd.colorscheme("gruvbox")

vim.o.relativenumber = true
vim.o.number = true

vim.o.inccommand = "split"

vim.o.smartcase = true
vim.o.ignorecase = true
vim.o.splitbelow = true
vim.o.splitright = true

vim.o.signcolumn = "yes"

vim.o.swapfile = false

vim.o.wrap = true
vim.o.linebreak = true

vim.o.tabstop = 4
vim.o.shiftwidth = 4

vim.o.more = false

vim.o.foldmethod = "manual"
