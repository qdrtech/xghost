-- Key mappings for telescope
vim.api.nvim_set_keymap("n", "<Leader>ff", ":Telescope find_files<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Leader>fg", ":Telescope live_grep<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Leader>fb", ":Telescope buffers<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Leader>ft", ":Telescope help_tags<CR>", { noremap = true, silent = true })

-- File explorer keybindings
vim.keymap.set("n", "<leader>e", function()
	Snacks.explorer()
end, { desc = "Explorer" })
vim.keymap.set("n", "<leader>E", function()
	Snacks.explorer({ cwd = vim.uv.cwd() })
end, { desc = "Explorer (cwd)" })

-- Close buffer keybindings
vim.keymap.set("n", "<leader>bd", ":bd<CR>", { desc = "Close Buffer" })

-- LSP keybindings (custom)
vim.keymap.set("n", "<leader>gd", vim.lsp.buf.definition, { desc = "Goto Definition" })
vim.keymap.set("n", "<leader>gi", vim.lsp.buf.implementation, { desc = "Goto Implementation" })
vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, { desc = "Goto References" })
vim.keymap.set("n", "<leader>gt", vim.lsp.buf.type_definition, { desc = "Goto Type Definition" })

-- Other keybindings
vim.keymap.set("i", "jj", "<Esc>", { noremap = true })
