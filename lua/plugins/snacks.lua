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
				  enabled = true, -- show file icons
				  dir = "󰉋 ",
				  dir_open = "⌄ 󰝰 ",
				  file = " "
				},
				keymaps = {
				  nowait = "󰓅 "
				},
				tree = {
				  vertical = "  ",
				  middle   = "  ",
				  last     = "  ",
				},
				undo = {
				  saved   = " ",
				},
				ui = {
				  live        = "● ",
				  hidden      = "H",
				  ignored     = "I",
				  follow      = "F",
				  selected    = "● ",
				  unselected  = "○ ",
				  -- selected = " ",
				},
				git = {
				  enabled   = true, -- show git icons
				  commit    = "● ", -- used by git log
				  staged    = "A", -- staged changes. always overrides the type icons
				  added     = "A",
				  deleted   = "D",
				  ignored   = "I",
				  modified  = "M",
				  renamed   = "R",
				  unmerged  = "U",
				  untracked = "?",
				},
				diagnostics = {
				  Error = "● ",
				  Warn  = "▲ ",
				  Hint  = "💡 ",
				  Info  = "ⓘ ",
				},
				lsp = {
				  unavailable = "○",
				  enabled = "●",
				  disabled = "○",
				  attached = "● "
				},
				kinds = {
				  Array         = "[] ",
				  Boolean       = "◯ ",
				  Class         = "C ",
				  Color         = "# ",
				  Control       = "⚙ ",
				  Collapsed     = "… ",
				  Constant      = "K ",
				  Constructor   = "⚒ ",
				  Copilot       = "🤖 ",
				  Enum          = "E ",
				  EnumMember    = "e ",
				  Event         = "⚡ ",
				  Field         = "F ",
				  File          = "📄 ",
				  Folder        = "📁 ",
				  Function      = "f ",
				  Interface     = "I ",
				  Key           = "🔑 ",
				  Keyword       = "K ",
				  Method        = "m ",
				  Module        = "M ",
				  Namespace     = "N ",
				  Null          = "∅ ",
				  Number        = "# ",
				  Object        = "{} ",
				  Operator      = "+ ",
				  Package       = "📦 ",
				  Property      = "p ",
				  Reference     = "& ",
				  Snippet       = "<> ",
				  String        = "\" ",
				  Struct        = "S ",
				  Text          = "T ",
				  TypeParameter = "T ",
				  Unit          = "U ",
				  Unknown        = "? ",
				  Value         = "V ",
				  Variable      = "v ",
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
