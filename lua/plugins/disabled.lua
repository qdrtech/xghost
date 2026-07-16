-- Disable LazyVim default plugins that aren't in our curated set.
-- Add more as: { "owner/repo", enabled = false }. Delete a line to re-enable.
--
-- KEPT on purpose (deps/infra — do NOT disable here):
--   plenary.nvim (telescope dep), nvim-web-devicons (bufferline/oil dep),
--   mini.icons (UI icon provider), mason-lspconfig.nvim (LSP auto-enable),
--   lazydev.nvim (nvim-cmp source for editing this config).
-- Completion engine is switched to nvim-cmp via the extra imported in
-- config/lazy.lua, which also disables blink.cmp for us.
local M = {
	-- UI / session
	{ "nvim-neo-tree/neo-tree.nvim", enabled = false }, -- we use oil + snacks explorer
	{ "MunifTanjim/nui.nvim", enabled = false }, -- only needed by neo-tree/noice
	{ "folke/noice.nvim", enabled = false },
	{ "folke/persistence.nvim", enabled = false },

	-- Editor extras
	{ "folke/flash.nvim", enabled = false },
	{ "folke/which-key.nvim", enabled = false },
	{ "folke/trouble.nvim", enabled = false },
	{ "folke/todo-comments.nvim", enabled = false },
	{ "lewis6991/gitsigns.nvim", enabled = false },
	{ "MagicDuck/grug-far.nvim", enabled = false },

	-- Editing sugar
	{ "nvim-mini/mini.ai", enabled = false },
	{ "nvim-mini/mini.pairs", enabled = false },
	{ "folke/ts-comments.nvim", enabled = false },
	{ "windwp/nvim-ts-autotag", enabled = false },
	{ "nvim-treesitter/nvim-treesitter-textobjects", enabled = false },

	-- Picker (we use telescope)
	{ "ibhagwan/fzf-lua", enabled = false },
}

return M
