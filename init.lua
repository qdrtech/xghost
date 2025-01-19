-- init.lua

-- Ensure lazy.nvim is installed and loaded
vim.opt.rtp:prepend("~/.local/share/nvim/site/pack/lazy/opt/lazy.nvim")

-- Plugin manager setup using lazy.nvim
require('lazy').setup({

  -- TokyoNight theme
  { 'folke/tokyonight.nvim' },

  -- Telescope for fuzzy finding
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' }
  },

  -- File explorer
  { 'nvim-tree/nvim-tree.lua' },

  -- Statusline
  { 'nvim-lualine/lualine.nvim' },

  -- Autocompletion
  { 'hrsh7th/nvim-cmp' },
  { 'hrsh7th/cmp-nvim-lsp' },
  { 'hrsh7th/cmp-buffer' },
  { 'hrsh7th/cmp-path' },
  { 'saadparwaiz1/cmp_luasnip' },

  -- Snippets support
  { 'L3MON4D3/LuaSnip' },
  { 'rafamadriz/friendly-snippets' },

  -- LSP configuration
  { 'neovim/nvim-lspconfig' },
  { 'williamboman/mason.nvim' },
  { 'williamboman/mason-lspconfig.nvim' },

  -- Treesitter for syntax highlighting and code navigation
  { 'nvim-treesitter/nvim-treesitter' },

  -- Git integration
  { 'tpope/vim-fugitive' },

  -- Automatically sync plugins after saving init.lua
  { 'wbthomason/packer.nvim', opt = true },

})

-- Set the theme (tokyonight)
vim.cmd [[colorscheme tokyonight]]

-- Basic settings
vim.opt.number = true                -- Show line numbers
vim.opt.relativenumber = true        -- Relative line numbers
vim.opt.expandtab = true             -- Convert tabs to spaces
vim.opt.shiftwidth = 2               -- Indentation width
vim.opt.tabstop = 2                 -- Tab width
vim.opt.smartindent = true           -- Smart indentation
vim.opt.hlsearch = true              -- Highlight search matches
vim.opt.ignorecase = true            -- Ignore case in search
vim.opt.smartcase = true             -- Smart case sensitivity
vim.opt.clipboard = "unnamedplus"    -- Use system clipboard

-- Set up telescope
require('telescope').setup{
  defaults = {
    prompt_prefix = "🔍 ",
    selection_caret = " ",
    entry_prefix = "  ",
    winblend = 10,
    border = true,
    borderchars = {'-', '|', '-', '|', '┌', '┐', '┘', '└'},
  },
}

-- Key mappings for telescope
vim.api.nvim_set_keymap('n', '<Leader>ff', ':Telescope find_files<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>fg', ':Telescope live_grep<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>fb', ':Telescope buffers<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>ft', ':Telescope help_tags<CR>', { noremap = true, silent = true })

-- Set up nvim-tree
require('nvim-tree').setup({
  view = {
    width = 30,                    -- Width of the file tree
  },
})

-- Set up lualine (statusline)
require('lualine').setup({
  options = {
    theme = 'tokyonight',
  },
})

-- Set up Treesitter
require'nvim-treesitter.configs'.setup {
  ensure_installed = "all", -- Only install maintained parsers
  highlight = {
    enable = true,                 -- Enable Treesitter-based highlighting
  },
}

-- LSP Setup (example for pyright)
require('mason').setup()
require('mason-lspconfig').setup()
require('lspconfig').pyright.setup{}

-- Key mappings for NvimTree toggle
vim.api.nvim_set_keymap('n', '<Leader>e', ':NvimTreeToggle<CR>', { noremap = true, silent = true })

