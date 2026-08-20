#!/usr/bin/env bats
#
# Tests for the Rofi bundle: the prescribed configuration under config/rofi and
# the templates under templates/rofi.
#
# No test here opens a window. Rofi is run in exactly two read-only forms, both
# of which print to standard output and return:
#
#   rofi -no-config -theme FILE -dump-theme   parse one file
#   rofi -dump-theme                          print the theme the launcher holds
#
# Every invocation goes through rofi_probe below, which removes DISPLAY and
# WAYLAND_DISPLAY, so no invocation of this suite can reach a compositor even if
# one is running. '-show' and '-modi' appear nowhere in this file. The machine
# this bundle was written on runs a live session, and a launcher started there
# would appear on it.
#
# The rule this suite is built around, and the reason the two forms above are
# not one:
#
#   Rofi exits 0 on a theme that fails to parse. The exit code proves nothing.
#   Empty standard error is the only reliable signal, and it is reliable only in
#   the first form: a file that fails to parse as the configuration of the
#   launcher reports nothing at all.
#
# docs/bundles/rofi.md records both, and the measurements behind them.
#
# The tests that run Rofi skip on a machine without it, which is the continuous
# integration runner. Everything those tests prove about the shipped files is
# proved again by reading the files, so a skipped run still fails on a bundle
# that is wrong.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	PRESCRIBED_DIR="$ROOT_DIR/config/rofi"
	CONFIG_FILE="$PRESCRIBED_DIR/config.rasi"
	TEMPLATE_DIR="$ROOT_DIR/templates/rofi"

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
	export XDG_DATA_HOME="$HOME/.local/share"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"

	# A render of the shipped templates needs the machine facts, because the
	# Hyprland bundle takes its monitor layout from them. No assertion below
	# reads a fact. tests/helpers.bash records the rule.
	use_fixed_machine_facts

	# The knobs are the third input, and one of them reaches the launcher. Every
	# test starts from a machine with no knobs file, so each knob holds the
	# default of schema/knobs.conf.
	use_own_knobs

	GENERATED="$XDG_STATE_HOME/xghost/generated"

	# The name 'xghost config link' gives the generated output inside the config
	# directory. The launcher reaches both generated files through it.
	BRIDGE_NAME=xghost-generated
}

# Link the prescribed configuration of the checkout into the config directory.
link_prescribed() {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config link
}

# Skip a test that needs Rofi on a machine that has none, which is the
# continuous integration runner.
require_rofi() {
	command -v rofi >/dev/null || skip "this machine has no rofi"
}

# The one way this suite runs Rofi.
#
# DISPLAY and WAYLAND_DISPLAY are removed, so the process cannot reach a
# compositor whatever it is asked to do. Every caller passes a dump flag, which
# prints and returns.
rofi_probe() {
	env -u DISPLAY -u WAYLAND_DISPLAY rofi "$@"
}

# Parse one file and print whatever Rofi says about it.
#
# This is the form that reports. A file given with '-theme' is parsed and a
# failure is a warning on standard error, so an empty standard error is the
# proof that the file is valid. The exit code is 0 either way, and a test below
# proves that.
parse_theme() {
	rofi_probe -no-config -theme "$1" -dump-theme
}

# Print the theme the launcher holds after it has read every file.
#
# This form reads the linked configuration out of XDG_CONFIG_HOME, so it is the
# one that shows whether the generated files reached the launcher. It reports
# nothing when they did not, which is why the assertions below read the theme it
# prints rather than the code it exits with.
dump_theme() {
	rofi_probe -dump-theme
}

# Print the value one theme declares for one palette name.
palette_value() {
	local theme=$1 name=$2
	sed -n "s/^$name=//p" "$ROOT_DIR/themes/$theme/palette.conf"
}

# Print 'r, g, b' of one '#rrggbb' value, which is the form '-dump-theme'
# prints a colour in.
rgb_of() {
	local hex=${1#\#}
	printf '%d, %d, %d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
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

# Print every '<name> <PALETTE_KEY>' pair the colour template declares.
#
# The pairs are read out of the template rather than listed in a test, so a
# palette name added to templates/rofi/colors.rasi later is covered on the day
# it is added.
template_colours() {
	sed -n 's/^[[:space:]]*\([a-z][a-z-]*\):[[:space:]]*@\([A-Z][A-Z0-9_]*\)@;.*/\1 \2/p' \
		"$TEMPLATE_DIR/colors.rasi"
}

# Print every colour the prescribed file names, one per line.
#
# The pattern reads a property value, so it passes over the two directives at
# the top of the file and over every word of every comment.
prescribed_colours() {
	grep -oE ':[[:space:]]*@[a-zA-Z][a-zA-Z0-9-]*' "$CONFIG_FILE" |
		sed 's/.*@//' | LC_ALL=C sort -u
}

# --- the prescribed configuration --------------------------------------------

@test "the Rofi configuration is prescribed configuration" {
	[ -f "$CONFIG_FILE" ]
	[ ! -L "$PRESCRIBED_DIR" ]

	# One prescribed file, and it is the one Rofi opens by name.
	run bash -c "find '$PRESCRIBED_DIR' -type f | LC_ALL=C sort | paste -sd, -"
	[ "$output" = "$CONFIG_FILE" ]
}

@test "'config link' places the Rofi configuration as a symbolic link" {
	run link_prescribed
	[ "$status" -eq 0 ]
	[ -L "$XDG_CONFIG_HOME/rofi" ]
	[ "$(readlink "$XDG_CONFIG_HOME/rofi")" = "$PRESCRIBED_DIR" ]
	[ -f "$XDG_CONFIG_HOME/rofi/config.rasi" ]
	[ -L "$XDG_CONFIG_HOME/$BRIDGE_NAME" ]
}

# The keybinding of the compositor runs the launcher, and the mode it asks for
# has to be a mode the prescribed configuration declares. The dotfiles this
# bundle comes from declared both, and 'rofi -show drun' is what the key runs.
@test "the launcher declares the mode the keybinding asks for" {
	local menu mode
	menu=$(sed -n 's/^\$menu[[:space:]]*=[[:space:]]*//p' \
		"$ROOT_DIR/config/hypr/hyprland.conf")
	[ -n "$menu" ]
	[[ $menu == "rofi -show "* ]]
	mode=${menu##* }

	run grep -E "^[[:space:]]*modi:.*\"[^\"]*$mode" "$CONFIG_FILE"
	[ "$status" -eq 0 ]
}

# --- the two generated files -------------------------------------------------

# There is exactly one '@theme', it comes first, and it names the colours.
#
# '@theme' discards the theme loaded so far. A second one would throw the first
# away, and one written under the blocks of the prescribed file would throw
# every one of them away and leave the launcher drawing the default theme of
# Rofi. Neither failure reports anything.
@test "the launcher loads the generated files, and it loads them in one order" {
	run grep -c '^@theme ' "$CONFIG_FILE"
	[ "$output" = "1" ]

	run grep -Fx '@theme "~/.config/xghost-generated/rofi/colors.rasi"' "$CONFIG_FILE"
	[ "$status" -eq 0 ]
	run grep -Fx '@import "~/.config/xghost-generated/rofi/knobs.rasi"' "$CONFIG_FILE"
	[ "$status" -eq 0 ]

	# The '@theme' is the first of the two.
	local first
	first=$(grep -nE '^@(theme|import) ' "$CONFIG_FILE" | head -1)
	[[ $first == *"@theme"* ]]

	# And both come before the first widget block, which is the window.
	local last_directive first_block
	last_directive=$(grep -nE '^@(theme|import) ' "$CONFIG_FILE" | tail -1 | cut -d: -f1)
	first_block=$(grep -n '^window {' "$CONFIG_FILE" | head -1 | cut -d: -f1)
	[ -n "$last_directive" ]
	[ -n "$first_block" ]
	[ "$last_directive" -lt "$first_block" ]
}

# The guard against the fault this bundle inherited. The dotfiles named
# '@border-width', '@border-radius', '@current-image' and '@color11' in the
# launcher, and the generated file beside it defined none of the four, so four
# values of every login resolved to nothing at all. Rofi reports no such thing.
#
# The names are read out of the prescribed file rather than listed here, so a
# name added later is covered on the day it is added.
@test "every colour the launcher names is defined by the generated palette" {
	"$XGHOST" theme set tokyonight >/dev/null
	local generated="$GENERATED/rofi/colors.rasi"
	[ -f "$generated" ]

	local name count=0
	while IFS= read -r name; do
		[ -n "$name" ] || continue
		run grep -E "^[[:space:]]*$name:" "$generated"
		[ "$status" -eq 0 ] || {
			printf 'the launcher names @%s and no generated file defines it\n' \
				"$name" >&2
			return 1
		}
		count=$((count + 1))
	done < <(prescribed_colours)
	[ "$count" -gt 0 ]
}

# The rule of this bundle, in the direction Rofi reads. The prescribed file is
# parsed after both generated files, so a colour or a font written here would
# win over the theme and over the knob, and the launcher would look the same
# whatever either one held.
@test "the prescribed file names no colour and no font of its own" {
	run grep -nE '#[0-9a-fA-F]{3,8}' "$CONFIG_FILE"
	[ "$status" -ne 0 ]

	# One font family reaches the launcher, and it is written in one file of the
	# whole project. The pattern is not anchored to the start of a line: a
	# property written after a brace on one line would evade an anchored one,
	# and it would win on nothing more than being parsed last.
	local guard='(^|[{;[:space:]])font[[:space:]]*:'
	run bash -c "cd '$ROOT_DIR' && grep -rlE '$guard' config templates | LC_ALL=C sort | paste -sd, -"
	[ "$output" = "templates/rofi/knobs.rasi" ]

	# And the guard fires on that evasion. It is written into a copy: no test of
	# this project writes into the checkout.
	local copy="$BATS_TEST_TMPDIR/evasion"
	mkdir -p "$copy"
	cp -R "$ROOT_DIR/config" "$ROOT_DIR/templates" "$copy/"
	printf 'window { font: "Comic Sans 11"; }\n' >>"$copy/config/rofi/config.rasi"
	run bash -c "cd '$copy' && grep -rlE '$guard' config templates | LC_ALL=C sort | paste -sd, -"
	[ "$output" = "config/rofi/config.rasi,templates/rofi/knobs.rasi" ]
}

@test "the generated palette carries every colour of every theme" {
	local theme name key value count=0
	while IFS= read -r theme; do
		[ -n "$theme" ] || continue
		"$XGHOST" theme set "$theme" >/dev/null
		while read -r name key; do
			value=$(palette_value "$theme" "$key")
			[ -n "$value" ]
			run grep -Fx "    $name:          $value;" "$GENERATED/rofi/colors.rasi"
			[ "$status" -eq 0 ] || {
				run grep -E "^[[:space:]]*$name:[[:space:]]*$value;" \
					"$GENERATED/rofi/colors.rasi"
				[ "$status" -eq 0 ]
			}
			count=$((count + 1))
		done < <(template_colours)
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

# A name of this language holds letters, digits and hyphens. An underscore is a
# parse error, and the whole file is then dropped. The palette keys of this
# project hold underscores, so the template converts them, and this is the guard
# that the conversion was not forgotten.
@test "no name of the generated palette holds an underscore" {
	local name key count=0
	while read -r name key; do
		[[ $name != *_* ]] || {
			printf 'the template declares %s, and an underscore is a parse error\n' \
				"$name" >&2
			return 1
		}
		count=$((count + 1))
	done < <(template_colours)
	[ "$count" -gt 0 ]

	run grep -nE '^[[:space:]]*[a-z0-9-]*_[a-z0-9_-]*:' "$CONFIG_FILE"
	[ "$status" -ne 0 ]
}

@test "no template of the launcher names a machine fact" {
	run grep -rn 'MACHINE_' "$TEMPLATE_DIR"
	[ "$status" -ne 0 ]
}

# --- the path to the generated output ----------------------------------------

# The measurement this bundle exists around. Rofi tests a relative import for
# existence against the path the kernel resolves, and opens the path it
# canonicalises itself. The prescribed file is opened through the symbolic link
# 'xghost config link' made, so the two disagree and the import is dropped
# without a word. The path is therefore written from the home directory.
# docs/bundles/rofi.md and ADR 0002 both record it.
@test "no import of the launcher is relative, and none names the state directory" {
	local line count=0
	while IFS= read -r line; do
		[[ $line != *"../"* ]]
		[[ $line != *".local/state"* ]]
		[[ $line != *'$'* ]]
		[[ $line == *"$BRIDGE_NAME"* ]]
		count=$((count + 1))
	done < <(grep -E '^@(theme|import) ' "$CONFIG_FILE")
	[ "$count" -eq 2 ]
}

@test "the imports reach the files the renderer writes" {
	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local name resolved
	for name in colors knobs; do
		resolved="$HOME/.config/$BRIDGE_NAME/rofi/$name.rasi"
		[ -f "$resolved" ]
		[ "$resolved" -ef "$GENERATED/rofi/$name.rasi" ]
	done
}

# The renderer follows XDG_STATE_HOME and the import reaches the state directory
# through the bridge, so a machine that moved that variable keeps a themed
# launcher. This is the half of ADR 0002 that this bundle still holds, and the
# Confirmation section of that ADR asks every bundle for a case like it.
@test "the imports reach the generated files when XDG_STATE_HOME is not the default" {
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local name resolved
	for name in colors knobs; do
		resolved="$HOME/.config/$BRIDGE_NAME/rofi/$name.rasi"
		[ -f "$resolved" ]
		[ "$resolved" -ef "$XDG_STATE_HOME/xghost/generated/rofi/$name.rasi" ]
	done
}

# The other half, which this bundle does not hold, and the page that records it.
# The import names the default of the XDG base directory specification, so a
# machine that moved XDG_CONFIG_HOME has a launcher that reaches nothing. It is
# written down rather than hidden, and this test fails if the page stops saying
# so.
@test "the bundle page records the one variable the launcher does not follow" {
	local page="$ROOT_DIR/docs/bundles/rofi.md"
	[ -f "$page" ]
	run grep -c 'XDG_CONFIG_HOME' "$page"
	[ "$status" -eq 0 ]
	[ "$output" -gt 0 ]
	run grep -F 'xghost doctor' "$page"
	[ "$status" -eq 0 ]
}

# --- the knob ----------------------------------------------------------------

# The theme is set first, and that is the precondition rather than a detail:
# 'xghost settings set' renders only when a theme is active. docs/knobs.md
# records it, and the knob test of every other bundle opens the same way.
@test "the font knob reaches the launcher at every value the schema names" {
	"$XGHOST" theme set tokyonight >/dev/null

	local value count=0
	while IFS= read -r value; do
		run "$XGHOST" settings set KNOB_FONT "$value"
		[ "$status" -eq 0 ]
		[ -f "$GENERATED/rofi/knobs.rasi" ]
		run grep -Fx "    font: \"$value 11\";" "$GENERATED/rofi/knobs.rasi"
		[ "$status" -eq 0 ]
		count=$((count + 1))
	done < <(schema_values KNOB_FONT)
	[ "$count" -gt 1 ]
}

# --- the order of an installation --------------------------------------------

# "The launcher opens themed immediately after installation." The installer
# links, detects, and renders, in that order, before the first session starts.
# docs/installing.md records that order. This is that order, and it ends with
# every path the prescribed file names reaching a file the renderer wrote.
@test "an installation leaves every path the launcher reads in place" {
	run link_prescribed
	[ "$status" -eq 0 ]
	run "$XGHOST" machine detect
	[ "$status" -eq 0 ]
	run "$XGHOST" theme set tokyonight
	[ "$status" -eq 0 ]

	local name
	for name in colors knobs; do
		[ -f "$HOME/.config/$BRIDGE_NAME/rofi/$name.rasi" ]
	done
}

# The other half of the order. A launcher started between the link step and the
# render step reaches neither generated file, and Rofi says nothing about it:
# there is no optional import in this bundle, because the one Rofi offers is
# broken. docs/bundles/rofi.md records the measurement.
@test "the imports reach nothing before the first render" {
	run link_prescribed
	[ "$status" -eq 0 ]

	local name
	for name in colors knobs; do
		[ ! -e "$HOME/.config/$BRIDGE_NAME/rofi/$name.rasi" ]
	done

	run grep -n '^?import' "$CONFIG_FILE"
	[ "$status" -ne 0 ]
}

# --- what Rofi itself says ---------------------------------------------------

# Criterion 4 of issue #13. Every file of this bundle is parsed by Rofi, and the
# proof that it parsed is that Rofi said nothing.
@test "every file of the bundle parses, and empty standard error is the proof" {
	require_rofi
	"$XGHOST" theme set tokyonight >/dev/null

	local file count=0
	for file in "$CONFIG_FILE" "$GENERATED/rofi/colors.rasi" \
		"$GENERATED/rofi/knobs.rasi"; do
		[ -f "$file" ]
		run --separate-stderr parse_theme "$file"
		[ "$stderr" = "" ] || {
			printf '%s: %s\n' "${file##*/}" "$stderr" >&2
			return 1
		}
		count=$((count + 1))
	done
	[ "$count" -eq 3 ]
}

# The reason the test above reads standard error rather than the exit code, and
# the reason it uses '-theme' rather than the launcher's own configuration path.
# Both are measurements of Rofi 2.0.0 rather than opinions, so both are pinned:
# a release that starts reporting a failure through the exit code would fail
# here and send the reader to docs/bundles/rofi.md.
@test "a theme that cannot be parsed still exits zero, and reports on standard error" {
	require_rofi

	# An underscore in a name. It is the mistake this project is closest to
	# making, because every palette key of every theme holds one.
	local broken="$BATS_TEST_TMPDIR/broken.rasi"
	printf '* {\n    text_muted: #A9B1D6;\n}\n' >"$broken"

	run --separate-stderr parse_theme "$broken"
	[ "$status" -eq 0 ]
	[ -n "$stderr" ]
	[[ $stderr == *"Failed to parse theme"* ]]
}

# The same broken file, read the way the launcher reads its own configuration.
# Nothing is reported, and that is why the check above exists in the form it
# does. A test that ran the launcher against its own configuration and asserted
# on standard error would pass on every broken file this project could ship.
@test "the same failure reports nothing when the file is the launcher's own configuration" {
	require_rofi

	local own="$BATS_TEST_TMPDIR/own/rofi"
	mkdir -p "$own"
	printf '* {\n    text_muted: #A9B1D6;\n}\nwindow { width: 1em; }\n' \
		>"$own/config.rasi"

	XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/own" run --separate-stderr dump_theme
	[ "$status" -eq 0 ]
	[ "$stderr" = "" ]
}

# The launcher, after it has read every file, holds the palette of the active
# theme and no other colour at all.
#
# This is the assertion that a passing parse cannot make. A launcher whose
# imports reached nothing parses clean, reports nothing, exits 0, and comes up
# looking wrong. What it cannot do is hold these values.
@test "the launcher holds the palette of the active theme and no other colour" {
	require_rofi

	local theme count=0
	while IFS= read -r theme; do
		[ -n "$theme" ] || continue
		run link_prescribed
		[ "$status" -eq 0 ]
		"$XGHOST" theme set "$theme" >/dev/null

		run --separate-stderr dump_theme
		[ "$status" -eq 0 ]
		[ "$stderr" = "" ]

		local name key value colours=0
		while read -r name key; do
			value=$(palette_value "$theme" "$key")
			[ -n "$value" ]
			[[ $output == *"$name:"*"rgba ( $(rgb_of "$value"), 100 % );"* ]] || {
				printf 'the launcher does not hold %s of the theme %s\n' \
					"$name" "$theme" >&2
				return 1
			}
			colours=$((colours + 1))
		done < <(template_colours)
		[ "$colours" -gt 0 ]

		# And it holds no colour beyond them. A literal colour is written out as
		# 'rgba ( ... )', so counting them counts every colour the launcher can
		# draw with, whichever file it came from.
		local literals
		literals=$(printf '%s\n' "$output" | grep -c 'rgba (' || true)
		[ "$literals" -eq "$colours" ] || {
			printf 'the launcher holds %s colours and the palette declares %s\n' \
				"$literals" "$colours" >&2
			return 1
		}
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 1 ]
}

# The font the launcher holds is the knob, read back out of the launcher rather
# than out of the file the renderer wrote.
@test "the launcher holds the font family the knob names" {
	require_rofi

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	run --separate-stderr dump_theme
	[ "$stderr" = "" ]
	[[ $output == *'font:'*'"JetBrainsMono Nerd Font 11"'* ]]

	run "$XGHOST" settings set KNOB_FONT 'CaskaydiaCove Nerd Font'
	[ "$status" -eq 0 ]
	run --separate-stderr dump_theme
	[ "$stderr" = "" ]
	[[ $output == *'font:'*'"CaskaydiaCove Nerd Font 11"'* ]]
}

# The failure this bundle is built to prevent, shown happening. After the link
# step and before the render step the launcher parses clean, reports nothing,
# and holds none of the palette. It is the state a first session would find if
# the render step were ever moved after it.
@test "before the first render the launcher holds none of the palette" {
	require_rofi

	run link_prescribed
	[ "$status" -eq 0 ]

	run --separate-stderr dump_theme
	[ "$status" -eq 0 ]
	[ "$stderr" = "" ]

	local name key
	while read -r name key; do
		[[ $output != *"$name:"*"rgba ("* ]]
	done < <(template_colours)
}
