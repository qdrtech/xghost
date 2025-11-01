-- Key mappings for telescope
vim.api.nvim_set_keymap("n", "<Leader>ff", ":Telescope find_files<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Leader>fg", ":Telescope live_grep<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Leader>fb", ":Telescope buffers<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Leader>ft", ":Telescope help_tags<CR>", { noremap = true, silent = true })

-- File explorer keybindings
vim.keymap.set("n", "<leader>e", function() Snacks.explorer() end, { desc = "Explorer" })
vim.keymap.set("n", "<leader>E", function() Snacks.explorer({ cwd = vim.uv.cwd() }) end, { desc = "Explorer (cwd)" })

-- Other keybindings
vim.keymap.set("i", "jj", "<Esc>", { noremap = true })
