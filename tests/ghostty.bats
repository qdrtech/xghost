#!/usr/bin/env bats
#
# Tests for the Ghostty bundle: the prescribed configuration under
# config/ghostty and the colour template under templates/ghostty.
#
# The bundle is the first one that joins the linker and the renderer, so these
# tests drive both real commands against a temporary home directory and assert
# what lands on disk.
#
# The tests that need Ghostty itself skip when Ghostty is not installed, so the
# suite passes in continuous integration, which has no Ghostty. Those tests
# assert on 'ghostty +show-config', which prints the settings Ghostty actually
# holds. They never assert on 'ghostty +validate-config': the include of the
# generated colours is optional, so a terminal that found none of them still
# validates and exits zero.
#
# The design of the bundle is recorded in docs/bundles/ghostty.md.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR="$BATS_TEST_DIRNAME/.."
	PRESCRIBED="$ROOT_DIR/config/ghostty/config"
	TEMPLATE="$ROOT_DIR/templates/ghostty/colors.conf"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# Every path the commands read comes from this setup, so no test touches
	# the home directory of the person who runs them, and no override that
	# person happens to export reaches a command. A developer with
	# XGHOST_TEMPLATE_DIR exported would otherwise render from templates that
	# are not the ones under test, and every assertion below would still pass.
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
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	# A render of the shipped templates needs the machine facts, because the
	# Hyprland bundle takes its monitor layout from them. These tests render the
	# whole template directory to reach the Ghostty part of it. No assertion
	# below reads a fact: they only keep the render from failing on a fact it
	# wanted. tests/helpers.bash records the rule.
	use_fixed_machine_facts

	# The knobs are the third input, and one of them is the font family this
	# bundle draws with. Every test starts from a machine with no knobs file, so
	# the font is the default of schema/knobs.conf.
	use_own_knobs

	GENERATED="$XDG_STATE_HOME/xghost/generated"

	# The name 'xghost config link' gives the generated output inside the
	# config directory, and the line the prescribed configuration carries.
	#
	# The include is relative, so both of its ends follow the environment: the
	# directory the prescribed file was opened from is inside XDG_CONFIG_HOME,
	# and the bridge reaches XDG_STATE_HOME. Ghostty expands no environment
	# variable, so a path written out in full would be wrong the moment either
	# variable is not the default. docs/bundles/ghostty.md records that.
	BRIDGE_NAME=xghost-generated
	INCLUDE_PATH="../$BRIDGE_NAME/ghostty/colors.conf"
	INCLUDE_LINE="config-file = ?$INCLUDE_PATH"
}

# Print the value one theme declares for one palette name.
palette_value() {
	local theme=$1 name=$2
	sed -n "s/^$name=//p" "$ROOT_DIR/themes/$theme/palette.conf"
}

# Link the prescribed configuration of the checkout into the config directory.
link_prescribed() {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config link
}

# Resolve the include the way Ghostty resolves it: against the directory of the
# file it opened, and lexically, so '..' is the parent of the path that still
# holds the link rather than the parent of the directory the link points into.
resolved_include() {
	local opened="$XDG_CONFIG_HOME/ghostty"
	printf '%s/%s\n' "${opened%/*}" "${INCLUDE_PATH#../}"
}

# A test that needs the real Ghostty. Continuous integration has none.
require_ghostty() {
	if ! command -v ghostty >/dev/null 2>&1; then
		skip "ghostty is not installed"
	fi
}

@test "the Ghostty configuration is prescribed configuration" {
	[ -f "$PRESCRIBED" ]
	[ ! -L "$ROOT_DIR/config/ghostty" ]
}

@test "'config link' places the Ghostty configuration as a symbolic link" {
	run link_prescribed
	[ "$status" -eq 0 ]
	[ -L "$XDG_CONFIG_HOME/ghostty" ]
	[ "$(readlink "$XDG_CONFIG_HOME/ghostty")" = "$ROOT_DIR/config/ghostty" ]
	[ -f "$XDG_CONFIG_HOME/ghostty/config" ]
}

@test "the prescribed configuration includes the generated colours, optionally" {
	run grep -Fx "$INCLUDE_LINE" "$PRESCRIBED"
	[ "$status" -eq 0 ]
}

# The include names one path and the renderer writes another. The bridge that
# 'config link' creates is what joins them, so this test drives both commands
# and follows the path from the prescribed file to the generated file.
@test "the include reaches the file the renderer writes" {
	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local resolved
	resolved=$(resolved_include)
	[ "$resolved" = "$XDG_CONFIG_HOME/$BRIDGE_NAME/ghostty/colors.conf" ]
	[ -f "$resolved" ]
	[ "$resolved" -ef "$GENERATED/ghostty/colors.conf" ]
}

# The one divergence that breaks a terminal, and the one a home directory built
# out of defaults can never show: a state directory that is not
# '$HOME/.local/state'. The renderer writes where XDG_STATE_HOME points, so an
# include that names the default path in full reaches nothing. The '?' in front
# of the include swallows that miss, and the terminal then comes up unthemed
# with no error at all.
@test "the include reaches the generated colours when XDG_STATE_HOME is not the default" {
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local resolved
	resolved=$(resolved_include)
	[ -f "$resolved" ]

	# It is the very file the renderer wrote, and it carries the colours of
	# the theme rather than an empty file that merely exists.
	[ "$resolved" -ef "$XDG_STATE_HOME/xghost/generated/ghostty/colors.conf" ]
	run grep -Fx "background = $(palette_value tokyonight BG)" "$resolved"
	[ "$status" -eq 0 ]
}

@test "'config unlink' removes the bridge to the generated output" {
	run link_prescribed
	[ "$status" -eq 0 ]
	[ -L "$XDG_CONFIG_HOME/$BRIDGE_NAME" ]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ ! -L "$XDG_CONFIG_HOME/$BRIDGE_NAME" ]
	[ ! -e "$XDG_CONFIG_HOME/$BRIDGE_NAME" ]
}

# The font is a knob, so the prescribed file names no family at all. Ghostty
# appends every 'font-family' it reads to one list and draws with the first of
# them, so a family here would win over the generated one and the knob would
# change nothing.
@test "the font family comes from the knob and not from the prescribed file" {
	run grep -E '^[[:space:]]*font-family' "$PRESCRIBED"
	[ "$status" -ne 0 ]
	run grep -Fx "config-file = ?../$BRIDGE_NAME/ghostty/font.conf" "$PRESCRIBED"
	[ "$status" -eq 0 ]

	# The generated file names one family, and it is the knob.
	run grep -E '^[[:space:]]*font-family' "$ROOT_DIR/templates/ghostty/font.conf"
	[ "$status" -eq 0 ]
	[ "$output" = 'font-family = @KNOB_FONT@' ]

	# '.SF NS Mono' is the macOS system font, and no Arch machine has it. The
	# comments still name it as the font that was replaced, so the test reads
	# the settings alone: a comment line starts with a hash.
	run grep -E '^[^#]*\.SF NS Mono' "$PRESCRIBED"
	[ "$status" -ne 0 ]
}

# The default of the knob is the family the Arch package
# 'ttf-jetbrains-mono-nerd' provides, so a machine that changes nothing gets the
# font this bundle was designed around.
@test "the font knob reaches the generated Ghostty configuration" {
	"$XGHOST" theme set tokyonight >/dev/null
	run grep -Fx 'font-family = JetBrainsMono Nerd Font' "$GENERATED/ghostty/font.conf"
	[ "$status" -eq 0 ]

	run "$XGHOST" settings set KNOB_FONT 'CaskaydiaCove Nerd Font'
	[ "$status" -eq 0 ]
	run grep -Fx 'font-family = CaskaydiaCove Nerd Font' "$GENERATED/ghostty/font.conf"
	[ "$status" -eq 0 ]

	# One family reaches the terminal, whatever the knob holds.
	run grep -c '^font-family' "$GENERATED/ghostty/font.conf"
	[ "$output" = 1 ]
}

# 'background-blur-radius' is an undocumented compatibility alias. Ghostty
# 1.3.1 rewrites it to 'background-blur' and says nothing, and it appears in no
# '+show-config --default --docs' output, so its removal would be silent.
@test "the prescribed configuration names the documented blur setting" {
	run grep -Fx 'background-blur = 20' "$PRESCRIBED"
	[ "$status" -eq 0 ]
	run grep -E '^[[:space:]]*background-blur-radius' "$PRESCRIBED"
	[ "$status" -ne 0 ]
}

# The mapping of a setting to the palette name it carries. A test that only
# looked for each value somewhere in the file would pass with 'background' and
# 'foreground' swapped, so every assertion here is on a whole line.
@test "every theme renders the Ghostty colours from its own palette" {
	local -a settings=(
		'background=BG'
		'foreground=TEXT'
		'cursor-color=ACCENT'
		'selection-background=SURFACE'
		'selection-foreground=TEXT'
	)
	local -a slots=(
		BG ERROR SUCCESS WARN ACCENT ACCENT_ALT ACCENT_ALT TEXT
		TEXT_MUTED ERROR SUCCESS WARN ACCENT ACCENT_ALT ACCENT_ALT TEXT
	)
	local theme entry setting name value slot count=0

	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		[ -f "$GENERATED/ghostty/colors.conf" ]

		for entry in "${settings[@]}"; do
			setting=${entry%%=*}
			name=${entry#*=}
			value=$(palette_value "$theme" "$name")
			[ -n "$value" ]
			run grep -Fx "$setting = $value" "$GENERATED/ghostty/colors.conf"
			[ "$status" -eq 0 ]
		done

		for slot in "${!slots[@]}"; do
			value=$(palette_value "$theme" "${slots[slot]}")
			[ -n "$value" ]
			run grep -Fx "palette = $slot=$value" "$GENERATED/ghostty/colors.conf"
			[ "$status" -eq 0 ]
		done

		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

# Slot 8 is bright black. zsh-autosuggestions, the hints of fzf, and the line
# numbers of bat and delta all draw in it by default, so a slot 8 that carries
# the background colour, or the surface colour that is the background under
# another name, makes all of them invisible.
@test "bright black is neither the background colour nor the surface colour" {
	local theme background surface bright_black count=0
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		background=$(palette_value "$theme" BG)
		surface=$(palette_value "$theme" SURFACE)
		bright_black=$(sed -n 's/^palette = 8=//p' "$GENERATED/ghostty/colors.conf")
		[ -n "$bright_black" ]
		[ "$bright_black" != "$background" ]
		[ "$bright_black" != "$surface" ]
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

@test "the Ghostty template names only values the palettes declare" {
	local theme
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		run grep -E '@[A-Z][A-Z0-9_]*@' "$GENERATED/ghostty/colors.conf"
		[ "$status" -ne 0 ]
	done < <("$XGHOST" theme list)
}

@test "the colour template holds every one of the sixteen terminal slots" {
	local slot
	for slot in $(seq 0 15); do
		run grep -E "^palette = $slot=@[A-Z][A-Z0-9_]*@\$" "$TEMPLATE"
		[ "$status" -eq 0 ]
	done
}

# --- the real Ghostty --------------------------------------------------------

# '+show-config' prints the settings Ghostty holds after it has read every file
# it reads. A 'background' line is therefore the proof that the terminal is
# themed. '+validate-config' proves nothing here: the include is optional, so a
# terminal that found no colours at all still exits zero.
@test "ghostty reads the generated colours when XDG_STATE_HOME is not the default" {
	require_ghostty
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local shown="$BATS_TEST_TMPDIR/show-config"
	run --separate-stderr ghostty +show-config
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" >"$shown"

	# Ghostty prints a colour in lower case, whatever case the theme wrote.
	local background
	background=$(palette_value tokyonight BG)
	run grep '^background = ' "$shown"
	[ "$status" -eq 0 ]
	[ "$output" = "background = ${background,,}" ]
}

@test "ghostty reads the whole palette of the theme" {
	require_ghostty
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local shown="$BATS_TEST_TMPDIR/show-config"
	run --separate-stderr ghostty +show-config
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" >"$shown"

	local foreground bright_black
	foreground=$(palette_value tokyonight TEXT)
	bright_black=$(palette_value tokyonight TEXT_MUTED)
	run grep '^foreground = ' "$shown"
	[ "$status" -eq 0 ]
	[ "$output" = "foreground = ${foreground,,}" ]
	run grep '^palette = 8=' "$shown"
	[ "$status" -eq 0 ]
	[ "$output" = "palette = 8=${bright_black,,}" ]
}

# The font knob has to reach the terminal that runs, not only the file the
# renderer wrote. '+show-config' prints the family Ghostty holds after it has
# read every file, so a second 'font-family' anywhere would show up here.
@test "ghostty draws with the family the font knob names" {
	require_ghostty
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local shown="$BATS_TEST_TMPDIR/show-config"
	run --separate-stderr ghostty +show-config
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" >"$shown"
	run grep '^font-family = ' "$shown"
	[ "$status" -eq 0 ]
	[ "$output" = 'font-family = JetBrainsMono Nerd Font' ]

	run "$XGHOST" settings set KNOB_FONT 'CaskaydiaCove Nerd Font'
	[ "$status" -eq 0 ]
	run --separate-stderr ghostty +show-config
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" >"$shown"
	run grep '^font-family = ' "$shown"
	[ "$status" -eq 0 ]
	[ "$output" = 'font-family = CaskaydiaCove Nerd Font' ]
}

# The bridge is what makes the relative include resolve. Without it the include
# reaches nothing, and the optional include reports nothing, so the terminal
# comes up unthemed in silence. This is the failure the bundle must never have
# again.
@test "ghostty comes up unthemed when the bridge is missing" {
	require_ghostty
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null
	rm "$XDG_CONFIG_HOME/$BRIDGE_NAME"

	local shown="$BATS_TEST_TMPDIR/show-config"
	run --separate-stderr ghostty +show-config
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" >"$shown"

	run grep '^background = ' "$shown"
	[ "$status" -ne 0 ]

	# And Ghostty still validates, which is why no test in this file reads the
	# exit code of '+validate-config' as proof of a themed terminal.
	run --separate-stderr ghostty +validate-config
	[ "$status" -eq 0 ]
}
