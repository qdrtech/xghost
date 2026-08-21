#!/usr/bin/env bats
#
# Tests for the Waybar bundle: the prescribed configuration under config/waybar
# and the templates under templates/waybar.
#
# No test here starts Waybar. Every claim below is proved by rendering, by
# reading the two prescribed files, and by resolving each path the way Waybar
# resolves it. What that leaves unproved is recorded in docs/bundles/waybar.md,
# under "What this bundle has never been observed doing".
#
# Two rules of this bundle are what most of these tests are about, and both come
# from the same fault: a generated file that reaches nothing, or that is
# overruled, leaves a bar that looks wrong and says nothing.
#
#   - Waybar keeps the value the including file holds, so a key the generated
#     configuration sets must be absent from the prescribed file. The same holds
#     for the style sheet, where a rule of the importing file wins over a rule of
#     the same weight in the imported one.
#   - A GTK '@import' that reaches nothing is fatal, so the render has to run
#     before the first session.
#
# The design of the bundle is recorded in docs/bundles/waybar.md.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	PRESCRIBED_DIR="$ROOT_DIR/config/waybar"
	CONFIG_FILE="$PRESCRIBED_DIR/config"
	STYLE_FILE="$PRESCRIBED_DIR/style.css"
	TEMPLATE_DIR="$ROOT_DIR/templates/waybar"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# Every path the commands read comes from this setup, so no test touches the
	# home directory of the person who runs them, and no override that person
	# happens to export reaches a command.
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
	# Hyprland bundle takes its monitor layout from them. No assertion below
	# reads a fact. tests/helpers.bash records the rule.
	use_fixed_machine_facts

	# The knobs are the third input, and two of them reach the bar. Every test
	# starts from a machine with no knobs file, so each one holds the default of
	# schema/knobs.conf.
	use_own_knobs

	GENERATED="$XDG_STATE_HOME/xghost/generated"

	# The name 'xghost config link' gives the generated output inside the config
	# directory. Both the style sheet and the configuration file reach the
	# generated output through it.
	BRIDGE_NAME=xghost-generated
}

# Link the prescribed configuration of the checkout into the config directory.
link_prescribed() {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config link
}

# Print the prescribed configuration with its comments dropped.
#
# Waybar parses that file with jsoncpp, which allows a comment wherever white
# space is allowed. Every comment of the file is a whole line, which this test
# file asserts on its own below, so dropping the lines that start with '//'
# leaves one JSON document.
prescribed_json() {
	grep -v '^[[:space:]]*//' "$CONFIG_FILE"
}

# Read one JSON document with lib/json.sh and print one path of it.
#
#   json_value TEXT PATH
#
# Nothing else in this project reads JSON in a test, so the reader of the
# detection is used. It runs nothing and expands nothing.
json_value() {
	local script="$BATS_TEST_TMPDIR/json.sh"
	cat >"$script" <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		if ! json_parse "$2"; then
			printf 'problem: %s\n' "$JSON_ERROR" >&2
			exit 1
		fi
		if [ -n "${JSON_VALUE[$3]+set}" ]; then
			printf '%s\n' "${JSON_VALUE[$3]}"
			exit 0
		fi
		if [ -n "${JSON_SIZE[$3]+set}" ]; then
			printf '%s of %s members\n' "${JSON_KIND[$3]}" "${JSON_SIZE[$3]}"
			exit 0
		fi
		exit 3
	EOF
	bash "$script" "$ROOT_DIR" "$1" "$2"
}

# Print the value one theme declares for one palette name.
palette_value() {
	local theme=$1 name=$2
	sed -n "s/^$name=//p" "$ROOT_DIR/themes/$theme/palette.conf"
}

# Print every value the schema declares for one knob, one per line.
schema_values() {
	local knob=$1
	awk -v knob="$knob" '
		/^[a-z]+=/ {
			field = substr($0, 1, index($0, "=") - 1)
			value = substr($0, index($0, "=") + 1)
			if (field == "knob") { current = value }
			else if (field == "value" && current == knob) { print value }
		}
	' "$ROOT_DIR/schema/knobs.conf"
}

# Print the include path of the prescribed configuration, expanded the way
# Waybar expands it.
#
# Waybar passes an include path to wordexp(3), which is full shell word
# expansion. 'eval' is that expansion here. The text it runs is the include line
# of a file the project owns, which is the same rule the bundle itself lives by:
# docs/adr/0002-the-bridge-to-the-generated-output.md records that a Waybar
# include path is executed input and must stay a constant of the project.
expanded_include() {
	local raw
	raw=$(json_value "$(prescribed_json)" include.0) || return 1
	eval "printf '%s\n' $raw"
}

@test "the Waybar configuration is prescribed configuration" {
	[ -f "$CONFIG_FILE" ]
	[ -f "$STYLE_FILE" ]
	[ ! -L "$PRESCRIBED_DIR" ]
}

@test "'config link' places the Waybar configuration as a symbolic link" {
	run link_prescribed
	[ "$status" -eq 0 ]
	[ -L "$XDG_CONFIG_HOME/waybar" ]
	[ "$(readlink "$XDG_CONFIG_HOME/waybar")" = "$PRESCRIBED_DIR" ]
	[ -f "$XDG_CONFIG_HOME/waybar/config" ]
	[ -f "$XDG_CONFIG_HOME/waybar/style.css" ]
	[ -L "$XDG_CONFIG_HOME/$BRIDGE_NAME" ]
}

# --- the configuration file --------------------------------------------------

@test "the prescribed configuration is one JSON document" {
	run json_value "$(prescribed_json)" .
	[ "$status" -eq 0 ]
	[[ $output == "object of "* ]]

	# And the module lists are the ones the style sheet draws.
	run json_value "$(prescribed_json)" modules-center.0
	[ "$status" -eq 0 ]
	[ "$output" = "hyprland/workspaces" ]
}

# Every comment of the file is a whole line. A comment that followed a value on
# its line would leave the helper above producing text that is not the document
# Waybar reads, and every assertion of this file would then be about something
# else.
@test "every comment of the prescribed configuration is a whole line" {
	run grep -n '//' "$CONFIG_FILE"
	[ "$status" -eq 0 ]
	local line
	while IFS= read -r line; do
		[[ ${line#*:} =~ ^[[:space:]]*// ]]
	done <<<"$output"
}

# The rule of this bundle. Waybar merges an included file into the file that
# includes it and keeps the value the including file already holds, so a
# 'position' in the prescribed file would overrule the generated one and the
# knob would change nothing at all.
@test "the prescribed configuration sets no key the generated configuration sets" {
	run json_value "$(prescribed_json)" position
	[ "$status" -eq 3 ]

	# Read against every file of the bundle rather than against that one path: a
	# 'position' added to any other prescribed file would pass the assertion
	# above and still reach Waybar.
	run bash -c "cd '$ROOT_DIR' && grep -rl '\"position\"' config templates | LC_ALL=C sort | paste -sd, -"
	[ "$output" = "templates/waybar/position.json" ]
}

@test "the include reaches the file the renderer writes" {
	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local resolved
	resolved=$(expanded_include)
	[ "$resolved" = "$XDG_CONFIG_HOME/$BRIDGE_NAME/waybar/position.json" ]
	[ -f "$resolved" ]
	[ "$resolved" -ef "$GENERATED/waybar/position.json" ]
}

# The divergence a home directory built out of defaults can never show. The
# renderer follows XDG_STATE_HOME and the include follows XDG_CONFIG_HOME, and
# the bridge is what joins them, so both ends have to be right at once.
@test "the include reaches the generated configuration when neither XDG path is the default" {
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local resolved
	resolved=$(expanded_include)
	[ -f "$resolved" ]
	[ "$resolved" -ef "$XDG_STATE_HOME/xghost/generated/waybar/position.json" ]
}

# A machine that never set XDG_CONFIG_HOME is the usual one, and the include has
# to be right there as well. The path names the default of the XDG base
# directory specification for exactly that case.
@test "the include reaches the generated configuration when XDG_CONFIG_HOME is unset" {
	local config_home="$HOME/.config"
	unset XDG_CONFIG_HOME

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local resolved
	resolved=$(expanded_include)
	[ "$resolved" = "$config_home/$BRIDGE_NAME/waybar/position.json" ]
	[ -f "$resolved" ]
}

# wordexp splits its result into fields and expands a glob, so the include path
# carries its own quotation marks. A home directory with a space in it would
# otherwise reach Waybar as its first field alone.
@test "the include path survives a home directory that holds a space" {
	export HOME="$BATS_TEST_TMPDIR/a home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local resolved
	resolved=$(expanded_include)
	[ "$resolved" = "$XDG_CONFIG_HOME/$BRIDGE_NAME/waybar/position.json" ]
	[ -f "$resolved" ]
}

# Neither end of the include is written out in full. The config directory comes
# from the variable that names it, with the default of the XDG base directory
# specification behind it, and the state directory is reached through the bridge
# and is never named at all.
@test "the include names no state directory and follows XDG_CONFIG_HOME" {
	local raw
	raw=$(json_value "$(prescribed_json)" include.0)
	[[ $raw == *'${XDG_CONFIG_HOME:-$HOME/.config}'* ]]
	[[ $raw != *"~"* ]]
	[[ $raw != *".local/state"* ]]
	[[ $raw == *"$BRIDGE_NAME"* ]]
}

# --- the style sheet ---------------------------------------------------------

@test "the style sheet imports the generated files through the bridge" {
	local name
	for name in colors knobs; do
		run grep -Fx "@import \"../$BRIDGE_NAME/waybar/$name.css\";" "$STYLE_FILE"
		[ "$status" -eq 0 ]
	done

	# GTK expands neither a variable nor '~' in an '@import', so a path that
	# named either would reach nothing, and an import that reaches nothing is
	# fatal.
	run grep -nE '^[[:space:]]*@import.*(~|\$)' "$STYLE_FILE"
	[ "$status" -ne 0 ]

	# Every import comes before the first rule. A colour has to be defined
	# before a rule names it.
	local first_import first_rule
	first_import=$(grep -n '^@import' "$STYLE_FILE" | head -1 | cut -d: -f1)
	first_rule=$(grep -nE '^[^ /*@}].*\{' "$STYLE_FILE" | head -1 | cut -d: -f1)
	[ -n "$first_import" ]
	[ -n "$first_rule" ]
	[ "$first_import" -lt "$first_rule" ]
}

# GTK resolves a relative '@import' against the directory of the file that
# imports it, and Waybar opens the style sheet at the path 'xghost config link'
# created. '..' is therefore the config directory of the user, where the bridge
# is.
#
# Both XDG paths are moved, which is the case the include has above and the
# Confirmation section of ADR 0002 asks every bundle after Ghostty for by name.
# The renderer follows XDG_STATE_HOME and the import is resolved against
# XDG_CONFIG_HOME, so the two ends have to be right at once on this route as
# well as on the other one. A home directory built out of defaults can never
# show that divergence.
@test "the import of the style sheet reaches the file the renderer writes" {
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local opened="$XDG_CONFIG_HOME/waybar"
	local resolved="${opened%/*}/$BRIDGE_NAME/waybar/colors.css"
	[ -f "$resolved" ]
	[ "$resolved" -ef "$XDG_STATE_HOME/xghost/generated/waybar/colors.css" ]
	run grep -Fx "@define-color bg $(palette_value tokyonight BG);" "$resolved"
	[ "$status" -eq 0 ]
}

# A GTK colour that no file defines is a colour the style sheet cannot draw
# with, and this style sheet defines none of its own. The dotfiles this bundle
# comes from named four colours that their generated file never defined, which
# is the fault this test exists for.
#
# The pattern carries the hyphen, and that is the point of it. GTK3 allows '-'
# in the identifier of an '@define-color', so '@accent-alt' is one name. A
# pattern that stopped at the hyphen would read it as '@accent', find 'accent'
# in the palette, and pass. Nothing downstream catches that: a Gtk.CssProvider
# that loads a sheet naming an undefined colour returns success and drops the
# declaration in silence, which is how the four colours above went unnoticed
# through every login.
@test "every colour the style sheet names is defined by the generated palette" {
	"$XGHOST" theme set tokyonight >/dev/null
	local generated="$GENERATED/waybar/colors.css"
	[ -f "$generated" ]

	local name count=0
	while IFS= read -r name; do
		[ "$name" = "import" ] && continue
		run grep -Fq "@define-color $name " "$generated"
		[ "$status" -eq 0 ] || {
			printf 'the style sheet names @%s and no generated file defines it\n' \
				"$name" >&2
			return 1
		}
		count=$((count + 1))
	done < <(grep -oE '@[a-zA-Z][a-zA-Z0-9_-]*' "$STYLE_FILE" | sed 's/^@//' |
		LC_ALL=C sort -u)
	[ "$count" -gt 0 ]
}

@test "the style sheet defines no colour of its own" {
	run grep -n '@define-color' "$STYLE_FILE"
	[ "$status" -ne 0 ]
}

# An eight-digit hex in a palette would stop this bar from starting. GTK3 reads
# '#RRGGBBAA' in an '@define-color' as a colour it cannot parse and raises
# 'Missing semicolon at end of color definition', which is an error, and an
# '@import' that errors is the fatal case this bundle is built around.
#
# Waybar carries a workaround for exactly that spelling, 'transform_8bit_to_hex',
# and it does not cover this: it rewrites the style sheet Waybar opened and never
# a file that sheet imports. The generated palette is imported, so GTK reads it
# as written.
#
# Every name of the palette today is caught before that, and by accident.
# templates/hypr/colors.conf asks for 'NAME_HEX', lib/palette.sh derives that
# form from a six-digit value alone, and the render then fails by name. That
# guard belongs to another bundle and covers the names that bundle consumes. A
# name added for the bar alone carries no such guard: the render succeeds and
# the value reaches the imported file. This test is the guard that depends on no
# other bundle.
#
# The names are read out of the template rather than listed here, so a palette
# name added to templates/waybar/colors.css later is covered on the day it is
# added.
@test "every palette value the bar imports is a six-digit hex" {
	local names
	names=$(grep -oE '@[A-Z][A-Z0-9_]*@' "$TEMPLATE_DIR/colors.css" |
		tr -d '@' | LC_ALL=C sort -u)
	[ -n "$names" ]

	local theme name value count=0
	while IFS= read -r theme; do
		[ -n "$theme" ] || continue
		while IFS= read -r name; do
			value=$(palette_value "$theme" "$name")
			[ -n "$value" ] || {
				printf 'the theme %s declares no %s, which the bar imports\n' \
					"$theme" "$name" >&2
				return 1
			}
			[[ $value =~ ^#[0-9a-fA-F]{6}$ ]] || {
				printf 'the theme %s writes %s=%s; GTK cannot parse it and the bar would not start\n' \
					"$theme" "$name" "$value" >&2
				return 1
			}
			count=$((count + 1))
		done <<<"$names"
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

# --- the knobs ---------------------------------------------------------------

# The bar position is a scalar knob: one value reaches one key of one generated
# file. docs/bundles/waybar.md records why it is not a structural choice.
#
# The theme is set first, and that is the precondition rather than a detail of
# this test. 'xghost settings set' renders only when a theme is active: with
# none, it stores the value, writes no file, and says so. docs/knobs.md records
# that, and the knob tests of the other two bundles open the same way.
@test "the bar position knob reaches the generated configuration at every value" {
	"$XGHOST" theme set tokyonight >/dev/null

	local value count=0
	while IFS= read -r value; do
		run "$XGHOST" settings set KNOB_BAR_POSITION "$value"
		[ "$status" -eq 0 ]
		# Read before parsing, so a file that was never written is named as the
		# missing file it is rather than as a document that holds nothing.
		[ -f "$GENERATED/waybar/position.json" ]
		run json_value "$(grep -v '^[[:space:]]*//' "$GENERATED/waybar/position.json")" position
		[ "$status" -eq 0 ]
		[ "$output" = "$value" ]
		count=$((count + 1))
	done < <(schema_values KNOB_BAR_POSITION)
	[ "$count" -gt 1 ]
}

@test "the bar comes up at the top on a machine that has changed nothing" {
	"$XGHOST" theme set tokyonight >/dev/null
	run json_value "$(grep -v '^[[:space:]]*//' "$GENERATED/waybar/position.json")" position
	[ "$status" -eq 0 ]
	[ "$output" = top ]
}

@test "the schema refuses a position Waybar would not draw" {
	run "$XGHOST" settings set KNOB_BAR_POSITION sideways
	[ "$status" -eq 2 ]
	[[ $output == *"'sideways' is not a value of 'KNOB_BAR_POSITION'"* ]]
}

# The font of the bar is the font of the compositor and of the terminal. A
# family in the style sheet would win over the generated one, because a rule of
# the importing file wins over a rule of the file it imported.
@test "the font knob reaches the bar and the style sheet names no family" {
	"$XGHOST" theme set tokyonight >/dev/null
	run grep -F 'font-family: "JetBrainsMono Nerd Font", sans-serif;' \
		"$GENERATED/waybar/knobs.css"
	[ "$status" -eq 0 ]

	run "$XGHOST" settings set KNOB_FONT 'CaskaydiaCove Nerd Font'
	[ "$status" -eq 0 ]
	run grep -F 'font-family: "CaskaydiaCove Nerd Font", sans-serif;' \
		"$GENERATED/waybar/knobs.css"
	[ "$status" -eq 0 ]

	# One family reaches the bar, and it is written in the generated file of
	# each bundle that draws in it. No prescribed file of the project holds one.
	# The SwayNC bundle is the second, and docs/bundles/swaync.md records it.
	#
	# The pattern is not anchored to the start of a line. A rule written on one
	# line, 'window#waybar { font-family: "Comic Sans"; }', holds the property
	# after a brace rather than after white space alone, and an anchored pattern
	# reads that file as one that names no family at all. Such a rule wins on
	# specificity over the '*' of the generated file, so the knob would reach
	# the bar and change nothing anyone can see.
	local guard='(^|[{;[:space:]])font-family[[:space:]]*:'
	run bash -c "cd '$ROOT_DIR' && grep -rlE '$guard' config templates | LC_ALL=C sort | paste -sd, -"
	[ "$output" = "templates/swaync/knobs.css,templates/waybar/knobs.css" ]

	# And the guard fires on that evasion. It is written into a copy: no test of
	# this project writes into the checkout.
	local copy="$BATS_TEST_TMPDIR/evasion"
	mkdir -p "$copy"
	cp -R "$ROOT_DIR/config" "$ROOT_DIR/templates" "$copy/"
	printf 'window#waybar { font-family: "Comic Sans"; }\n' \
		>>"$copy/config/waybar/style.css"
	run bash -c "cd '$copy' && grep -rlE '$guard' config templates | LC_ALL=C sort | paste -sd, -"
	[ "$output" = "config/waybar/style.css,templates/swaync/knobs.css,templates/waybar/knobs.css" ]
}

# --- what the bundle names ---------------------------------------------------

# The terminal of the two modules that open one is the terminal of this desktop,
# read from the file that names it rather than written out twice.
@test "the modules that open a terminal open the terminal of this desktop" {
	local terminal
	terminal=$(sed -n 's/^\$terminal[[:space:]]*=[[:space:]]*//p' \
		"$ROOT_DIR/config/hypr/hyprland.conf")
	[ -n "$terminal" ]

	local command
	command=$(json_value "$(prescribed_json)" network.on-click)
	[[ $command == "$terminal "* ]]
	command=$(json_value "$(prescribed_json)" custom/pacman.on-click)
	[[ $command == "$terminal "* ]]

	# The dotfiles opened kitty, which this desktop does not ship at all.
	run grep -n 'kitty' "$CONFIG_FILE"
	[ "$status" -ne 0 ]
}

# MACHINE_TERMINAL is 'unknown' on a machine that declares no default terminal,
# and the renderer refuses to write that word. The terminal of the bar is
# prescribed for that reason, and this proves no template of the bundle reaches
# for the fact instead.
@test "no template of the bar names a machine fact" {
	run grep -rn 'MACHINE_' "$TEMPLATE_DIR"
	[ "$status" -ne 0 ]
}

# A prescribed file cannot write its own location, so every command of this
# bundle names a program on the PATH. The dotfiles ran three scripts out of
# ~/.config/waybar/scripts, and none of them is carried over.
#
# The include path is the one line that names a directory, and it names it
# through the variable rather than in full. It is not a command: Waybar reads it
# to find a file.
@test "no command of the bundle names a script file or a home directory" {
	run grep -nE '"(exec|exec-if|on-[a-z-]+)":.*(~|\$HOME|\.sh)' "$CONFIG_FILE"
	[ "$status" -ne 0 ]
	run grep -nE '\.sh([^a-z]|$)' "$CONFIG_FILE" "$STYLE_FILE"
	[ "$status" -ne 0 ]
}

# --- the order of an installation --------------------------------------------

# "The bar comes up styled immediately after installation, with no separate
# step." The installer links, detects, and renders, in that order, before the
# first session starts. This is that order, and it ends with every path the two
# prescribed files name reaching a file the renderer wrote.
@test "an installation leaves every path the bar reads in place" {
	run link_prescribed
	[ "$status" -eq 0 ]
	run "$XGHOST" machine detect
	[ "$status" -eq 0 ]
	run "$XGHOST" theme set tokyonight
	[ "$status" -eq 0 ]

	local resolved
	resolved=$(expanded_include)
	[ -f "$resolved" ]

	local name
	for name in colors knobs; do
		[ -f "$XDG_CONFIG_HOME/$BRIDGE_NAME/waybar/$name.css" ]
	done
}

# The other half of the order, and the reason it is an order rather than a
# preference. A GTK '@import' that reaches nothing is fatal, so a bar started
# between the link step and the render step would not come up at all. There is
# no optional import to soften that, the way the Ghostty bundle has a '?'.
@test "the imports of the style sheet reach nothing before the first render" {
	run link_prescribed
	[ "$status" -eq 0 ]

	local name
	for name in colors knobs; do
		[ ! -e "$XDG_CONFIG_HOME/$BRIDGE_NAME/waybar/$name.css" ]
	done

	run grep -n '?' "$STYLE_FILE"
	[ "$status" -ne 0 ]
}
