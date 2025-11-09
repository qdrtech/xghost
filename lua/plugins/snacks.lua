return {
	"folke/snacks.nvim",
	opts = {
		dashboard = {
			preset = {
				pick = function(cmd, opts)
					return LazyVim.pick(cmd, opts)()
				end,
				header = [[
        ██╗      █████╗ ███████╗██╗   ██╗██╗   ██╗██╗███╗   ███╗          Z
        ██║     ██╔══██╗╚══███╔╝╚██╗ ██╔╝██║   ██║██║████╗ ████║      Z    
        ██║     ███████║  ███╔╝  ╚████╔╝ ██║   ██║██║██╔████╔██║   z       
        ██║     ██╔══██║ ███╔╝    ╚██╔╝  ╚██╗ ██╔╝██║██║╚██╔╝██║ z         
        ███████╗██║  ██║███████╗   ██║    ╚████╔╝ ██║██║ ╚═╝ ██║           
        ╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝     ╚═══╝  ╚═╝╚═╝     ╚═╝           
 ]],
			},
		},
		notifier = { enabled = true },

		-- VSCode-style explorer configuration
		picker = {
			-- Global picker formatting for VSCode style
			formatters = {
				file = {
					-- Show the path (dir + file) instead of repeating the folder name first
					filename_first = true,
					filename_only = false,
				},
			},
			icons = {
				files = {
					enabled = true, -- hide folder/file glyphs so the path stands alone
				},
			},
			sources = {
				explorer = {
					-- Layout: VSCode sidebar style on the left
					layout = {
						preset = "sidebar",
						preview = false, -- Disable preview (like VSCode sidebar)
						layout = {
							position = "left", -- Position on left side
							width = 0.25, -- 25% of screen width
						},
					},
					-- File visibility
					hidden = true, -- Show hidden files like .env
					ignored = false, -- Hide git-ignored files (like VSCode default)
					exclude = { "node_modules", ".git" },
					-- Explorer behavior
					follow_file = true, -- Auto-reveal active file (like VSCode)
					auto_close = false, -- Keep explorer open after selecting file
					focus = "list", -- Focus on file list, not search input
					-- Window configuration
					win = {
						list = {
							keys = {},
						},
					},
				},
			},
		},
	},
}
