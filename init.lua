-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.g.mapleader = " "
-- init.lua
require("opts")
require("kebindings")
require("plugin.lazy")

