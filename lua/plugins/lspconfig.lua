return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts = opts or {}
      opts.servers = opts.servers or {}

      -- Disable the stock tsserver setup in favor of the richer VTSLS experience.
      opts.servers.tsserver = { enabled = false }

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

      return opts
    end,
  },
}
