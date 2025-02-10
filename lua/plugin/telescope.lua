local M = {
	"nvim-telescope/telescope.nvim",
	dependencies = { "nvim-lua/plenary.nvim" },
	lazy = true,
	cmd = "Telescope",
}

function M.config()
    -- Set up telescope
    require('telescope').setup({
        defaults = {
        prompt_prefix = "🔍 ",
        selection_caret = " ",
        entry_prefix = "  ",
        winblend = 10,
        border = true,
        borderchars = {'-', '|', '-', '|', '┌', '┐', '┘', '└'},
        },
    })
end

return M

