local M = {
	{
		"stevearc/conform.nvim",
		opts = {
			formatters_by_ft = {
				-- Lua
				lua = { "stylua" },

				-- JavaScript/TypeScript
				javascript = { "prettierd", "prettier", stop_after_first = true },
				javascriptreact = { "prettierd", "prettier", stop_after_first = true },
				typescript = { "prettierd", "prettier", stop_after_first = true },
				typescriptreact = { "prettierd", "prettier", stop_after_first = true },

				-- Web
				html = { "prettierd", "prettier", stop_after_first = true },
				css = { "prettierd", "prettier", stop_after_first = true },
				scss = { "prettierd", "prettier", stop_after_first = true },
				less = { "prettierd", "prettier", stop_after_first = true },

				-- Config/Data
				json = { "prettierd", "prettier", stop_after_first = true },
				jsonc = { "prettierd", "prettier", stop_after_first = true },
				yaml = { "prettierd", "prettier", stop_after_first = true },

				-- SQL
				sql = { "sqlfmt" },

				-- Markdown
				markdown = { "prettierd", "prettier", stop_after_first = true },
				["markdown.mdx"] = { "prettierd", "prettier", stop_after_first = true },

				-- GraphQL
				graphql = { "prettierd", "prettier", stop_after_first = true },

				-- Vue/Svelte
				vue = { "prettierd", "prettier", stop_after_first = true },
				svelte = { "prettierd", "prettier", stop_after_first = true },
			},
			default_format_opts = {
				lsp_format = "fallback",
			},
			-- Fixed typo: format_on_save (was forat_on_save)
			format_on_save = {
				timeout_ms = 500,
				lsp_format = "fallback",
			},
		}
	}
}

return M
