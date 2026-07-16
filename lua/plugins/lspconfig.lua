local M = {
	"neovim/nvim-lspconfig",
	opts = function(_, opts)
		opts = opts or {}
		opts.servers = opts.servers or {}

		-- Disable the stock tsserver setup in favor of the richer VTSLS experience.
		opts.servers.tsserver = false

		local inlay_hints = {
			includeInlayParameterNameHints = "all",
			includeInlayParameterNameHintsWhenArgumentMatchesName = false,
			includeInlayFunctionParameterTypeHints = true,
			includeInlayVariableTypeHints = true,
			includeInlayPropertyDeclarationTypeHints = true,
			includeInlayFunctionLikeReturnTypeHints = true,
			includeInlayEnumMemberValueHints = true,
		}

		opts.servers.vtsls = vim.tbl_deep_extend("force", opts.servers.vtsls or {}, {
			settings = {
				vtsls = {
					enableMoveToFileCodeAction = true,
					experimental = {
						completion = { enableServerSideFuzzyMatch = true },
					},
				},
				typescript = {
					inlayHints = inlay_hints,
					suggest = {
						completeFunctionCalls = true,
						includeCompletionsForModuleExports = true,
						includeCompletionsWithSnippetText = true,
					},
					preferences = {
						includeCompletionsForImportStatements = true,
						includeAutomaticOptionalChainCompletions = true,
						includeCompletionsWithInsertText = true,
					},
				},
				javascript = {
					inlayHints = inlay_hints,
					suggest = {
						completeFunctionCalls = true,
						includeCompletionsForModuleExports = true,
						includeCompletionsWithSnippetText = true,
					},
					preferences = {
						includeCompletionsForImportStatements = true,
						includeAutomaticOptionalChainCompletions = true,
						includeCompletionsWithInsertText = true,
					},
				},
			},
		})

		-- Go
		opts.servers.gopls = opts.servers.gopls or {}

		-- Python: pyright for types, ruff for lint/format/imports
		opts.servers.pyright = opts.servers.pyright or {}
		opts.servers.ruff = opts.servers.ruff or {}

		return opts
	end,
}

return M
