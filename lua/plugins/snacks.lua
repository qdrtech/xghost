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
					filename_first = true, -- Show filename before path (like VSCode)
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