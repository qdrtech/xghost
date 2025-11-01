
-- vim.opt.nu = true                -- Show absolute line numbers
vim.opt.relativenumber = true    -- Show relative line numbers
-- vim.opt.tabstop = 3              -- Number of spaces per tab
-- vim.opt.softtabstop = 3          -- Number of spaces per tab while editing
-- vim.opt.shiftwidth = 3           -- Number of spaces for each indentation
-- vim.opt.expandtab = false        -- Use tabs instead of spaces
-- vim.smartindent = true           -- Enable smart indentation
-- vim.opt.wrap = false             -- Disable line wrapping
-- vim.opt.hlsearch = false         -- Disable highlight for search matches
-- vim.opt.incsearch = true         -- Enable incremental search
-- vim.opt.swapfile = false         -- Disable swap file creation
-- vim.opt.backup = false           -- Disable backup file creation
-- vim.opt.undofile = true          -- Enable persistent undo
-- vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir" -- Set undo directory (Linux/macOS)
-- vim.opt.undodir = os.getenv("UserProfile") .. /".vim/undodir" -- Set undo directory (Windows)
-- vim.opt.scrolloff = 8            -- Minimum lines to keep above/below cursor
-- vim.opt.signcolumn = "no"        -- Hide sign column (for diagnostics, git, etc.)
-- vim.opt.updatetime = 50          -- Faster completion and CursorHold events
-- vim.opt.termguicolors = true     -- Enable 24-bit RGB color in the terminal
-- vim.g.root_lsp_ignore = { "copilot" } -- Ignore Copilot in root LSP setup

-- Minimal Neovim options with comments:

vim.opt.encoding = "utf-8"      -- Set default encoding to UTF-8
vim.opt.fileencoding = "utf-8"  -- File encoding used for written files
vim.opt.compatible = false      -- Disable Vi compatibility for better Neovim experience


