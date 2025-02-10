-- init.lua
require('opts')
require('launch')
require('kebindings')

-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

spec('plugin.telescope')
spec('plugin.luarocks')
spec('plugin.nvimtree')
spec('plugin.lualine')
spec('plugin.treesitter')
spec('plugin.lsp-zero')
spec('plugin.mason')


require('plugin.lazy')
