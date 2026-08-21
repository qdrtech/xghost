#!/usr/bin/env bats
#
# Tests for the SwayNC bundle: the prescribed configuration under config/swaync
# and the templates under templates/swaync.
#
# No test here starts SwayNC, and none may. The machine this bundle was written
# on runs a live session with a notification daemon of its own, and a second
# daemon takes the D-Bus name from it. 'swaync' with any argument starts one,
# '-c' included, and 'swaync-client -rs' reloads the one that is running. None
# of the three appears below.
#
# What is proved instead is the half of the journey that can be measured without
# a daemon. GTK 4 parses a style sheet without a window and without a
# compositor, so the import of this bundle is followed the way GTK follows it,
# and the palette of the active theme is read back out of the provider. That is
# the shape docs/adr/0002-the-bridge-to-the-generated-output.md asks every bundle
# for: read back the state the application holds, never the code it exits with.
#
# Two rules of this bundle are what most of these tests are about:
#
#   - A rule of the importing file wins over a rule of the same weight in the
#     file it imported, so a property the generated files set must be absent
#     from the prescribed style sheet.
#   - A GTK4 '@import' that reaches nothing is silent. It is not fatal, the way
#     the GTK3 one of the bar is. So the render has to run before the first
#     session, and nothing at all reports it when it did not.
#
# The design of the bundle is recorded in docs/bundles/swaync.md.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	PRESCRIBED_DIR="$ROOT_DIR/config/swaync"
	CONFIG_FILE="$PRESCRIBED_DIR/config.json"
	STYLE_FILE="$PRESCRIBED_DIR/style.css"
	TEMPLATE_DIR="$ROOT_DIR/templates/swaync"
	GOLDEN_DIR="$BATS_TEST_DIRNAME/golden"

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

	# The knobs are the third input, and one of them reaches this bundle. Every
	# test starts from a machine with no knobs file, so each knob holds the
	# default of schema/knobs.conf.
	use_own_knobs

	GENERATED="$XDG_STATE_HOME/xghost/generated"

	# The name 'xghost config link' gives the generated output inside the config
	# directory. The style sheet reaches the generated output through it.
	BRIDGE_NAME=xghost-generated
}

# Link the prescribed configuration of the checkout into the config directory.
link_prescribed() {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config link
}

# Print the prescribed configuration with its comments dropped.
#
# SwayNC parses that file with json-glib, which allows a comment wherever white
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

# Load one style sheet into a GTK4 CssProvider and print what the provider
# holds afterwards.
#
# This is the one place a real GTK reads a file of this bundle. It parses
# without a window and without a compositor, so it starts no daemon and it
# touches no session. 'to_string' prints the rules the provider holds after
# every '@import' has been followed, so an import that resolved shows up as the
# text it pulled in rather than as the absence of an error.
#
# A parsing error is delivered on a signal rather than through the return value.
# Each one is printed with an 'ERROR' prefix, and a test that wants the silence
# of GTK4 asserts on that prefix being absent.
gtk4_css() {
	local sheet=$1
	local script="$BATS_TEST_TMPDIR/cssprobe.py"

	cat >"$script" <<-'EOF'
		import sys
		import gi
		gi.require_version("Gtk", "4.0")
		from gi.repository import Gtk

		provider = Gtk.CssProvider()
		provider.connect(
		    "parsing-error",
		    lambda p, section, error: print("ERROR %s: %s" % (section.to_string(), error.message)),
		)
		provider.load_from_path(sys.argv[1])
		print(provider.to_string())
	EOF
	python3 "$script" "$sheet"
}

# Skip the calling test when this machine has no GTK4 for Python.
#
# The bindings are not a dependency of xghost and no manifest declares them, so
# a machine without them is a machine this suite still has to run on. The skip
# names what went unproved rather than passing quietly.
require_gtk4() {
	if ! command -v python3 >/dev/null 2>&1; then
		skip "no python3, so the GTK4 parse of the style sheet is unproved"
	fi
	if ! python3 -c 'import gi; gi.require_version("Gtk", "4.0"); from gi.repository import Gtk' \
		>/dev/null 2>&1; then
		skip "no GTK4 bindings for Python, so the GTK4 parse of the style sheet is unproved"
	fi
}

@test "the SwayNC configuration is prescribed configuration" {
	[ -f "$CONFIG_FILE" ]
	[ -f "$STYLE_FILE" ]
	[ ! -L "$PRESCRIBED_DIR" ]
}

@test "'config link' places the SwayNC configuration as a symbolic link" {
	run link_prescribed
	[ "$status" -eq 0 ]
	[ -L "$XDG_CONFIG_HOME/swaync" ]
	[ "$(readlink "$XDG_CONFIG_HOME/swaync")" = "$PRESCRIBED_DIR" ]
	[ -f "$XDG_CONFIG_HOME/swaync/config.json" ]
	[ -f "$XDG_CONFIG_HOME/swaync/style.css" ]
	[ -L "$XDG_CONFIG_HOME/$BRIDGE_NAME" ]
}

# --- the configuration file --------------------------------------------------

@test "the prescribed configuration is one JSON document" {
	run json_value "$(prescribed_json)" .
	[ "$status" -eq 0 ]
	[[ $output == "object of "* ]]

	run json_value "$(prescribed_json)" widgets.0
	[ "$status" -eq 0 ]
	[ "$output" = "mpris" ]
}

# Every comment of the file is a whole line. A comment that followed a value on
# its line would leave the helper above producing text that is not the document
# SwayNC reads, and every assertion of this file would then be about something
# else.
@test "every comment of the prescribed configuration is a whole line" {
	run grep -n '//' "$CONFIG_FILE"
	[ "$status" -eq 0 ]
	local line
	while IFS= read -r line; do
		[[ ${line#*:} =~ ^[[:space:]]*// ]]
	done <<<"$output"
}

# The decision of this bundle, held in place from the other side.
#
# SwayNC has no include mechanism, so a setting of this file that followed a
# theme, a knob or a machine fact could not be generated and delivered without a
# mechanism nothing here builds. The file is prescribed because no setting does.
# The day one appears, this fails, and docs/bundles/swaync.md records what to do
# about it.
@test "the prescribed configuration names no theme value, no knob and no fact" {
	run grep -n 'KNOB_' "$CONFIG_FILE"
	[ "$status" -ne 0 ]
	run grep -n 'MACHINE_' "$CONFIG_FILE"
	[ "$status" -ne 0 ]

	# No colour of any spelling, and no name the palette declares.
	run grep -nE '#[0-9a-fA-F]{3,8}' "$CONFIG_FILE"
	[ "$status" -ne 0 ]

	local name count=0
	while IFS= read -r name; do
		[ -n "$name" ] || continue
		run grep -nF "$name" "$CONFIG_FILE"
		[ "$status" -ne 0 ] || {
			printf 'the prescribed configuration names the palette value %s, which no include can reach it\n' \
				"$name" >&2
			return 1
		}
		count=$((count + 1))
	done < <(sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' "$ROOT_DIR/themes/tokyonight/palette.conf")
	[ "$count" -gt 0 ]
}

# The one file of this project that holds the renderer's own spelling and must
# never be read by the renderer.
#
# 'wpctl' names the default audio device '@DEFAULT_AUDIO_SINK@', which is an
# upper case name between two '@' and therefore exactly what the renderer
# substitutes. A template holding that line would fail the render by name,
# because no palette, no fact and no knob declares it.
@test "the audio buttons hold a name the renderer would substitute, in no template" {
	local placeholder
	for placeholder in '@DEFAULT_AUDIO_SINK@' '@DEFAULT_AUDIO_SOURCE@'; do
		run grep -Fn "$placeholder" "$CONFIG_FILE"
		[ "$status" -eq 0 ]
		run bash -c "cd '$ROOT_DIR' && grep -rlF '$placeholder' templates"
		[ "$status" -ne 0 ]
	done
}

# The two buttons that mute use the tool the keybindings use. The dotfiles used
# 'pactl', which is in libpulse and which no manifest of this project declares.
@test "the audio buttons use the tool the keybindings use" {
	local tool
	tool=$(sed -n 's/^bindel[[:space:]]*=.*exec,[[:space:]]*\([a-z]*\)[[:space:]].*/\1/p' \
		"$ROOT_DIR/config/hypr/conf/keybinding.conf" | head -1)
	[ -n "$tool" ]

	local command
	command=$(json_value "$(prescribed_json)" 'widget-config.buttons-grid.actions.0.command')
	[[ $command == "$tool "* ]]
	command=$(json_value "$(prescribed_json)" 'widget-config.buttons-grid.actions.1.command')
	[[ $command == "$tool "* ]]

	run grep -n 'pactl' "$CONFIG_FILE"
	[ "$status" -ne 0 ]
}

# The button that opens a terminal opens the terminal of this desktop, read from
# the file that names it rather than written out twice. The dotfiles opened
# kitty, which this desktop does not ship at all.
@test "the button that opens a terminal opens the terminal of this desktop" {
	local terminal
	terminal=$(sed -n 's/^\$terminal[[:space:]]*=[[:space:]]*//p' \
		"$ROOT_DIR/config/hypr/hyprland.conf")
	[ -n "$terminal" ]

	run grep -Fn "\"$terminal " "$CONFIG_FILE"
	[ "$status" -eq 0 ]

	run grep -n 'kitty' "$CONFIG_FILE"
	[ "$status" -ne 0 ]
}

# A widget configured and never listed draws nothing at all. The dotfiles
# configured a 'label' widget that no list named, so the text in it was never
# seen. This reads the two halves against each other rather than naming either.
@test "every widget the configuration configures is a widget it draws" {
	local listed index name size
	size=$(json_value "$(prescribed_json)" widgets)
	[[ $size == "array of "* ]]

	listed=
	index=0
	while name=$(json_value "$(prescribed_json)" "widgets.$index"); do
		listed="$listed $name"
		index=$((index + 1))
	done
	[ "$index" -gt 0 ]

	local count=0
	while IFS= read -r name; do
		[ -n "$name" ] || continue
		[[ " $listed " == *" $name "* ]] || {
			printf 'widget-config configures %s, which no widget list names, so it draws nothing\n' \
				"$name" >&2
			return 1
		}
		count=$((count + 1))
	done < <(sed -n 's/^    "\([a-z0-9-]*\)": {$/\1/p' "$CONFIG_FILE")
	[ "$count" -gt 0 ]
}

# A prescribed file cannot write its own location, so every command of this
# bundle names a program on the PATH. The dotfiles shipped a 'refresh.sh' beside
# this configuration, and three buttons ran shell functions of their author.
@test "no command of the bundle names a script file or a home directory" {
	run grep -nE '"command":.*(~|\$HOME|\.sh)' "$CONFIG_FILE"
	[ "$status" -ne 0 ]
	run grep -nE '\.sh([^a-z]|$)' "$CONFIG_FILE" "$STYLE_FILE"
	[ "$status" -ne 0 ]
	run grep -nE 'bash -i' "$CONFIG_FILE"
	[ "$status" -ne 0 ]
}

# --- the style sheet ---------------------------------------------------------

@test "the style sheet imports the generated files through the bridge" {
	local name
	for name in colors knobs; do
		run grep -Fx "@import \"../$BRIDGE_NAME/swaync/$name.css\";" "$STYLE_FILE"
		[ "$status" -eq 0 ]
	done

	# GTK expands neither a variable nor '~' in an '@import', so a path that
	# named either would reach nothing, and GTK4 reaches nothing in silence.
	run grep -nE '^[[:space:]]*@import.*(~|\$)' "$STYLE_FILE"
	[ "$status" -ne 0 ]

	# Every import comes before the first rule. A colour has to be defined
	# before a rule names it, and a rule of this file wins over a rule of the
	# same weight above it.
	local first_import first_rule
	first_import=$(grep -n '^@import' "$STYLE_FILE" | head -1 | cut -d: -f1)
	first_rule=$(grep -nE '^[^ /*@}].*\{' "$STYLE_FILE" | head -1 | cut -d: -f1)
	[ -n "$first_import" ]
	[ -n "$first_rule" ]
	[ "$first_import" -lt "$first_rule" ]
}

# GTK resolves a relative '@import' against the directory of the file that
# imports it, and SwayNC opens the style sheet at the path 'xghost config link'
# created. '..' is therefore the config directory of the user, where the bridge
# is.
#
# Both XDG paths are moved, which is the case the Confirmation section of
# ADR 0002 asks every bundle after Ghostty for by name. The renderer follows
# XDG_STATE_HOME and the import is resolved against XDG_CONFIG_HOME, so the two
# ends have to be right at once. A home directory built out of defaults can
# never show that divergence.
@test "the import of the style sheet reaches the file the renderer writes" {
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]
	"$XGHOST" theme set tokyonight >/dev/null

	local opened="$XDG_CONFIG_HOME/swaync"
	local resolved="${opened%/*}/$BRIDGE_NAME/swaync/colors.css"
	[ -f "$resolved" ]
	[ "$resolved" -ef "$XDG_STATE_HOME/xghost/generated/swaync/colors.css" ]
	run grep -Fx "@define-color bg $(palette_value tokyonight BG);" "$resolved"
	[ "$status" -eq 0 ]
}

# The measurement, rather than the reasoning. GTK 4 loads the style sheet at the
# path SwayNC opens, follows the '@import' the way it will follow it in the
# daemon, and the provider then holds the palette of the active theme.
#
# 'xghost config link' makes '$XDG_CONFIG_HOME/swaync' a symbolic link into the
# checkout, so this is also what proves that GTK applies the '..' lexically. A
# '..' applied physically would land in the checkout, where ADR 0002 forbids
# generated output to be, and the import would reach nothing.
@test "GTK4 reads the palette of the theme through the linked style sheet" {
	require_gtk4

	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run link_prescribed
	[ "$status" -eq 0 ]

	local theme count=0
	while IFS= read -r theme; do
		[ -n "$theme" ] || continue
		"$XGHOST" theme set "$theme" >/dev/null

		run gtk4_css "$XDG_CONFIG_HOME/swaync/style.css"
		[ "$status" -eq 0 ]
		[[ $output != *ERROR* ]]

		# The palette of this theme, as GTK holds it after the import. GTK
		# prints a colour in its own decimal form, so the expected text is
		# built from the palette rather than copied out of it.
		local name hex expected
		for name in BG SURFACE TEXT ACCENT ERROR; do
			hex=$(palette_value "$theme" "$name")
			printf -v expected '@define-color %s rgb(%d,%d,%d);' \
				"$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" \
				"0x${hex:1:2}" "0x${hex:3:2}" "0x${hex:5:2}"
			[[ $output == *"$expected"* ]] || {
				printf 'GTK4 holds no %s for the theme %s after the import\n' \
					"$name" "$theme" >&2
				return 1
			}
		done

		# And the font family of the second import, which is a second file
		# through the same bridge.
		[[ $output == *'JetBrainsMono Nerd Font'* ]]
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 1 ]
}

# A GTK colour that no file defines is a colour the style sheet cannot draw
# with, and this style sheet defines none of its own. The dotfiles this bundle
# comes from named three colours with hyphens that their generated file defined
# with underscores, which is the fault this test exists for.
#
# The pattern carries the hyphen, and that is the point of it. GTK allows '-' in
# the identifier of an '@define-color', so '@accent-alt' is one name. A pattern
# that stopped at the hyphen would read it as '@accent', find 'accent' in the
# palette, and pass. Nothing downstream catches that: a Gtk.CssProvider that
# loads a sheet naming an undefined colour reports no error at all, not even on
# the signal, which is how the three names above went unnoticed through every
# login.
@test "every colour the style sheet names is defined by the generated palette" {
	"$XGHOST" theme set tokyonight >/dev/null
	local generated="$GENERATED/swaync/colors.css"
	[ -f "$generated" ]

	local name count=0
	while IFS= read -r name; do
		case $name in import | keyframes | define-color) continue ;; esac
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

	# The one colour written out is the black of a shadow, which is a colour of
	# this style sheet rather than of any theme.
	run grep -nE '#[0-9a-fA-F]{3,8}' "$STYLE_FILE"
	[ "$status" -ne 0 ]
}

# An eight-digit hex in a palette is a colour GTK cannot parse in an
# '@define-color', and the import that carries it is dropped. GTK4 says nothing
# about it, so the notification centre draws in the packaged colours and no line
# anywhere records why.
#
# The names are read out of the template rather than listed here, so a palette
# name added to templates/swaync/colors.css later is covered on the day it is
# added.
@test "every palette value the centre imports is a six-digit hex" {
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
				printf 'the theme %s declares no %s, which the centre imports\n' \
					"$theme" "$name" >&2
				return 1
			}
			[[ $value =~ ^#[0-9a-fA-F]{6}$ ]] || {
				printf 'the theme %s writes %s=%s; GTK cannot parse it and the import is dropped\n' \
					"$theme" "$name" "$value" >&2
				return 1
			}
			count=$((count + 1))
		done <<<"$names"
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

# --- the knobs ---------------------------------------------------------------

# The font of the notification centre is the font of the desktop. A family in
# the style sheet would win over the generated one, because a rule of the
# importing file wins over a rule of the file it imported.
@test "the font knob reaches the centre and the style sheet names no family" {
	"$XGHOST" theme set tokyonight >/dev/null

	local value count=0
	while IFS= read -r value; do
		[ -n "$value" ] || continue
		run "$XGHOST" settings set KNOB_FONT "$value"
		[ "$status" -eq 0 ]
		[ -f "$GENERATED/swaync/knobs.css" ]
		run grep -F "font-family: \"$value\", sans-serif;" "$GENERATED/swaync/knobs.css"
		[ "$status" -eq 0 ]
		count=$((count + 1))
	done < <(schema_values KNOB_FONT)
	[ "$count" -gt 1 ]

	# The prescribed style sheet of this bundle names no family at all.
	#
	# The pattern is not anchored to the start of a line. A rule written on one
	# line, '.summary { font-family: "Comic Sans"; }', holds the property after
	# a brace rather than after white space alone, and an anchored pattern reads
	# that file as one that names no family. Such a rule wins on specificity
	# over the '*' of the generated file, so the knob would reach the centre and
	# change nothing anyone can see.
	local guard='(^|[{;[:space:]])font-family[[:space:]]*:'
	run bash -c "cd '$ROOT_DIR' && grep -rlE '$guard' config templates | LC_ALL=C sort | paste -sd, -"
	[[ $output == *"templates/swaync/knobs.css"* ]]
	[[ $output != *"config/swaync/"* ]]

	# And the guard fires on that evasion. It is written into a copy: no test of
	# this project writes into the checkout.
	local copy="$BATS_TEST_TMPDIR/evasion"
	mkdir -p "$copy"
	cp -R "$ROOT_DIR/config" "$ROOT_DIR/templates" "$copy/"
	printf '.summary { font-family: "Comic Sans"; }\n' >>"$copy/config/swaync/style.css"
	run bash -c "cd '$copy' && grep -rlE '$guard' config templates | LC_ALL=C sort | paste -sd, -"
	[[ $output == *"config/swaync/style.css"* ]]
}

# MACHINE_TERMINAL is 'unknown' on a machine that declares no default terminal,
# and the renderer refuses to write that word. Nothing of this bundle reaches
# for a fact, and this proves it for a template added later as well.
@test "no template of the centre names a machine fact" {
	run grep -rn 'MACHINE_' "$TEMPLATE_DIR"
	[ "$status" -ne 0 ]
}

# --- the committed golden output ---------------------------------------------

# Criterion 4 of issue #14. tests/golden.bats proves that every template of the
# project has committed output for every theme at every knob set, and it
# compares a render against it. This reads the committed text of this bundle
# directly, so the palette of each theme and both values of the font knob are
# pinned to a file rather than to a render that could agree with a broken
# template.
@test "the committed golden output holds the SwayNC palette of every theme" {
	local set theme name hex count=0
	for set in default alternate; do
		while IFS= read -r theme; do
			[ -n "$theme" ] || continue
			local colours="$GOLDEN_DIR/$set/$theme/swaync/colors.css"
			[ -f "$colours" ]
			for name in BG SURFACE SURFACE_ALT TEXT TEXT_MUTED ACCENT ACCENT_ALT WARN ERROR SUCCESS; do
				hex=$(palette_value "$theme" "$name")
				[ -n "$hex" ]
				run grep -Fx "@define-color $(printf '%s' "$name" | tr '[:upper:]' '[:lower:]') $hex;" \
					"$colours"
				[ "$status" -eq 0 ] || {
					printf 'the golden output of %s/%s carries no %s\n' \
						"$set" "$theme" "$name" >&2
					return 1
				}
			done
			count=$((count + 1))
		done < <("$XGHOST" theme list)
	done
	[ "$count" -gt 1 ]
}

# The two knob sets differ in this bundle, so the font knob is proved to reach
# it against committed text. A knob that reached no file of this bundle would
# write the same family into both trees.
@test "the two golden knob sets carry the two families of the font knob" {
	local theme count=0
	while IFS= read -r theme; do
		[ -n "$theme" ] || continue
		run grep -F 'font-family: "JetBrainsMono Nerd Font", sans-serif;' \
			"$GOLDEN_DIR/default/$theme/swaync/knobs.css"
		[ "$status" -eq 0 ]
		run grep -F 'font-family: "CaskaydiaCove Nerd Font", sans-serif;' \
			"$GOLDEN_DIR/alternate/$theme/swaync/knobs.css"
		[ "$status" -eq 0 ]
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 1 ]
}

# --- the order of an installation --------------------------------------------

# "Notifications appear styled immediately after installation." The installer
# links, detects, and renders, in that order, before the first session starts.
# This is that order, and it ends with every path the daemon reads reaching a
# file.
#
# The compositor then starts the daemon, so the autostart line is part of the
# same claim and is read here.
@test "an installation leaves every path the notification centre reads in place" {
	run link_prescribed
	[ "$status" -eq 0 ]
	run "$XGHOST" machine detect
	[ "$status" -eq 0 ]
	run "$XGHOST" theme set tokyonight
	[ "$status" -eq 0 ]

	[ -f "$XDG_CONFIG_HOME/swaync/config.json" ]
	[ -f "$XDG_CONFIG_HOME/swaync/style.css" ]

	local name
	for name in colors knobs; do
		[ -f "$XDG_CONFIG_HOME/$BRIDGE_NAME/swaync/$name.css" ]
	done

	run grep -Fx 'exec-once = swaync' "$ROOT_DIR/config/hypr/conf/autostart.conf"
	[ "$status" -eq 0 ]
}

# The other half of the order, and the difference from the bar.
#
# A GTK3 '@import' that reaches nothing stops Waybar, so a bar started too early
# is a bar nobody can overlook. The GTK4 one is silent: the sheet loads, the
# daemon starts, and it draws in the packaged colours. Nothing reports it, which
# is why the order is a requirement rather than a preference.
@test "the imports reach nothing before the first render, and GTK4 says so to nobody" {
	run link_prescribed
	[ "$status" -eq 0 ]

	local name
	for name in colors knobs; do
		[ ! -e "$XDG_CONFIG_HOME/$BRIDGE_NAME/swaync/$name.css" ]
	done

	require_gtk4

	# The sheet still loads. The failure is delivered on the 'parsing-error'
	# signal, which this helper connects and the daemon need not.
	run gtk4_css "$XDG_CONFIG_HOME/swaync/style.css"
	[ "$status" -eq 0 ]
	[[ $output == *"Failed to import"* ]]

	# And the palette is simply absent, so every rule that names a colour draws
	# with nothing.
	[[ $output != *"@define-color bg"* ]]
}
