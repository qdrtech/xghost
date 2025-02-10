local M = { 'nvim-tree/nvim-tree.lua' }

function M.conifg()
    -- Set up nvim-tree
    require('nvim-tree').setup({
        view = {
        width = 30,                    -- Width of the file tree
        },
    })
end

return M