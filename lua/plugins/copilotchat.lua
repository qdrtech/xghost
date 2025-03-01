return {
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		dependencies = {
			{ "github/copilot.vim" }, -- or zbirenbaum/copilot.lua
			{ "nvim-lua/plenary.nvim", branch = "master" }, -- for curl, log and async functions
		},
		build = "make tiktoken", -- Only on MacOS or Linux
		opts = {
			-- See Configuration section for options
		},
		cmd = {
			"CopilotChat",
			"CopilotChatToggle",
			"CopilotChatOpen",
			"CopilotChatClose",
			"CopilotChatExplain",
			"CopilotChatTests",
			"CopilotChatFix",
			"CopilotChatOptimize",
			"CopilotChatDocs",
			"CopilotChatCommit",
		},
		keys = {
			{ "<leader>cc", "<cmd>CopilotChatToggle<cr>", desc = "Toggle Copilot Chat" },
			{ "<leader>ce", "<cmd>CopilotChatExplain<cr>", desc = "Explain Code" },
			{ "<leader>ct", "<cmd>CopilotChatTests<cr>", desc = "Generate Tests" },
			{ "<leader>cf", "<cmd>CopilotChatFix<cr>", desc = "Fix Code" },
			{ "<leader>co", "<cmd>CopilotChatOptimize<cr>", desc = "Optimize Code" },
		},
	},
}
