local M = {
	'akinsho/bufferline.nvim', 
	version = "*", 
	event = "VeryLazy",
	dependencies = 'nvim-tree/nvim-web-devicons',
	opts = {
		options = {
			mode = 'buffers',
			seperator_styhle = "padded_slant",
			diagnostics = "nvim_lsp",
			always_show_bufferline = false,
			hover = {
				enabled = true,
				delay = 200,
				reveal = { 'close' },
			},

		}
	},
	config = function(_, opts)
		require('bufferline').setup(opts)

		-- fix bufferline when restoring a session
		vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete" }, {
			callback = function()
				vim.schedule(function()
					pcall(nvim_bufferline)
				end)
			end,
		})
	end,
}

return M

