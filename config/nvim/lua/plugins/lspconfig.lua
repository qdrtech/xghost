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
		opts.servers.gopls = vim.tbl_deep_extend("force", opts.servers.gopls or {}, {
			settings = {
				gopls = {
					gofumpt = true,
					usePlaceholders = true,
					completeUnimported = true,
					staticcheck = true,
					semanticTokens = true,
					analyses = {
						nilness = true,
						unusedparams = true,
						unusedwrite = true,
						useany = true,
					},
					hints = {
						assignVariableTypes = true,
						compositeLiteralFields = true,
						compositeLiteralTypes = true,
						constantValues = true,
						functionTypeParameters = true,
						parameterNames = true,
						rangeVariableTypes = true,
					},
					codelenses = {
						gc_details = false,
						generate = true,
						regenerate_cgo = true,
						run_govulncheck = true,
						test = true,
						tidy = true,
						upgrade_dependency = true,
						vendor = true,
					},
					directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
				},
			},
		})

		-- Python: pyright for types, ruff for lint/format/imports
		opts.servers.pyright = opts.servers.pyright or {}
		opts.servers.ruff = opts.servers.ruff or {}

		return opts
	end,
}

return M
