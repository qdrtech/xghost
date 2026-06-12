local M = {
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPost", "BufWritePost", "InsertLeave" },
		config = function()
			local lint = require("lint")

			-- Python lint/format is handled by the ruff LSP; nvim-lint covers shell.
			lint.linters_by_ft = {
				sh = { "shellcheck" },
				bash = { "shellcheck" },
			}

			local group = vim.api.nvim_create_augroup("nvim-lint", { clear = true })
			vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
				group = group,
				callback = function()
					-- Only lint if a linter is configured for this filetype.
					if next(lint.linters_by_ft[vim.bo.filetype] or {}) ~= nil then
						lint.try_lint()
					end
				end,
			})
		end,
	},
}

return M
