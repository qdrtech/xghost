local M = {
   {
      "williamboman/mason.nvim",
      opts = { 
			ensure_installed = { 
				"prettier",
				"stylua",
				"shellcheck",
				"shfmt",
				"flake8",
			},
		}
   }
}


return M
