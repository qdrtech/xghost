local M = {
   {
      "williamboman/mason.nvim",
      opts = {
			ensure_installed = {
				-- Formatters & Linters
				"prettierd",                    -- Fast Prettier daemon (preferred)
				"prettier",                     -- Fallback formatter
				"stylua",
				"shellcheck",
				"shfmt",
				"flake8",

				-- Language Servers
				"typescript-language-server",  -- TypeScript/JavaScript
				"vtsls",                        -- Alternative TS server
				"gopls",                        -- Go
				"omnisharp",                    -- C#
			},
		}
   }
}


return M
