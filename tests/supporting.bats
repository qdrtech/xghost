#!/usr/bin/env bats
#
# Tests for the supporting bundles: the prescribed configuration under
# config/gtk-3.0, config/hyprshade and config/yay, and the template under
# templates/gtk.
#
# No test here opens a window, applies a shader, or installs a package. The
# machine this bundle was written on runs a live session, and all three of
# those would have reached it.
#
#   - GTK is read through Gtk.CssProvider, which parses a style sheet and
#     returns. It needs no display and it draws nothing.
#   - hyprshade is never run. Its schedule is read as TOML and checked against
#     the rules its own validator applies, and its shader directory is read.
#     'hyprshade on', 'off' and 'auto' each apply a shader to the running
#     compositor and appear nowhere in this file.
#   - yay is never run. 'pacman' is read with '-Si', '-Fl' and '-Ql', which
#     query the databases and change nothing.
#
# Two rules this suite is built around, and docs/bundles/supporting.md records
# the measurement behind each:
#
#   A GTK colour that no file defines is dropped in silence. A provider that
#   loads such a sheet reports success, so an assertion has to read back what
#   GTK kept rather than the code it returned.
#
#   A settings.ini that names a theme nobody installs falls back to the
#   built-in Adwaita in silence. The chain from the setting to the package is
#   therefore read end to end: the file names a theme, the bundle page names
#   the package that ships it, and a manifest declares that package.
#
# The tests that need GTK skip on a machine without the GTK 3 typelib, which is
# the continuous integration runner. Everything they prove about the shipped
# files is proved again by reading the files, so a skipped run still fails on a
# bundle that is wrong.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	GTK_DIR="$ROOT_DIR/config/gtk-3.0"
	SETTINGS_FILE="$GTK_DIR/settings.ini"
	STYLE_FILE="$GTK_DIR/gtk.css"
	SHADE_FILE="$ROOT_DIR/config/hyprshade/config.toml"
	YAY_FILE="$ROOT_DIR/config/yay/config.json"
	TEMPLATE_FILE="$ROOT_DIR/templates/gtk/colors.css"
	PAGE="$ROOT_DIR/docs/bundles/supporting.md"
	BASE_MANIFEST="$ROOT_DIR/install/packages/base.txt"
	AUR_MANIFEST="$ROOT_DIR/install/packages/aur.txt"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

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

	use_fixed_machine_facts
	use_own_knobs

	GENERATED="$XDG_STATE_HOME/xghost/generated"
	BRIDGE_NAME=xghost-generated
}

link_prescribed() {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config link
}

# Skip a test that needs the GTK 3 typelib on a machine without it, which is
# the continuous integration runner.
require_gtk() {
	python3 - <<-'PY' 2>/dev/null || skip "this machine has no GTK 3 typelib for python"
		import gi
		gi.require_version("Gtk", "3.0")
		from gi.repository import Gtk

		Gtk.CssProvider()
	PY
}

# Parse one style sheet with GTK and print every colour definition it kept.
#
# This is the only way GTK is run in this suite. A provider parses a file and
# returns; it opens no display and draws nothing.
#
# The output is the sheet as GTK holds it, so a definition GTK dropped is
# absent from it. That is the point: a definition whose value names a colour
# nothing defines is dropped without an error, so what GTK kept is the only
# reliable report.
gtk_colours() {
	CSS_PATH=$1 python3 - <<-'PY'
		import os
		import gi

		gi.require_version("Gtk", "3.0")
		from gi.repository import Gtk

		provider = Gtk.CssProvider()
		provider.load_from_path(os.environ["CSS_PATH"])
		for line in provider.to_string().splitlines():
		    if line.startswith("@define-color "):
		        print(line[len("@define-color ") :].rstrip(";"))
	PY
}

# Print the value one theme declares for one palette name.
palette_value() {
	local theme=$1 name=$2
	sed -n "s/^$name=//p" "$ROOT_DIR/themes/$theme/palette.conf"
}

# Print 'rgb(r,g,b)' of one '#rrggbb' value, which is the form GTK prints a
# parsed colour in.
gtk_rgb_of() {
	local hex=${1#\#}
	printf 'rgb(%d,%d,%d)' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Print the value settings.ini gives one key.
setting_value() {
	sed -n "s/^$1=//p" "$SETTINGS_FILE"
}

# Print every package name a manifest declares, one per line.
manifest_packages() {
	sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$1"
}

# Print 'THEME PACKAGE' for one setting, read out of the table of the bundle
# page. The table has four columns: the setting, the value the dotfiles gave
# it, the value this project gives it, and the package that ships that value.
page_theme_row() {
	sed -n "s/^| \`$1\` *| \`[^\`]*\` *| \`\([^\`]*\)\` *| \`\([^\`]*\)\` *|\$/\1 \2/p" "$PAGE"
}

# Print every file of the checkout, one per line, with the paths git and this
# agent keep out of the way.
project_files() {
	find "$ROOT_DIR" -name .git -prune -o -name .claude -prune -o -type f -print |
		sed "s#^$ROOT_DIR/##" | LC_ALL=C sort
}

# --- the prescribed configuration --------------------------------------------

@test "the three configurations of this bundle are prescribed configuration" {
	local file
	for file in "$SETTINGS_FILE" "$STYLE_FILE" "$SHADE_FILE" "$YAY_FILE"; do
		[ -f "$file" ]
		[ ! -L "$file" ]
	done

	# config/gtk-3.0 holds these two files and nothing else. A third file there
	# would be prescribed configuration this page does not document.
	run bash -c "find '$GTK_DIR' -type f | LC_ALL=C sort | paste -sd, -"
	[ "$output" = "$STYLE_FILE,$SETTINGS_FILE" ]
}

@test "'config link' places all three directories as symbolic links" {
	run -0 link_prescribed

	local name
	for name in gtk-3.0 hyprshade yay; do
		[ -L "$XDG_CONFIG_HOME/$name" ]
		[ "$XDG_CONFIG_HOME/$name" -ef "$ROOT_DIR/config/$name" ]
	done

	# The bridge is what the style sheet reaches the generated palette through.
	[ -L "$XDG_CONFIG_HOME/$BRIDGE_NAME" ]
}

@test "'config unlink' removes all three links again" {
	link_prescribed >/dev/null
	run -0 "$XGHOST" config unlink

	local name
	for name in gtk-3.0 hyprshade yay; do
		[ ! -e "$XDG_CONFIG_HOME/$name" ]
		[ ! -L "$XDG_CONFIG_HOME/$name" ]
	done
}

# --- the GTK settings file ----------------------------------------------------

# The criterion this bundle exists for. A settings file that names a theme
# nobody installs falls back to the built-in Adwaita in silence, so the chain
# from the setting to the package is read end to end here.
#
# The three settings are read out of the file rather than listed, so a fourth
# theme setting added later is covered on the day it is added.
@test "every theme the settings file names is a theme a manifest installs" {
	local declared
	declared=$(
		manifest_packages "$BASE_MANIFEST"
		manifest_packages "$AUR_MANIFEST"
	)

	local key value row want package count=0
	while IFS= read -r key; do
		value=$(setting_value "$key")
		[ -n "$value" ]

		row=$(page_theme_row "$key")
		[ -n "$row" ] || {
			printf 'settings.ini names %s and %s carries no row for it\n' \
				"$key" "${PAGE##*/}" >&2
			return 1
		}
		want=${row%% *}
		package=${row##* }

		[ "$want" = "$value" ] || {
			printf '%s says %s is %s and settings.ini says %s\n' \
				"${PAGE##*/}" "$key" "$want" "$value" >&2
			return 1
		}
		[[ $'\n'$declared$'\n' == *$'\n'"$package"$'\n'* ]] || {
			printf '%s=%s comes from %s and no manifest declares it\n' \
				"$key" "$value" "$package" >&2
			return 1
		}
		count=$((count + 1))
	done < <(grep -oE '^gtk-(theme|icon-theme|cursor-theme)-name' "$SETTINGS_FILE")

	# A file whose keys stopped matching would pass this test without a theme
	# ever being read.
	[ "$count" -eq 3 ]
}

# The other half of the same criterion. The test above proves that the package
# is declared; this one proves that the package ships the theme the setting
# asks for. It is the half no reading of this repository can answer, so it is
# read out of the package database of Arch.
#
# 'pacman -Fl' lists the files of a package this machine need not have
# installed. It needs the file database, which 'pacman -Fy' fills, so a machine
# that has never run that is skipped rather than failed.
@test "every package the bundle page names ships the theme the settings file asks for" {
	command -v pacman >/dev/null || skip "this machine has no pacman"
	pacman -Fl adw-gtk-theme >/dev/null 2>&1 ||
		skip "the pacman file database is not filled; run 'pacman -Fy'"

	local key value package directory count=0
	while read -r key directory; do
		value=$(setting_value "$key")
		package=$(page_theme_row "$key")
		package=${package##* }

		run -0 bash -c "pacman -Fl '$package' | grep -qxF '$package usr/share/$directory/$value/'"
		[ "$status" -eq 0 ] || {
			printf '%s does not ship usr/share/%s/%s, which settings.ini asks for\n' \
				"$package" "$directory" "$value" >&2
			return 1
		}
		count=$((count + 1))
	done <<-'KEYS'
		gtk-theme-name themes
		gtk-icon-theme-name icons
		gtk-cursor-theme-name icons
	KEYS
	[ "$count" -eq 3 ]
}

# The settings file cannot reach the generated output at all: GTK reads it with
# g_key_file_load_from_file, which has no include of any kind. A path in it
# would therefore be a path nothing follows.
@test "the settings file names no path and no generated file" {
	run grep -nE '^[^#]*(/|~|\$)' "$SETTINGS_FILE"
	[ "$status" -ne 0 ]
}

@test "the cursor size of GTK is the cursor size of the compositor" {
	local gtk_size hypr_size
	gtk_size=$(setting_value gtk-cursor-theme-size)
	hypr_size=$(sed -n 's/^env = XCURSOR_SIZE,//p' "$ROOT_DIR/config/hypr/conf/cursor.conf")
	[ -n "$gtk_size" ]
	[ -n "$hypr_size" ]
	[ "$gtk_size" = "$hypr_size" ]
}

# --- the GTK style sheet ------------------------------------------------------

@test "the style sheet imports the generated palette through the bridge" {
	run -0 grep -Fx "@import url(\"../$BRIDGE_NAME/gtk/colors.css\");" "$STYLE_FILE"

	# GTK expands neither a variable nor '~' in an '@import', so a path that
	# named either would reach nothing, and an import that reaches nothing
	# discards this whole file.
	run grep -nE '^[[:space:]]*@import.*(~|\$)' "$STYLE_FILE"
	[ "$status" -ne 0 ]

	# The import comes before the first definition. A colour has to be defined
	# before another one names it.
	local first_import first_define
	first_import=$(grep -n '^@import' "$STYLE_FILE" | head -1 | cut -d: -f1)
	first_define=$(grep -n '^@define-color' "$STYLE_FILE" | head -1 | cut -d: -f1)
	[ -n "$first_import" ]
	[ -n "$first_define" ]
	[ "$first_import" -lt "$first_define" ]
}

# The style sheet is a map and holds no colour of its own, so every value in it
# is a reference. A literal here would be a colour that follows no theme and
# that a theme switch could never change.
@test "every value the style sheet defines is a reference and not a colour" {
	local name value count=0
	while read -r name value; do
		[[ $value == @* ]] || {
			printf 'the style sheet defines %s as %s, which is a colour of its own\n' \
				"$name" "$value" >&2
			return 1
		}
		count=$((count + 1))
	done < <(sed -n 's/^@define-color \([a-z_]*\) \(.*\);$/\1 \2/p' "$STYLE_FILE")
	[ "$count" -gt 0 ]
}

# A GTK colour that no file defines is dropped in silence, so a name the sheet
# draws with and the generated palette does not define is a widget colour that
# quietly stays as the stock theme drew it.
#
# The names are read out of the two files rather than listed here, so a name
# added to either one later is covered on the day it is added.
@test "every colour the style sheet names is defined by the generated palette" {
	"$XGHOST" theme set tokyonight >/dev/null
	local generated="$GENERATED/gtk/colors.css"
	[ -f "$generated" ]

	local name count=0
	while IFS= read -r name; do
		run grep -Fq "@define-color $name " "$generated"
		[ "$status" -eq 0 ] || {
			printf 'the style sheet names @%s and the generated palette does not define it\n' \
				"$name" >&2
			return 1
		}
		count=$((count + 1))
	done < <(sed -n 's/^@define-color [a-z_]* @\([a-z_]*\);$/\1/p' "$STYLE_FILE" |
		LC_ALL=C sort -u)
	[ "$count" -gt 0 ]
}

# The confirmation ADR 0002 asks every bundle after Ghostty for by name. Both
# XDG paths are moved, so the two ends of the include have to be right at once:
# the renderer follows XDG_STATE_HOME and GTK resolves the import against
# XDG_CONFIG_HOME. A home directory built out of defaults can never show that
# divergence.
@test "the import reaches the file the renderer writes when both XDG paths move" {
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run -0 link_prescribed
	"$XGHOST" theme set tokyonight >/dev/null

	local opened="$XDG_CONFIG_HOME/gtk-3.0"
	local resolved="${opened%/*}/$BRIDGE_NAME/gtk/colors.css"
	[ -f "$resolved" ]
	[ "$resolved" -ef "$XDG_STATE_HOME/xghost/generated/gtk/colors.css" ]
	run -0 grep -Fx "@define-color bg $(palette_value tokyonight BG);" "$resolved"
}

# GTK is what reads this file, so GTK is what is asked whether the import
# worked. The palette names appear in the provider only when the import was
# resolved and opened.
@test "GTK resolves the import and holds the palette of the active theme" {
	require_gtk
	run -0 link_prescribed
	"$XGHOST" theme set tokyonight >/dev/null

	run -0 gtk_colours "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
	[[ $'\n'$output$'\n' == *$'\n'"bg $(gtk_rgb_of "$(palette_value tokyonight BG)")"$'\n'* ]]
	[[ $'\n'$output$'\n' == *$'\n'"accent $(gtk_rgb_of "$(palette_value tokyonight ACCENT)")"$'\n'* ]]
}

# The path as opened and the real path are two different directories, because
# 'xghost config link' places a symbolic link. This is the measurement that
# says which of the two GTK reads, and it is the rule the whole construction
# rests on.
#
# The decoy holds a value GTK cannot parse. GTK reporting nothing is therefore
# the proof that it never opened the decoy, on top of the value it holds.
@test "GTK reads the bridge and not a file at the real path" {
	require_gtk
	"$XGHOST" theme set tokyonight >/dev/null

	# The two links are made here rather than by 'xghost config link'. The path
	# this test plants a decoy at is a top level entry of the prescribed
	# configuration directory, so the linker would try to link it as an entry
	# of its own and refuse the bridge. The shape below is the shape the linker
	# makes, and the decoy is inside a copy, never in the checkout.
	local source_copy="$BATS_TEST_TMPDIR/config-source"
	cp -R "$ROOT_DIR/config" "$source_copy"
	mkdir -p "$source_copy/$BRIDGE_NAME/gtk"
	printf '@define-color bg #DECOY0;\n' >"$source_copy/$BRIDGE_NAME/gtk/colors.css"

	ln -s "$source_copy/gtk-3.0" "$XDG_CONFIG_HOME/gtk-3.0"
	ln -s "$GENERATED" "$XDG_CONFIG_HOME/$BRIDGE_NAME"

	# Both bases now hold the file, which is the case this test exists for.
	[ -f "$XDG_CONFIG_HOME/$BRIDGE_NAME/gtk/colors.css" ]
	[ -f "$source_copy/$BRIDGE_NAME/gtk/colors.css" ]

	run -0 gtk_colours "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
	[[ $'\n'$output$'\n' == *$'\n'"bg $(gtk_rgb_of "$(palette_value tokyonight BG)")"$'\n'* ]]

	# The decoy holds a value GTK cannot parse, so GTK saying nothing about it
	# is the proof that it was never opened.
	[[ $output != *DECOY* ]]
}

# The map from the palette onto the names GTK draws with, read back out of GTK
# rather than out of the file that wrote it. The chain is two steps, because
# GTK keeps a reference as a reference and resolves it when it draws:
#
#   theme_selected_bg_color -> @accent -> rgb(122,162,247)
#
# The second step is what pins the map. A test that read the first step alone
# would pass with every reference pointing at the same colour.
@test "the widget colours GTK holds are the colours of the active theme" {
	require_gtk
	run -0 link_prescribed
	"$XGHOST" theme set tokyonight >/dev/null

	local dump
	dump=$(gtk_colours "$XDG_CONFIG_HOME/gtk-3.0/gtk.css")

	local name reference expected count=0
	while read -r name expected; do
		reference=$(printf '%s\n' "$dump" | sed -n "s/^$name //p")
		[ -n "$reference" ] || {
			printf 'GTK dropped %s, so no widget draws with it\n' "$name" >&2
			return 1
		}
		[[ $reference == @* ]] || {
			printf '%s is %s in GTK, which is a colour rather than a reference\n' \
				"$name" "$reference" >&2
			return 1
		}
		run -0 bash -c "printf '%s\n' \"\$1\" | sed -n \"s/^\${2#@} //p\"" _ "$dump" "$reference"
		[ "$output" = "$(gtk_rgb_of "$(palette_value tokyonight "$expected")")" ] || {
			printf '%s reaches %s, which is %s and not the %s of the theme\n' \
				"$name" "$reference" "$output" "$expected" >&2
			return 1
		}
		count=$((count + 1))
	done <<-'PAIRS'
		theme_bg_color BG
		theme_base_color SURFACE
		theme_fg_color TEXT
		theme_text_color TEXT
		theme_selected_bg_color ACCENT
		theme_selected_fg_color BG
		insensitive_fg_color TEXT_MUTED
		borders SURFACE
		warning_color WARN
		error_color ERROR
		success_color SUCCESS
	PAIRS
	[ "$count" -eq 11 ]
}

# Every focused name has an unfocused twin, and the two hold the same value.
# Leaving a twin out leaves every unfocused window in the colours of the stock
# theme, which is a split nobody chose and which nothing else here would catch.
@test "a window that does not hold the focus draws in the same colours" {
	local name twin value twin_value count=0
	while IFS= read -r name; do
		twin=theme_unfocused_${name#theme_}
		value=$(sed -n "s/^@define-color $name //p" "$STYLE_FILE")
		twin_value=$(sed -n "s/^@define-color $twin //p" "$STYLE_FILE")
		[ -n "$twin_value" ] || {
			printf 'the style sheet defines %s and no %s\n' "$name" "$twin" >&2
			return 1
		}
		[ "$value" = "$twin_value" ] || {
			printf '%s is %s and %s is %s\n' "$name" "$value" "$twin" "$twin_value" >&2
			return 1
		}
		count=$((count + 1))
	done < <(sed -n 's/^@define-color \(theme_[a-z_]*\) .*/\1/p' "$STYLE_FILE" |
		grep -v '^theme_unfocused_')
	[ "$count" -gt 0 ]
}

# --- the theme switch ---------------------------------------------------------

@test "a theme switch rewrites the palette every GTK window draws with" {
	link_prescribed >/dev/null

	local theme count=0
	while IFS= read -r theme; do
		[ -n "$theme" ] || continue
		"$XGHOST" theme set "$theme" >/dev/null
		run -0 grep -Fx "@define-color accent $(palette_value "$theme" ACCENT);" \
			"$GENERATED/gtk/colors.css"
		count=$((count + 1))
	done < <("$XGHOST" theme list)

	# Two themes, so the file is proved to change rather than to exist.
	[ "$count" -gt 1 ]
}

@test "every palette value the style sheet reaches is a six-digit hex" {
	local names
	names=$(grep -oE '@[A-Z][A-Z0-9_]*@' "$TEMPLATE_FILE" | tr -d '@' | LC_ALL=C sort -u)
	[ -n "$names" ]

	local theme name value count=0
	while IFS= read -r theme; do
		[ -n "$theme" ] || continue
		while IFS= read -r name; do
			value=$(palette_value "$theme" "${name%_RGB}")
			[ -n "$value" ] || {
				printf 'the theme %s declares no %s\n' "$theme" "$name" >&2
				return 1
			}
			[[ $value =~ ^#[0-9a-fA-F]{6}$ ]] || {
				printf 'the theme %s writes %s=%s; GTK cannot parse it and the whole sheet is dropped\n' \
					"$theme" "$name" "$value" >&2
				return 1
			}
			count=$((count + 1))
		done <<<"$names"
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

# --- hyprshade ----------------------------------------------------------------

@test "the hyprshade schedule is the file hyprshade reads" {
	run -0 link_prescribed
	[ -f "$XDG_CONFIG_HOME/hyprshade/config.toml" ]

	# hyprshade reads $XDG_CONFIG_HOME/hypr/hyprshade.toml first, and that
	# directory is one this project links. A file there would take priority
	# over the prescribed schedule in silence.
	[ ! -e "$XDG_CONFIG_HOME/hypr/hyprshade.toml" ]
	run bash -c "find '$ROOT_DIR/config/hypr' -name 'hyprshade*' -print -quit"
	[ -z "$output" ]
}

# The rules are the ones hyprshade's own validator applies: every shade needs a
# name, and a shade that is not the default needs a start time.
@test "the hyprshade schedule satisfies the rules hyprshade validates" {
	run -0 python3 - "$SHADE_FILE" <<-'PY'
		import sys
		import tomllib

		config = tomllib.load(open(sys.argv[1], "rb"))
		shades = config["shades"]
		assert isinstance(shades, list), "`shades` must be a list"
		assert shades, "the schedule declares no shade"
		for shade in shades:
		    assert shade.get("name"), "`name` is required for each item in `shades`"
		    assert shade.get("start_time") or shade.get("default") is True, (
		        "a non-default shade must define `start_time`"
		    )
		print(" ".join(shade["name"] for shade in shades))
	PY
	[ "$output" = blue-light-filter ]
}

# The schedule names a shader and never a path, so there is no name in it that
# only this checkout could satisfy.
@test "the shader the schedule names is one hyprshade itself ships" {
	run grep -nE '^[^#]*(/|~|\.glsl)' "$SHADE_FILE"
	[ "$status" -ne 0 ]

	command -v hyprshade >/dev/null || skip "this machine has no hyprshade"
	local name
	name=$(sed -n 's/^name = "\(.*\)"$/\1/p' "$SHADE_FILE")
	[ -f "/usr/share/hyprshade/shaders/$name.glsl" ]
}

# hyprshade is the one package of this desktop that no official repository
# carries, and a package in aur.txt is not installed on a machine with no
# helper. Nothing the desktop needs to draw itself may be in that file.
@test "hyprshade is declared by the AUR manifest and by no other" {
	run -0 manifest_packages "$AUR_MANIFEST"
	[ "$output" = hyprshade ]

	run -0 manifest_packages "$BASE_MANIFEST"
	[[ $'\n'$output$'\n' != *$'\n'hyprshade$'\n'* ]]

	# Read from pacman rather than trusted: a package that reaches an official
	# repository later belongs in base.txt, where a helper is not needed.
	command -v pacman >/dev/null || skip "this machine has no pacman"
	run pacman -Si hyprshade
	[ "$status" -ne 0 ]
}

# --- yay ----------------------------------------------------------------------

@test "the yay configuration is the one setting the bundle page names" {
	run -0 python3 - "$YAY_FILE" <<-'PY'
		import json
		import sys

		print(" ".join(sorted(json.load(open(sys.argv[1])))))
	PY
	[ "$output" = cleanAfter ]

	run -0 grep -Fq '`cleanAfter`' "$PAGE"
}

# xghost installs no AUR helper by itself, so prescribing the configuration of
# one must not turn into declaring it.
@test "no manifest declares an AUR helper" {
	local declared name
	declared=$(
		manifest_packages "$BASE_MANIFEST"
		manifest_packages "$AUR_MANIFEST"
	)
	for name in yay paru; do
		[[ $'\n'$declared$'\n' != *$'\n'"$name"$'\n'* ]] || {
			printf '%s is declared, and this project installs no AUR helper\n' "$name" >&2
			return 1
		}
	done
}

# --- pywal --------------------------------------------------------------------

# The criterion the issue states: no dangling reference to pywal remains.
#
# A dangling reference is one a reader or a program can follow to nothing: an
# include path, a package name, a command, a variable. A record of a removal is
# not one, and three pages carry such a record on purpose. This test is what
# turns that judgement into a rule: the name may appear in those three pages,
# in this file, and in the control that proves this file can fail, and nowhere
# else at all.
#
# Each allowed file has to carry the name as well, so an allowance cannot rot
# into a permission nobody needs.
@test "the name of pywal appears only where its removal is recorded" {
	local allowed=(
		docs/bundles/shell.md
		docs/bundles/waybar.md
		docs/bundles/supporting.md
		tests/supporting.bats
		tests/negative-control
	)

	local file found
	for file in "${allowed[@]}"; do
		run -0 grep -qi pywal "$ROOT_DIR/$file"
	done

	while IFS= read -r file; do
		grep -qi pywal "$ROOT_DIR/$file" || continue
		found=no
		for allowed_file in "${allowed[@]}"; do
			[ "$file" = "$allowed_file" ] && found=yes
		done
		[ "$found" = yes ] || {
			printf '%s names pywal, and this project does not use it\n' "$file" >&2
			return 1
		}
	done < <(project_files)
}

# The other half. The name being absent proves nothing on its own: the cache
# path, the sequence file and the vendored script each reach pywal without
# spelling it.
@test "nothing this desktop installs or runs reaches the colour cache of pywal" {
	# Everything the desktop places, renders or executes. The documentation and
	# the suites are left out on purpose: a page that records the removal and a
	# test that asserts the absence both have to be able to write the path
	# down.
	local roots=(bin commands completions config install lib schema templates themes)
	roots+=(boot.sh install.sh)

	local file count=0
	while IFS= read -r file; do
		run grep -nE 'cache/wal|wal/colors|wal/sequences|python-pywal|wal -[a-z]' \
			"$file"
		[ "$status" -ne 0 ] || {
			printf '%s reaches the colour cache of pywal\n' "${file#"$ROOT_DIR/"}" >&2
			return 1
		}
		count=$((count + 1))
	done < <(cd "$ROOT_DIR" && find "${roots[@]}" -type f -printf "$ROOT_DIR/%p\n")

	# A root that moved would otherwise leave this test reading nothing.
	[ "$count" -gt 50 ]
}

@test "this project ships no pywal template, colourscheme or vendored script" {
	run bash -c "find '$ROOT_DIR' -name .git -prune -o \\( -name wal -o -name 'wal.*' -o -name 'colors-wal*' \\) -print"
	[ -z "$output" ]

	[ ! -e "$ROOT_DIR/templates/wal" ]
	[ ! -e "$ROOT_DIR/config/wal" ]
}

# The shell was the last reader of the cache, and the shell bundle dropped the
# block. This is the criterion read against the file rather than against the
# page that records it.
@test "the prescribed zshrc reads no cache of a colour generator" {
	run grep -nE 'wal|sequences' "$ROOT_DIR/config/zsh/.zshrc"
	[ "$status" -ne 0 ]
}

# --- ImageMagick --------------------------------------------------------------

# Nothing needs it. lib/background.py draws the background with the standard
# library of Python alone, and the only mention left is the comment in the
# manifest that records why the alternative was rejected. That comment is a
# record and not a declaration, so this test reads the packages rather than the
# text.
@test "no manifest declares imagemagick" {
	local declared name
	declared=$(
		manifest_packages "$BASE_MANIFEST"
		manifest_packages "$AUR_MANIFEST"
	)
	for name in imagemagick magick graphicsmagick; do
		[[ $'\n'$declared$'\n' != *$'\n'"$name"$'\n'* ]] || {
			printf '%s is declared and nothing on this desktop needs it\n' "$name" >&2
			return 1
		}
	done

	# The record of the decision stays. A manifest that stopped explaining the
	# rejection would leave the next reader to weigh it again.
	run -0 grep -qi imagemagick "$BASE_MANIFEST"
	run -0 grep -qi imagemagick "$ROOT_DIR/docs/backgrounds.md"
}
