-- The theme bridge of the xghost Neovim bundle.
--
-- This file is prescribed configuration. The project owns it, and 'xghost
-- config link' symlinks the directory that holds it to ~/.config/nvim. Do not
-- edit it: an edit dirties the checkout and conflicts on the next pull. See
-- docs/adr/0001-prescribed-config-architecture.md.
--
-- It reads the palette of the active theme out of the generated output and
-- applies it to the highlight groups named at the bottom. The colours are not
-- here. They are in the generated file this reads, so a theme switch rewrites
-- that file and never this one.
--
-- Three things about this file are measured rather than assumed, and each one
-- is recorded in docs/bundles/neovim.md.
--
-- THE PATH IS BUILT LEXICALLY, WITH NO '..'.
--   Every other bundle of this project reaches the generated output with
--   '../xghost-generated/<app>/<file>', relative to the prescribed file. That
--   form is wrong here. 'xghost config link' makes ~/.config/nvim a symbolic
--   link into the checkout, and the kernel applies a '..' physically: it
--   follows that link first and then goes up, which lands in the checkout and
--   not in the config directory. The bridge is not there. Lua can take the
--   parent directory as text instead, which is what ':h' does below, so this
--   bundle never writes a '..' at all. It is the same fault Rofi has, and
--   docs/adr/0002-the-bridge-to-the-generated-output.md records both.
--
-- THE FILE IS LOADED WITH 'loadfile', NOT WITH 'require' AND NOT WITH 'dofile'.
--   'require' and 'dofile' both raise when the file is not there, and an error
--   raised in init.lua stops init.lua: every line after it is skipped. A user
--   who has not run 'xghost theme set' yet would get an editor with no
--   keybindings and no options. 'loadfile' returns nil and a message instead,
--   so a missing palette costs one warning and nothing else.
--
-- THE HIGHLIGHTS ARE APPLIED ON 'ColorScheme', NOT ONCE.
--   The configuration beside this file loads LazyVim, which loads a
--   colourscheme plugin, and loading a colourscheme clears every highlight
--   group first. Whatever this file set before that would be gone. The
--   autocommand below runs after each colourscheme, so the palette of the
--   active theme is applied last whichever colourscheme is in use.
--
-- THE WARNING GOES THROUGH 'nvim_echo', NOT THROUGH 'vim.notify'.
--   'vim.notify' is a variable, and a plugin may replace it. snacks.nvim,
--   which LazyVim loads, replaces it before init.lua reaches the line that
--   calls this file, and the replacement drops the message: measured with the
--   generated palette absent, the warning reached neither the message history
--   nor standard error. That is the silence this project refuses. 'nvim_echo'
--   is an API function rather than a variable, so nothing can stand in front
--   of it, and its second argument puts the line in ':messages' for a user who
--   was not looking when it was printed.

local M = {}

-- Where 'xghost config link' puts the bridge to the generated output.
M.RELATIVE_PATH = "xghost-generated/nvim/colors.lua"

-- The name of the autocommand group, so that sourcing this file twice leaves
-- one autocommand rather than two.
local GROUP = "XghostTheme"

-- The path of the generated palette.
--
-- 'stdpath("config")' is the config directory of Neovim as it was opened, which
-- is '$XDG_CONFIG_HOME/nvim'. It is not resolved, so its parent as text is
-- '$XDG_CONFIG_HOME', which is where the bridge is. Both ends of the path
-- therefore follow the environment, which is what the bridge exists for.
function M.palette_path()
	local parent = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h")
	return parent .. "/" .. M.RELATIVE_PATH
end

-- Read the generated palette.
--
-- Returns the table on success. Returns nil and one sentence otherwise, and the
-- caller reports it. Nothing here raises, because this runs from init.lua.
function M.read_palette(path)
	local chunk, message = loadfile(path)
	if not chunk then
		return nil, message
	end

	local ok, palette = pcall(chunk)
	if not ok then
		return nil, tostring(palette)
	end
	if type(palette) ~= "table" then
		return nil, path .. ": the generated palette is a " .. type(palette) .. ", not a table"
	end

	return palette
end

-- The highlight groups this bundle owns, and the palette name each one takes.
--
-- This list is the whole of what the theme reaches. A group that is not here
-- keeps the colour the colourscheme gave it, which is the honest half of this
-- bundle: the chrome of the editor follows the desktop theme and the syntax
-- colours stay with the colourscheme. docs/bundles/neovim.md records why.
function M.highlights(c)
	return {
		Normal = { fg = c.text, bg = c.bg },
		NormalFloat = { fg = c.text, bg = c.surface },
		FloatBorder = { fg = c.accent, bg = c.surface },
		FloatTitle = { fg = c.accent, bg = c.surface, bold = true },
		SignColumn = { bg = c.bg },
		ColorColumn = { bg = c.surface },
		CursorLine = { bg = c.surface },
		CursorLineNr = { fg = c.accent, bold = true },
		LineNr = { fg = c.text_muted },
		Visual = { bg = c.surface },
		WinSeparator = { fg = c.surface },
		StatusLine = { fg = c.text, bg = c.surface },
		StatusLineNC = { fg = c.text_muted, bg = c.surface_alt },
		TabLine = { fg = c.text_muted, bg = c.surface_alt },
		TabLineSel = { fg = c.text, bg = c.surface },
		TabLineFill = { bg = c.surface_alt },
		Pmenu = { fg = c.text, bg = c.surface },
		PmenuSel = { fg = c.bg, bg = c.accent },
		PmenuSbar = { bg = c.surface_alt },
		PmenuThumb = { bg = c.text_muted },
		Search = { fg = c.bg, bg = c.accent_alt },
		IncSearch = { fg = c.bg, bg = c.warn },
		CurSearch = { fg = c.bg, bg = c.warn },
		Comment = { fg = c.text_muted, italic = true },
		Directory = { fg = c.accent },
		Title = { fg = c.accent, bold = true },
		Question = { fg = c.success },
		MoreMsg = { fg = c.success },
		ErrorMsg = { fg = c.error },
		WarningMsg = { fg = c.warn },
		DiagnosticError = { fg = c.error },
		DiagnosticWarn = { fg = c.warn },
		DiagnosticInfo = { fg = c.accent },
		DiagnosticHint = { fg = c.accent_alt },
		DiagnosticOk = { fg = c.success },
		DiffAdd = { fg = c.success },
		DiffChange = { fg = c.warn },
		DiffDelete = { fg = c.error },
	}
end

-- Apply one palette to the highlight groups above.
--
-- A palette name the generated file does not carry leaves every group that
-- names it alone, and is reported. A colour is never invented here: a group
-- with half a definition would be worse than the one the colourscheme gave it.
function M.apply(palette)
	local missing = {}
	for _, name in ipairs({
		"bg",
		"surface",
		"surface_alt",
		"text",
		"text_muted",
		"accent",
		"accent_alt",
		"warn",
		"error",
		"success",
	}) do
		if type(palette[name]) ~= "string" or not palette[name]:match("^#%x%x%x%x%x%x$") then
			missing[#missing + 1] = name
		end
	end
	if #missing > 0 then
		return false, "the generated palette has no '#rrggbb' value for: " .. table.concat(missing, ", ")
	end

	for group, definition in pairs(M.highlights(palette)) do
		vim.api.nvim_set_hl(0, group, definition)
	end
	return true
end

-- Print one warning, and keep it in ':messages'.
--
-- The call is scheduled, so the line is printed once the editor is up rather
-- than in the middle of startup, where a long message asks the user to press
-- ENTER before the first buffer appears.
function M.report(problem)
	local line = "xghost: " .. problem
	vim.schedule(function()
		vim.api.nvim_echo({ { line, "WarningMsg" } }, true, {})
	end)
end

-- Read the palette and apply it, now and after every colourscheme.
--
-- A problem is reported once, at startup, and never from inside the
-- autocommand: a warning on every colourscheme change would be a warning on
-- every ':colorscheme'.
function M.setup()
	local palette, message = M.read_palette(M.palette_path())
	if not palette then
		M.report(
			"the generated palette was not read, so the editor keeps the colours of its colourscheme; "
				.. "run 'xghost theme set <name>' to write it: "
				.. message
		)
		return false
	end

	local ok, problem = M.apply(palette)
	if not ok then
		M.report(problem)
		return false
	end

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup(GROUP, { clear = true }),
		desc = "Re-apply the xghost theme palette over the colourscheme that just loaded.",
		callback = function()
			local reread = M.read_palette(M.palette_path())
			if reread then
				M.apply(reread)
			end
		end,
	})

	return true
end

return M
