#!/usr/bin/env bats
#
# Tests for the Neovim bundle: the prescribed configuration under config/nvim,
# which is imported from the repository the maintainer kept it in, and the
# template under templates/nvim.
#
# Neovim is the first bundle of this project whose configuration is a
# programming language, and three things follow from that. Each one is measured
# here rather than reasoned about, because each one behaves against the way the
# rest of the project reads.
#
#   - The relative include every other bundle writes, '../xghost-generated/…',
#     does not work here. 'xghost config link' makes ~/.config/nvim a symbolic
#     link, and a '..' is applied by the kernel after that link is followed, so
#     the path lands in the checkout instead of the config directory. The
#     prescribed Lua takes the parent directory as text instead.
#   - A missing generated file is not a dropped include. 'require' and 'dofile'
#     both raise, and an error raised in init.lua stops init.lua, so the editor
#     comes up with none of its options and none of its keybindings.
#   - A colourscheme clears every highlight group when it loads, so a palette
#     applied once is a palette a later colourscheme wipes.
#
# NO TEST HERE STARTS THE REAL init.lua. That file loads LazyVim, which clones
# plugins from the network on first start and writes a data directory of
# hundreds of megabytes. Every test that runs Neovim runs it with '-u' against
# a fixture written by that test, and Neovim still puts the linked config
# directory on its 'runtimepath', so the fixture reaches the prescribed Lua by
# the same 'require' the real init.lua uses. What that leaves unproved is
# recorded in docs/bundles/neovim.md.
#
# The design of the bundle is recorded in docs/bundles/neovim.md.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	PRESCRIBED_DIR="$ROOT_DIR/config/nvim"
	INIT_FILE="$PRESCRIBED_DIR/init.lua"
	LOADER_FILE="$PRESCRIBED_DIR/lua/config/xghost.lua"
	TEMPLATE_FILE="$ROOT_DIR/templates/nvim/colors.lua"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR
	unset XGHOST_CONFIG_SOURCE
	unset XGHOST_ROOT
	unset XGHOST_THEMES_DIR
	unset XGHOST_TEMPLATE_DIR

	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XDG_DATA_HOME="$HOME/.local/share"
	export XDG_CACHE_HOME="$HOME/.cache"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

	use_fixed_machine_facts
	use_own_knobs

	GENERATED="$XDG_STATE_HOME/xghost/generated"

	# The name 'xghost config link' gives the generated output inside the
	# config directory.
	BRIDGE_NAME=xghost-generated

	# The relative path the prescribed Lua joins to the config directory.
	PALETTE_RELATIVE="$BRIDGE_NAME/nvim/colors.lua"
}

# Link the prescribed configuration of the checkout into the config directory.
link_prescribed() {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config link
}

# Print the value one theme declares for one palette name.
palette_value() {
	local theme=$1 name=$2
	sed -n "s/^$name=//p" "$ROOT_DIR/themes/$theme/palette.conf"
}

# Print the text of a file with its Lua comment lines dropped.
#
# Every comment in the two Lua files of this bundle is a whole line, which one
# test below asserts on its own, so dropping the lines that start with '--'
# leaves the code.
lua_code() {
	grep -v '^[[:space:]]*--' "$1"
}

# Stop a test that needs Neovim, or fail when the runner promised one.
#
# XGHOST_REQUIRE_NVIM turns the skip into a failure. Continuous integration
# installs Neovim and sets it, so a skip there means the install step stopped
# working and the measurement quietly stopped running. It is the shape
# tests/swaync.bats uses for the GTK4 bindings.
require_nvim() {
	if command -v nvim >/dev/null 2>&1; then
		NVIM=$(command -v nvim)
		return 0
	fi
	if [ -n "${XGHOST_REQUIRE_NVIM:-}" ]; then
		printf 'nvim is not on PATH and XGHOST_REQUIRE_NVIM is set\n' >&2
		return 1
	fi
	skip "nvim is not installed, so what the editor does cannot be measured"
}

# Run Neovim against a fixture, in the sandbox of this test and nowhere else.
#
#   run_nvim FIXTURE [ARGUMENT…]
#
# 'env -i' is what keeps every XDG variable of the person running the suite out
# of the run: a single 'export A=x B=$A' would read the old value of A, which is
# how a worker of this project once wrote into a real dotfile. Each variable
# below is given its sandbox value explicitly.
run_nvim() {
	local fixture=$1
	shift
	env -i \
		HOME="$HOME" \
		TERM=dumb \
		PATH=/usr/bin:/bin \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		XDG_STATE_HOME="$XDG_STATE_HOME" \
		XDG_DATA_HOME="$XDG_DATA_HOME" \
		XDG_CACHE_HOME="$XDG_CACHE_HOME" \
		"$NVIM" --headless -u "$fixture" "$@" +qa
}

# Write a fixture that loads the prescribed Lua and reports through a file.
#
# The report goes to a file rather than to standard output, because Neovim
# writes 'print' to standard error in headless mode and a test that read the
# wrong stream would pass on an empty string.
fixture() {
	local path=$1
	cat >"$path"
}

# Print '#RRGGBB' for one highlight group, read out of the running editor.
#
# This is the read-back rule of docs/adr/0002-the-bridge-to-the-generated-output.md:
# assert on the state the application holds after it has read every file, never
# on the code it exited with. An unthemed editor exits 0.
highlight_report() {
	local fixture_lua=$BATS_TEST_TMPDIR/highlight.lua
	local out=$BATS_TEST_TMPDIR/highlight.txt
	rm -f "$out"
	fixture "$fixture_lua" <<-EOF
		$1
		local out = assert(io.open("$out", "w"))
		local function hex(n) return n and string.format("#%06X", n) or "none" end
		local function show(name)
		  local h = vim.api.nvim_get_hl(0, { name = name })
		  out:write(name .. " fg=" .. hex(h.fg) .. " bg=" .. hex(h.bg) .. "\n")
		end
		$2
		out:close()
	EOF
	run_nvim "$fixture_lua" >/dev/null 2>&1 || true
	cat "$out"
}

#
# The import: the configuration is a directory of this repository.
#

@test "the Neovim configuration is a plain directory and not a submodule" {
	[ -f "$INIT_FILE" ]
	[ ! -e "$ROOT_DIR/.gitmodules" ]

	# A submodule is a tree entry of mode 160000. Not one may exist anywhere.
	run git -C "$ROOT_DIR" ls-files --stage
	[ "$status" -eq 0 ]
	[[ $output != *"160000"* ]]
}

@test "every file of the imported configuration is tracked by this repository" {
	local file
	for file in init.lua lua/config/lazy.lua lua/config/opts.lua \
		lua/config/keybindings.lua lua/config/xghost.lua lazy-lock.json; do
		[ -f "$PRESCRIBED_DIR/$file" ] || {
			printf 'the imported configuration has no %s\n' "$file" >&2
			return 1
		}
		run git -C "$ROOT_DIR" ls-files --error-unmatch "config/nvim/$file"
		[ "$status" -eq 0 ]
	done
}

@test "no file of the Neovim bundle names the private repository it came from" {
	# Acceptance criterion 3: a clean clone needs no SSH access to any private
	# repository. A prescribed file that still fetched from 'xghost-config'
	# would put that access back.
	run grep -rn -e 'xghost-config' -e 'git@github.com' "$PRESCRIBED_DIR"
	[ "$status" -ne 0 ]
}

@test "the history of the imported configuration is in this repository" {
	# 'git subtree add' without '--squash' merges the source history, so the
	# commit the import was taken from is an ancestor of this branch. A squash
	# would drop it, and acceptance criterion 2 asks for it.
	if [ "$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository)" = "true" ]; then
		skip "the checkout is shallow, so no history older than HEAD is here"
	fi
	run git -C "$ROOT_DIR" merge-base --is-ancestor \
		9d693d8368bcd0b861dfafce3a1ed02a6de9a887 HEAD
	[ "$status" -eq 0 ]
}

#
# Linking: 'xghost config link' places the configuration.
#

@test "'xghost config link' places the Neovim configuration" {
	run link_prescribed
	[ "$status" -eq 0 ]
	[ -L "$XDG_CONFIG_HOME/nvim" ]
	[ "$(readlink "$XDG_CONFIG_HOME/nvim")" = "$PRESCRIBED_DIR" ]
	[ -f "$XDG_CONFIG_HOME/nvim/init.lua" ]
}

@test "'xghost config unlink' removes the Neovim configuration" {
	link_prescribed
	[ -L "$XDG_CONFIG_HOME/nvim" ]
	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ ! -e "$XDG_CONFIG_HOME/nvim" ]
	# Removing a link never touches what it pointed at.
	[ -f "$INIT_FILE" ]
}

#
# The include path: this bundle reaches the bridge without a '..'.
#

@test "the prescribed Lua writes no '..' path" {
	# The one rule this bundle does not share with the others. A '..' is
	# applied by the kernel after ~/.config/nvim is followed, so it lands in
	# the checkout. The test below measures that; this one keeps the form out
	# of the file.
	# '..' is also the concatenation operator of Lua, so the assertion is about
	# a '..' inside a path: a segment that follows a slash, or a quoted one.
	run lua_code "$LOADER_FILE"
	[ "$status" -eq 0 ]
	[[ $output != *"/.."* ]]
	[[ $output != *'".."'* ]]
	[[ $output != *"../"* ]]
}

@test "the prescribed Lua names the bridge the linker creates" {
	run lua_code "$LOADER_FILE"
	[ "$status" -eq 0 ]
	[[ $output == *"$BRIDGE_NAME/nvim/colors.lua"* ]]
}

@test "the prescribed Lua names no path under the state directory" {
	# The fault docs/adr/0002-the-bridge-to-the-generated-output.md exists to
	# prevent: a path that is right only while XDG_STATE_HOME holds its default.
	run lua_code "$LOADER_FILE"
	[ "$status" -eq 0 ]
	[[ $output != *".local/state"* ]]
	[[ $output != *"XDG_STATE_HOME"* ]]
}

@test "the path the prescribed Lua computes is the bridge, and the palette is there" {
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight

	local out=$BATS_TEST_TMPDIR/path.txt
	fixture "$BATS_TEST_TMPDIR/path.lua" <<-EOF
		local m = require("config.xghost")
		local path = m.palette_path()
		local out = assert(io.open("$out", "w"))
		out:write(path .. "\n")
		out:write(tostring(vim.fn.filereadable(path) == 1) .. "\n")
		out:close()
	EOF
	run_nvim "$BATS_TEST_TMPDIR/path.lua" >/dev/null 2>&1 || true

	run cat "$out"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "$XDG_CONFIG_HOME/$PALETTE_RELATIVE" ]
	[ "${lines[1]}" = "true" ]
}

@test "a '..' path from the config directory reaches the checkout and not the bridge" {
	# The recorded behaviour of the kernel, and the reason this bundle differs
	# from every other one. It is the same fault Rofi has.
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight

	local out=$BATS_TEST_TMPDIR/dotdot.txt
	fixture "$BATS_TEST_TMPDIR/dotdot.lua" <<-EOF
		local config = vim.fn.stdpath("config")
		local dotdot = config .. "/../$PALETTE_RELATIVE"
		local lexical = vim.fn.fnamemodify(config, ":h") .. "/$PALETTE_RELATIVE"
		local out = assert(io.open("$out", "w"))
		out:write("dotdot=" .. tostring(vim.fn.filereadable(dotdot) == 1) .. "\n")
		out:write("lexical=" .. tostring(vim.fn.filereadable(lexical) == 1) .. "\n")
		out:close()
	EOF
	run_nvim "$BATS_TEST_TMPDIR/dotdot.lua" >/dev/null 2>&1 || true

	run cat "$out"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "dotdot=false" ]
	[ "${lines[1]}" = "lexical=true" ]
}

@test "the checkout holds no config/xghost-generated" {
	# The rule of docs/adr/0002-the-bridge-to-the-generated-output.md. A
	# directory of that name under the real path is what Ghostty would read in
	# place of the bridge, and it is what a '..' from config/nvim would find.
	[ ! -e "$ROOT_DIR/config/$BRIDGE_NAME" ]
}

#
# The render: the template writes the palette of the active theme.
#

@test "every theme renders a Neovim palette" {
	local theme
	for theme in $("$XGHOST" theme list); do
		"$XGHOST" theme set "$theme"
		[ -f "$GENERATED/nvim/colors.lua" ] || {
			printf 'theme %s rendered no Neovim palette\n' "$theme" >&2
			return 1
		}
	done
}

@test "the rendered palette holds the colours the theme declares" {
	# The assertion is the whole assignment line, not the value somewhere in
	# the file. Two names of a palette may carry one colour: SURFACE_ALT and BG
	# are the same in both shipped themes, so a template that wrote one of them
	# under the other name would pass a test that only looked for the value.
	local theme name key value
	for theme in $("$XGHOST" theme list); do
		"$XGHOST" theme set "$theme"
		for name in BG SURFACE SURFACE_ALT TEXT TEXT_MUTED ACCENT ACCENT_ALT WARN ERROR SUCCESS; do
			value=$(palette_value "$theme" "$name")
			[ -n "$value" ] || {
				printf 'theme %s declares no %s\n' "$theme" "$name" >&2
				return 1
			}
			key=${name,,}
			grep -qE "^[[:space:]]*$key = \"$value\",$" "$GENERATED/nvim/colors.lua" || {
				printf 'the palette of %s has no line "%s = \"%s\"," :\n' "$theme" "$key" "$value" >&2
				cat "$GENERATED/nvim/colors.lua" >&2
				return 1
			}
		done
	done
}

@test "a theme switch rewrites the Neovim palette" {
	"$XGHOST" theme set tokyonight
	local first
	first=$(cat "$GENERATED/nvim/colors.lua")
	"$XGHOST" theme set macos-dark
	local second
	second=$(cat "$GENERATED/nvim/colors.lua")
	[ "$first" != "$second" ]
	[[ $second == *"$(palette_value macos-dark BG)"* ]]
}

@test "no knob reaches the Neovim bundle" {
	# Rendered here at two knob sets rather than read out of the committed
	# golden output, so the assertion is about the template and not about two
	# files that were written together. Every knob differs between the two sets.
	#
	# The claim is the one docs/bundles/neovim.md makes: none of the four knobs
	# is a setting of the editor. The compositor animates, the compositor spaces
	# the windows, the terminal draws the glyphs, and the bar has an edge.
	local first second first_bar second_bar
	"$XGHOST" theme set tokyonight
	first=$(cat "$GENERATED/nvim/colors.lua")
	first_bar=$(cat "$GENERATED/waybar/knobs.css")

	cp "$ROOT_DIR/tests/fixtures/knobs/alternate.conf" "$XGHOST_KNOBS_FILE"
	"$XGHOST" theme set tokyonight
	second=$(cat "$GENERATED/nvim/colors.lua")
	second_bar=$(cat "$GENERATED/waybar/knobs.css")

	# The second knob set really did reach the output. Without this line, a
	# render that never read the knobs file at all would pass, and the test
	# would say nothing about Neovim.
	[ "$first_bar" != "$second_bar" ]

	[ "$first" = "$second" ]
}

@test "the template holds no colour of its own" {
	# Every colour of the generated file has to come from the palette, so the
	# template names placeholders and no '#rrggbb' literal.
	run grep -n '#[0-9a-fA-F]\{6\}' "$TEMPLATE_FILE"
	[ "$status" -ne 0 ]
}

#
# The generated palette is missing: the editor must not break, and must not be
# silent.
#

@test "a missing palette leaves the rest of init.lua running" {
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight
	rm -f "$(readlink -f "$GENERATED")/nvim/colors.lua"

	local out=$BATS_TEST_TMPDIR/after.txt
	fixture "$BATS_TEST_TMPDIR/after.lua" <<-EOF
		require("config.xghost").setup()
		local reached_the_end = true
		local out = assert(io.open("$out", "w"))
		out:write(tostring(reached_the_end) .. "\n")
		out:close()
	EOF
	run_nvim "$BATS_TEST_TMPDIR/after.lua" >/dev/null 2>&1 || true

	run cat "$out"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "true" ]
}

@test "a missing palette is reported on standard error" {
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight
	rm -f "$(readlink -f "$GENERATED")/nvim/colors.lua"

	fixture "$BATS_TEST_TMPDIR/warn.lua" <<-'EOF'
		require("config.xghost").setup()
	EOF
	run -0 --separate-stderr run_nvim "$BATS_TEST_TMPDIR/warn.lua"
	[[ $stderr == *"xghost: the generated palette was not read"* ]]
	[[ $stderr == *"xghost theme set"* ]]
}

@test "a missing palette is kept in the message history" {
	# Standard error is what a headless run sees. A user sees the message area,
	# and looks in ':messages' afterwards. Both have to hold it, because
	# 'vim.notify' is a variable a plugin may replace and this bundle's
	# configuration loads one that does.
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight
	rm -f "$(readlink -f "$GENERATED")/nvim/colors.lua"

	local out=$BATS_TEST_TMPDIR/messages.txt
	fixture "$BATS_TEST_TMPDIR/messages.lua" <<-EOF
		require("config.xghost").setup()
		vim.defer_fn(function()
		  local m = vim.api.nvim_exec2("messages", { output = true }).output
		  local out = assert(io.open("$out", "w"))
		  out:write(tostring(m:find("xghost: the generated palette", 1, true) ~= nil) .. "\n")
		  out:close()
		end, 200)
	EOF
	run_nvim "$BATS_TEST_TMPDIR/messages.lua" '+sleep 1' >/dev/null 2>&1 || true

	run cat "$out"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "true" ]
}

@test "'dofile' of a missing palette would stop the rest of init.lua" {
	# The recorded behaviour of Lua and of Neovim, and the reason the prescribed
	# file uses 'loadfile'. No change to this project can make 'dofile' do
	# something else; tests/negative-control mutates the assertion instead.
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight
	rm -f "$(readlink -f "$GENERATED")/nvim/colors.lua"

	local out=$BATS_TEST_TMPDIR/dofile.txt
	rm -f "$out"
	fixture "$BATS_TEST_TMPDIR/dofile.lua" <<-EOF
		dofile(vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h") .. "/$PALETTE_RELATIVE")
		local out = assert(io.open("$out", "w"))
		out:write("the rest of the file ran\n")
		out:close()
	EOF
	run_nvim "$BATS_TEST_TMPDIR/dofile.lua" >/dev/null 2>&1 || true

	[ ! -f "$out" ]
}

@test "'require' of a missing palette would stop the rest of init.lua" {
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight
	rm -f "$(readlink -f "$GENERATED")/nvim/colors.lua"

	local out=$BATS_TEST_TMPDIR/require.txt
	rm -f "$out"
	fixture "$BATS_TEST_TMPDIR/require.lua" <<-EOF
		package.path = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h")
		  .. "/$BRIDGE_NAME/nvim/?.lua;" .. package.path
		require("colors")
		local out = assert(io.open("$out", "w"))
		out:write("the rest of the file ran\n")
		out:close()
	EOF
	run_nvim "$BATS_TEST_TMPDIR/require.lua" >/dev/null 2>&1 || true

	[ ! -f "$out" ]
}

@test "a generated palette that is not a table is reported and the editor runs on" {
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight
	printf 'return 7\n' >"$(readlink -f "$GENERATED")/nvim/colors.lua"

	local out=$BATS_TEST_TMPDIR/nottable.txt
	fixture "$BATS_TEST_TMPDIR/nottable.lua" <<-EOF
		local applied = require("config.xghost").setup()
		local out = assert(io.open("$out", "w"))
		out:write(tostring(applied) .. "\n")
		out:close()
	EOF
	run -0 --separate-stderr run_nvim "$BATS_TEST_TMPDIR/nottable.lua"
	[[ $stderr == *"not a table"* ]]

	run cat "$out"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "false" ]
}

@test "a generated palette whose colour is not '#rrggbb' is named and nothing is applied" {
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight
	cat >"$(readlink -f "$GENERATED")/nvim/colors.lua" <<-'EOF'
		return { bg = "blue", surface = "#1F2335", surface_alt = "#1A1B26",
		  text = "#C0CAF5", text_muted = "#A9B1D6", accent = "#7AA2F7",
		  accent_alt = "#73DACA", warn = "#E0AF68", error = "#F7768E",
		  success = "#9ECE6A" }
	EOF

	fixture "$BATS_TEST_TMPDIR/badcolour.lua" <<-'EOF'
		require("config.xghost").setup()
	EOF
	run -0 --separate-stderr run_nvim "$BATS_TEST_TMPDIR/badcolour.lua"
	[[ $stderr == *"no '#rrggbb' value for: bg"* ]]
}

#
# The colourscheme: the palette is applied over it, and stays applied.
#

@test "the palette is applied over the colourscheme that loaded before it" {
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight

	run highlight_report \
		'vim.cmd.colorscheme("habamax") require("config.xghost").setup()' \
		'show("Normal") show("Comment") show("DiagnosticError")'
	[ "$status" -eq 0 ]

	local bg text muted err
	bg=$(palette_value tokyonight BG)
	text=$(palette_value tokyonight TEXT)
	muted=$(palette_value tokyonight TEXT_MUTED)
	err=$(palette_value tokyonight ERROR)
	[[ $output == *"Normal fg=${text^^} bg=${bg^^}"* ]]
	[[ $output == *"Comment fg=${muted^^} bg=none"* ]]
	[[ $output == *"DiagnosticError fg=${err^^} bg=none"* ]]
}

@test "a colourscheme loaded after the palette does not win" {
	# The trap of this bundle. Loading a colourscheme clears every highlight
	# group, so a palette applied once would be gone. The prescribed Lua
	# re-applies it on the 'ColorScheme' event.
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight

	run highlight_report \
		'require("config.xghost").setup() vim.cmd.colorscheme("desert")' \
		'show("Normal")'
	[ "$status" -eq 0 ]

	local bg text
	bg=$(palette_value tokyonight BG)
	text=$(palette_value tokyonight TEXT)
	[[ $output == *"Normal fg=${text^^} bg=${bg^^}"* ]]
}

@test "the colours of the editor follow a theme switch" {
	require_nvim
	link_prescribed
	"$XGHOST" theme set macos-dark

	run highlight_report \
		'vim.cmd.colorscheme("habamax") require("config.xghost").setup()' \
		'show("Normal")'
	[ "$status" -eq 0 ]

	local bg text
	bg=$(palette_value macos-dark BG)
	text=$(palette_value macos-dark TEXT)
	[[ $output == *"Normal fg=${text^^} bg=${bg^^}"* ]]
}

@test "loading the prescribed Lua twice leaves one autocommand" {
	require_nvim
	link_prescribed
	"$XGHOST" theme set tokyonight

	local out=$BATS_TEST_TMPDIR/autocmds.txt
	fixture "$BATS_TEST_TMPDIR/autocmds.lua" <<-EOF
		local m = require("config.xghost")
		m.setup()
		m.setup()
		local out = assert(io.open("$out", "w"))
		out:write(#vim.api.nvim_get_autocmds({ group = "XghostTheme", event = "ColorScheme" }) .. "\n")
		out:close()
	EOF
	run_nvim "$BATS_TEST_TMPDIR/autocmds.lua" >/dev/null 2>&1 || true

	run cat "$out"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "1" ]
}

#
# The prescribed files.
#

@test "init.lua loads the theme bridge after the plugins" {
	run lua_code "$INIT_FILE"
	[ "$status" -eq 0 ]
	[[ $output == *'require("config.xghost").setup()'* ]]

	# The order matters for a reader, though the autocommand is what makes the
	# palette win. The plugin manager is set up first.
	local lazy_line bridge_line
	lazy_line=$(grep -n 'require("config.lazy")' "$INIT_FILE" | head -1 | cut -d: -f1)
	bridge_line=$(grep -n 'require("config.xghost").setup()' "$INIT_FILE" | head -1 | cut -d: -f1)
	[ "$lazy_line" -lt "$bridge_line" ]
}

@test "the prescribed Lua names no colour of its own" {
	# The rule every bundle of this project lives by: a value the generated file
	# sets must not be set in the prescribed file, or the theme would change
	# nothing.
	run lua_code "$LOADER_FILE"
	[ "$status" -eq 0 ]
	[[ ! $output =~ \#[0-9a-fA-F]{6} ]]
}

@test "the prescribed Lua reports through nvim_echo and not through vim.notify" {
	# 'vim.notify' is a variable. snacks.nvim, which the configuration beside
	# this file loads through LazyVim, replaces it before init.lua reaches the
	# line that calls this bundle, and the replacement drops the message.
	run lua_code "$LOADER_FILE"
	[ "$status" -eq 0 ]
	[[ $output != *"vim.notify"* ]]
	[[ $output == *"nvim_echo"* ]]
}

@test "every comment of the two prescribed Lua files is a whole line" {
	# 'lua_code' above drops the comments by dropping the lines that start with
	# '--'. That is only the code if no comment shares a line with code.
	local file
	for file in "$INIT_FILE" "$LOADER_FILE"; do
		run grep -n '[^[:space:]].*--' "$file"
		[ "$status" -ne 0 ] || {
			printf '%s holds a comment that follows code:\n%s\n' "$file" "$output" >&2
			return 1
		}
	done
}
