-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.g.mapleader = " "

-- Load lazyvim and other configs
require("config.lazy")
require("config.opts")
require("config.keybindings")

-- The colours of the active xghost theme, applied over whichever
-- colourscheme the plugins above loaded. See
-- lua/config/xghost.lua and docs/bundles/neovim.md.
require("config.xghost").setup()
