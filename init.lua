-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- init.lua
require('opts')
require('launch')
require('kebindings')

spec('plugin.telescope')
spec('plugin.luarocks')
spec('plugin.nvim-tree')
spec('plugin.lualine')
spec('plugin.treesitter')
spec('plugin.lsp-zero')
spec('plugin.mason')

require('plugin.lazy')
