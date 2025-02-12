local M = { 
  'nvim-tree/nvim-tree.lua',
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  lazy = false 
}

function M.config()
    -- Set up nvim-tree
    require('nvim-tree').setup({
        view = {
            width = 30,                    -- Width of the file tree
        },
        filters = {
            dotfiles = true,               -- Show hidden files
        },
    })
end

return M