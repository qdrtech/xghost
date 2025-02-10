local M = {
    "nvim-treesitter/nvim-treesitter",
    build = "TSUpdate",
    lazy = false,
  }

function M.config()
    -- Set up Treesitter
    require'nvim-treesitter.configs'.setup {
        ensure_installed = "all", -- Only install maintained parsers
        highlight = {
        enable = true,                 -- Enable Treesitter-based highlighting
        },
    }
end

return M