local M = {
   {
      "williamboman/mason.nvim",
      opts = {
			ensure_installed = {
				-- Formatters & Linters
				"prettierd",                    -- Fast Prettier daemon (preferred)
				"prettier",                     -- Fallback formatter
				"stylua",
				"shellcheck",                   -- Shell linter (driven by nvim-lint)
				"shfmt",

				-- Language Servers
				"typescript-language-server",  -- TypeScript/JavaScript
				"vtsls",                        -- Alternative TS server
				"gopls",                        -- Go
				"pyright",                      -- Python type checking
				"ruff",                         -- Python lint + format + import sorting (LSP)
			},
		}
   }
}


return M
