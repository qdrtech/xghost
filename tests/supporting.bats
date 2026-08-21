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
#   - GTK is read through a style provider, which parses a style sheet and
#     returns. It needs no display and it draws nothing.
#   - hyprshade is never run. Its schedule is read as TOML and checked against
#     the rules its own validator applies, and its shader directory is read.
#     'hyprshade on', 'off' and 'auto' each apply a shader to the running
#     compositor and appear nowhere in this file.
#   - yay is never run. 'pacman' is read with '-Si', '-Fl' and '-Ql', which
#     query the databases and change nothing.
#
# Three rules this suite is built around, and docs/bundles/supporting.md
# records the measurement behind each:
#
#   A GTK colour that no file defines is dropped when a widget draws with it.
#   The provider keeps the definition and reports nothing, so an assertion has
#   to read back what GTK kept and follow it to a value.
#
#   The names a theme exports are not the names it draws with. Redefining an
#   exported name changes what an application reads and changes nothing the
#   theme puts on the screen, so one test reads the rules of the installed
#   theme rather than the sheet of this project.
#
#   A settings.ini that names a theme nobody installs falls back to the
#   built-in Adwaita in silence. The chain from the setting to the package is
#   therefore read end to end: the file names a theme, the bundle page names
#   the package that ships it, and a manifest declares that package.
#
# Some tests need GTK, pacman or hyprshade, and skip on a machine without
# them. A skipped test proves nothing, and two of them have no file-reading
# equivalent at all, so the set of tests that can skip is itself asserted
# against the list on the bundle page. A run that skips more than that list is
# a run whose cover shrank without anybody saying so.
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
	SUITE_FILE="$BATS_TEST_DIRNAME/supporting.bats"
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

# Skip a test that needs GTK 3 on a machine without it.
#
# Both routes into GTK are checked here, because this suite uses both: the
# typelib for the binding and the shared library for the call GTK itself
# makes. A machine that carries one and not the other would otherwise fail a
# test for a reason that has nothing to do with this project.
require_gtk() {
	python3 - <<-'PY' 2>/dev/null || skip "this machine has no GTK 3 for python"
		import ctypes

		import gi

		gi.require_version("Gtk", "3.0")
		from gi.repository import Gtk

		Gtk.CssProvider()
		ctypes.CDLL("libgtk-3.so.0")
	PY
}

# Parse one style sheet with GTK and print every colour definition it kept.
#
# The binding is what runs GTK here, and the binding passes a real GError**,
# so a failed import raises and this function ends non-zero with nothing kept.
# That is not what GTK does with the sheet of the user; gtk_colours_null_error
# below is. Both are here because the difference between them is the state of
# a machine that has not rendered a palette yet.
#
# The output is the sheet as GTK holds it, so a definition GTK dropped is
# absent from it.
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

# The same, on the route GTK takes for the style sheet of the user.
#
# GTK loads that sheet with a NULL error pointer, and a NULL error pointer
# changes the result: the failure is written to standard error, the call
# reports success, and everything the parser reached is kept. The binding
# cannot pass NULL, so this goes through the shared library with ctypes.
#
# The first line printed is the value the call returned. The rest are the
# definitions GTK kept.
gtk_colours_null_error() {
	CSS_PATH=$1 python3 - <<-'PY'
		import ctypes
		import os

		gtk = ctypes.CDLL("libgtk-3.so.0")
		gtk.gtk_css_provider_new.restype = ctypes.c_void_p
		gtk.gtk_css_provider_load_from_path.argtypes = [
		    ctypes.c_void_p,
		    ctypes.c_char_p,
		    ctypes.c_void_p,
		]
		gtk.gtk_css_provider_load_from_path.restype = ctypes.c_int
		gtk.gtk_css_provider_to_string.argtypes = [ctypes.c_void_p]
		gtk.gtk_css_provider_to_string.restype = ctypes.c_char_p

		provider = gtk.gtk_css_provider_new()
		returned = gtk.gtk_css_provider_load_from_path(
		    provider, os.environ["CSS_PATH"].encode(), None
		)
		print("return", returned)
		for line in gtk.gtk_css_provider_to_string(provider).decode().splitlines():
		    if line.startswith("@define-color "):
		        print(line[len("@define-color ") :].rstrip(";"))
	PY
}

# Print every colour name the rules of one style sheet read.
#
# The definitions are dropped first. A theme defines and exports far more
# names than it draws with, and a name it only exports is a name that
# redefining changes nothing about. What is left is the rules, and a name in
# them is a name the theme puts on the screen.
gtk_rule_references() {
	CSS_PATH=$1 python3 - <<-'PY'
		import os
		import re

		import gi

		gi.require_version("Gtk", "3.0")
		from gi.repository import Gtk

		provider = Gtk.CssProvider()
		provider.load_from_path(os.environ["CSS_PATH"])
		rules = "\n".join(
		    line
		    for line in provider.to_string().splitlines()
		    if not line.startswith("@define-color ")
		)
		# '@keyframes' and the rest are at-rules and not colours. A theme that
		# holds those alone reads no named colour, which is the case this is
		# here to report.
		at_rules = {"charset", "import", "keyframes", "media", "supports"}
		found = set(re.findall(r"@([a-z_][a-z0-9_-]*)", rules)) - at_rules
		for name in sorted(found):
		    print(name)
	PY
}

# Print the path of the GTK 3 style sheet of one theme, searched the way GTK
# searches for it. Nothing is printed when no directory holds it.
theme_sheet_path() {
	local name=$1 dir
	for dir in "$HOME/.themes" "${XDG_DATA_HOME:-$HOME/.local/share}/themes" \
		/usr/local/share/themes /usr/share/themes; do
		if [ -f "$dir/$name/gtk-3.0/gtk.css" ]; then
			printf '%s\n' "$dir/$name/gtk-3.0/gtk.css"
			return 0
		fi
	done
	return 1
}

# Print 'NAME VALUE' for every colour the style sheet defines. The value is
# everything up to the semicolon, so a CSS function reaches the caller whole.
style_definitions() {
	sed -n 's/^@define-color \([a-z_]*\) \(.*\);$/\1 \2/p' "$STYLE_FILE"
}

# Print the number of colours the style sheet defines.
style_definition_count() {
	grep -c '^@define-color' "$STYLE_FILE"
}

# Print the contrast ratio of two colours of the style sheet, as an integer of
# one hundredth, so a shell can compare it. 1.00 is two colours that are the
# same; 1.0 is the smallest ratio there is.
#
#   contrast_of THEME NAME AGAINST
#
# NAME and AGAINST are names the style sheet defines. A translucent colour is
# composited over AGAINST first, which is what a border drawn on a surface
# does.
contrast_of() {
	CONTRAST_THEME=$ROOT_DIR/themes/$1/palette.conf \
		CONTRAST_STYLE=$STYLE_FILE \
		CONTRAST_NAME=$2 \
		CONTRAST_AGAINST=$3 \
		python3 - <<-'PY'
			import os
			import re
			import sys

			palette = {}
			for line in open(os.environ["CONTRAST_THEME"], encoding="utf-8"):
			    if "=" in line and not line.startswith("#"):
			        key, value = line.strip().split("=", 1)
			        palette[key.lower()] = value

			definitions = {}
			for line in open(os.environ["CONTRAST_STYLE"], encoding="utf-8"):
			    found = re.match(r"^@define-color ([a-z_]+) (.*);$", line)
			    if found:
			        definitions[found.group(1)] = found.group(2)


			def rgba(text):
			    text = text.strip()
			    if text.startswith("#"):
			        return [int(text[i : i + 2], 16) for i in (1, 3, 5)] + [1.0]
			    if text.startswith("@"):
			        name = text[1:]
			        if name in palette:
			            return rgba(palette[name])
			        if name in definitions:
			            return rgba(definitions[name])
			        sys.exit("nothing defines @%s" % name)
			    found = re.match(r"^alpha\((.*),\s*([0-9.]+)\)$", text)
			    if found:
			        colour = rgba(found.group(1))
			        return colour[:3] + [colour[3] * float(found.group(2))]
			    found = re.match(r"^mix\((.*),\s*(@[a-z_]+|#[0-9a-fA-F]{6}),\s*([0-9.]+)\)$", text)
			    if found:
			        first, second = rgba(found.group(1)), rgba(found.group(2))
			        share = float(found.group(3))
			        return [
			            first[i] * (1 - share) + second[i] * share for i in range(3)
			        ] + [1.0]
			    sys.exit("this is not a colour of the palette: %s" % text)


			def luminance(colour):
			    channels = []
			    for value in colour[:3]:
			        value /= 255
			        channels.append(
			            value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4
			        )
			    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


			against = rgba("@" + os.environ["CONTRAST_AGAINST"])
			colour = rgba("@" + os.environ["CONTRAST_NAME"])
			share = colour[3]
			colour = [colour[i] * share + against[i] * (1 - share) for i in range(3)]

			first, second = luminance(colour), luminance(against)
			high, low = max(first, second), min(first, second)
			print(round((high + 0.05) / (low + 0.05) * 100))
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

# Print every key of settings.ini that names a theme.
#
# The pattern takes any key of the form 'gtk-<something>-name' whose something
# ends in 'theme', so a fourth theme setting added later is read on the day it
# is added rather than counted out.
setting_theme_keys() {
	grep -oE '^gtk-([a-z-]+-)?theme-name' "$SETTINGS_FILE"
}

# Print every package name a manifest declares, one per line.
manifest_packages() {
	sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$1"
}

# Print 'THEME PACKAGE DIRECTORY' for one setting, read out of the table of the
# bundle page. The table has five columns: the setting, the value the dotfiles
# gave it, the value this project gives it, the package that ships that value,
# and the directory under /usr/share the package puts it in.
page_theme_row() {
	sed -n "s#^| \`$1\` *| \`[^\`]*\` *| \`\([^\`]*\)\` *| \`\([^\`]*\)\` *| \`\([^\`]*\)\` *|\$#\1 \2 \3#p" "$PAGE"
}

# Print every table row under one heading of the bundle page.
#
# The heading anchors the read. Another table elsewhere on the page has the
# same shape, and a reader of rows alone would take those rows too.
page_rows_under() {
	awk -v heading="$1" '
		$0 == heading { inside = 1; next }
		inside && /^#/ { inside = 0 }
		inside && /^\| `/ { print }
	' "$PAGE"
}

# Print 'NAME VALUE' for every pair of the map table of the bundle page.
#
# One row of that table holds several names and one value, so a row of eleven
# names prints eleven lines. The value is the value the style sheet is required
# to give each of them, spelled exactly as the style sheet spells it.
page_map() {
	local row names value name
	while IFS= read -r row; do
		names=$(printf '%s\n' "$row" | cut -d'|' -f2 | grep -oE '`[a-z_]+`' | tr -d '`')
		value=$(printf '%s\n' "$row" | cut -d'|' -f3 | sed -e 's/^ *`//' -e 's/` *$//')
		for name in $names; do
			printf '%s %s\n' "$name" "$value"
		done
	done < <(page_rows_under '### How a palette colour becomes a widget colour')
}

# Print every file of the checkout, one per line, with the paths git and this
# agent keep out of the way.
project_files() {
	find "$ROOT_DIR" -name .git -prune -o -name .claude -prune -o -type f -print |
		sed "s#^$ROOT_DIR/##" | LC_ALL=C sort
}

# Print the name of every test of this suite that can end in a skip.
#
# A test counts when its body calls 'skip' with a message, or calls a helper
# that does. Comments are read past, so the reason written above a test is not
# mistaken for the test itself.
skipping_tests() {
	awk '
		/^@test "/ {
			name = $0
			sub(/^@test "/, "", name)
			sub(/" \{$/, "", name)
			found = 0
			next
		}
		name != "" && /^\}$/ {
			if (found) print name
			name = ""
			next
		}
		name != "" && $0 !~ /^[[:space:]]*#/ {
			if ($0 ~ /(^|[;|& \t])skip[ \t]+"/ || $0 ~ /require_gtk/) found = 1
		}
	' "$SUITE_FILE"
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
# The keys are read out of the file by their shape rather than listed, so a
# fourth theme setting added later is covered on the day it is added. The count
# is read out of the file as well: a fixed number here would fail on the fourth
# key instead of covering it.
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
		row=${row#* }
		package=${row%% *}

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
	done < <(setting_theme_keys)

	# Every theme key of the file was read, and the file names at least the
	# three this bundle ships. A file whose keys stopped matching would
	# otherwise pass this test without a theme ever being read.
	[ "$count" -eq "$(setting_theme_keys | wc -l)" ]
	[ "$count" -ge 3 ]
}

# The other half of the same criterion. The test above proves that the package
# is declared; this one proves that the package ships the theme the setting
# asks for. It is the half no reading of this repository can answer, so it is
# read out of the package database of Arch.
#
# The keys and the directory each package puts its theme in both come from the
# same two files as above, so a fourth theme setting is read here as well.
#
# 'pacman -Fl' lists the files of a package this machine need not have
# installed. It needs the file database, which 'pacman -Fy' fills, so a machine
# that has never run that is skipped rather than failed.
@test "every package the bundle page names ships the theme the settings file asks for" {
	command -v pacman >/dev/null || skip "this machine has no pacman"
	pacman -Fl adw-gtk-theme >/dev/null 2>&1 ||
		skip "the pacman file database is not filled; run 'pacman -Fy'"

	local key value row package directory count=0
	while IFS= read -r key; do
		value=$(setting_value "$key")
		row=$(page_theme_row "$key")
		row=${row#* }
		package=${row%% *}
		directory=${row##* }

		run bash -c "pacman -Fl '$package' | grep -qxF '$package usr/share/$directory/$value/'"
		[ "$status" -eq 0 ] || {
			printf '%s does not ship usr/share/%s/%s, which settings.ini asks for\n' \
				"$package" "$directory" "$value" >&2
			return 1
		}
		count=$((count + 1))
	done < <(setting_theme_keys)
	[ "$count" -eq "$(setting_theme_keys | wc -l)" ]
	[ "$count" -ge 3 ]
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
	# named either would reach nothing.
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
# reaches the palette. A literal here would be a colour that follows no theme
# and that a theme switch could never change.
#
# Two values are a CSS function over a palette name, because the palette holds
# no third surface and a border needs one. A function is allowed; a colour
# inside it is not.
@test "every value the style sheet defines reaches the palette and holds no colour" {
	local name value reference count=0
	while read -r name value; do
		[[ $value != *"#"* ]] || {
			printf 'the style sheet defines %s as %s, which is a colour of its own\n' \
				"$name" "$value" >&2
			return 1
		}
		[[ $value =~ ^(rgb|rgba|hsl|hsla)\( ]] && {
			printf 'the style sheet defines %s as %s, which is a colour of its own\n' \
				"$name" "$value" >&2
			return 1
		}
		reference=$(printf '%s\n' "$value" | grep -oE '@[a-z_]+' | head -1)
		[ -n "$reference" ] || {
			printf 'the style sheet defines %s as %s, which names no palette colour\n' \
				"$name" "$value" >&2
			return 1
		}
		count=$((count + 1))
	done < <(style_definitions)
	[ "$count" -eq "$(style_definition_count)" ]
}

# A GTK colour that no file defines is dropped when a widget draws with it, so
# a name the sheet draws with and the generated palette does not define is a
# widget colour that quietly stays as the stock theme drew it.
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
	done < <(style_definitions | grep -oE '@[a-z_]+' | tr -d '@' | LC_ALL=C sort -u)
	[ "$count" -gt 0 ]
}

# The other direction, which nothing read before. A palette colour the style
# sheet never names reaches no GTK window at all. That is allowed, because the
# template is older than this bundle and another consumer may take it, but it
# has to be a decision somebody wrote down rather than a name that quietly
# reaches nobody.
@test "every colour the generated palette defines is used or recorded as unused" {
	"$XGHOST" theme set tokyonight >/dev/null
	local generated="$GENERATED/gtk/colors.css"

	local used recorded
	used=$(style_definitions | grep -oE '@[a-z_]+' | tr -d '@' | LC_ALL=C sort -u)
	recorded=$(page_rows_under '#### The palette colours no GTK window reads' |
		sed -n 's/^| `\([a-z_]*\)`.*/\1/p' | LC_ALL=C sort -u)
	[ -n "$recorded" ]

	local name count=0
	while IFS= read -r name; do
		if [[ $'\n'$used$'\n' == *$'\n'"$name"$'\n'* ]]; then
			[[ $'\n'$recorded$'\n' != *$'\n'"$name"$'\n'* ]] || {
				printf '%s names @%s and %s records it as unused\n' \
					"${STYLE_FILE##*/}" "$name" "${PAGE##*/}" >&2
				return 1
			}
		else
			[[ $'\n'$recorded$'\n' == *$'\n'"$name"$'\n'* ]] || {
				printf 'the generated palette defines @%s, no style sheet names it, and %s does not record it\n' \
					"$name" "${PAGE##*/}" >&2
				return 1
			}
		fi
		count=$((count + 1))
	done < <(sed -n 's/^@define-color \([a-z_]*\) .*/\1/p' "$generated" | LC_ALL=C sort -u)
	[ "$count" -eq "$(grep -c '^@define-color' "$generated")" ]
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

# What the machine holds between 'xghost config link' and the first
# 'xghost theme set', measured on the route GTK itself takes.
#
# The two routes disagree, and the difference is the whole point. A binding
# that passes a real error pointer raises and keeps nothing, which reads like a
# style sheet that was discarded. GTK passes NULL, and then the import fails on
# standard error, the call reports success, and every definition is kept with
# nothing to reach. This test asserts both, because asserting the binding alone
# is how the wrong answer was written down the first time.
@test "a palette that is not there leaves every definition kept and reaching nothing" {
	require_gtk
	run -0 link_prescribed

	# No theme was rendered, so the bridge reaches no palette.
	[ ! -f "$XDG_CONFIG_HOME/$BRIDGE_NAME/gtk/colors.css" ]
	local sheet="$XDG_CONFIG_HOME/gtk-3.0/gtk.css"

	# The route the binding takes: an error is raised and nothing is kept.
	run gtk_colours "$sheet"
	[ "$status" -ne 0 ]

	# The route GTK takes.
	run --separate-stderr -0 gtk_colours_null_error "$sheet"
	[[ $stderr == *"Failed to import"* ]]

	local first=${output%%$'\n'*}
	[ "$first" = "return 1" ] || {
		printf 'GTK returned "%s" for a sheet whose import failed\n' "$first" >&2
		return 1
	}

	local kept=${output#*$'\n'}
	local name value defined count=0
	defined=$(printf '%s\n' "$kept" | cut -d' ' -f1)
	while read -r name value; do
		[[ $'\n'$defined$'\n' == *$'\n'"${value#@}"$'\n'* ]] && {
			printf '%s reaches %s, which is defined, so the palette was there after all\n' \
				"$name" "$value" >&2
			return 1
		}
		count=$((count + 1))
	done <<<"$kept"

	# Every definition of the sheet survived, and every one of them reaches a
	# colour nothing defines.
	[ "$count" -eq "$(style_definition_count)" ]
}

# The names a theme exports are not the names it draws with, and only the
# second kind changes a pixel. This test reads the rules of the theme
# settings.ini names and requires the style sheet to redefine what those rules
# read.
#
# It is the test the first version of this bundle did not have. That version
# redefined the legacy 'theme_*' names alone, every one of them was held by the
# provider, and no rule of any theme this project installs reads one, so every
# widget went on drawing in the colours of the stock theme.
@test "the theme the settings file names draws with names the style sheet redefines" {
	require_gtk
	local theme sheet
	theme=$(setting_value gtk-theme-name)
	sheet=$(theme_sheet_path "$theme") ||
		skip "the theme $theme is not installed on this machine"

	# The names are read with the standard error kept apart: GTK writes a line
	# about the icon theme for every icon a theme names, because there is no
	# screen to look one up on, and none of that is a colour.
	local referenced defined
	run --separate-stderr -0 gtk_rule_references "$sheet"
	referenced=$output
	[ -n "$referenced" ] || {
		printf '%s draws with no named colour at all, so no definition of this project reaches it\n' \
			"$theme" >&2
		return 1
	}
	defined=$(sed -n 's/^@define-color \([a-z_]*\) .*/\1/p' "$STYLE_FILE" | LC_ALL=C sort -u)

	# Three surfaces the desktop cannot be themed without. Each line holds
	# every name a GTK 3 theme is known to draw that surface with, and one of
	# them has to be both read by the theme and redefined here.
	local group name found
	while read -r group; do
		found=no
		for name in $group; do
			[[ $'\n'$referenced$'\n' == *$'\n'"$name"$'\n'* ]] || continue
			[[ $'\n'$defined$'\n' == *$'\n'"$name"$'\n'* ]] || continue
			found=yes
		done
		[ "$found" = yes ] || {
			printf '%s draws with none of "%s" that %s redefines\n' \
				"$theme" "$group" "${STYLE_FILE##*/}" >&2
			return 1
		}
	done <<-'GROUPS'
		window_bg_color theme_bg_color
		view_bg_color theme_base_color
		accent_bg_color theme_selected_bg_color
	GROUPS
}

# The map from the palette onto the names GTK draws with, read back out of GTK
# rather than out of the file that wrote it. The chain is three steps, and each
# one is a different record:
#
#   the bundle page says   theme_selected_bg_color -> @accent
#   GTK holds              theme_selected_bg_color -> @accent
#   GTK resolves           @accent -> rgb(122,162,247)
#
# The expectation comes from the page and the result from GTK, so the style
# sheet is never asked what it should say. A test that read the pairs out of
# the style sheet would expect whatever the style sheet said, and a swapped row
# would pass it: that is the shape the first version of this test had, with
# eleven pairs written by hand and ten names covered by nothing.
#
# The number of pairs is compared with the number of definitions, so a name in
# the file that this table never mentions fails here as well.
@test "the widget colours GTK holds are the colours of the active theme" {
	require_gtk
	run -0 link_prescribed
	"$XGHOST" theme set tokyonight >/dev/null

	local dump
	dump=$(gtk_colours "$XDG_CONFIG_HOME/gtk-3.0/gtk.css")

	local name value reference reached expected count=0
	while read -r name value; do
		reached=$(printf '%s\n' "$dump" | sed -n "s/^$name //p")
		[ -n "$reached" ] || {
			printf 'GTK dropped %s, so no widget draws with it\n' "$name" >&2
			return 1
		}

		# A bare reference has to match whole. A CSS function has to be the
		# same function, and GTK prints the number in it to more places than
		# anybody writes, so the names inside it are what is compared.
		[[ $reached == "${value%%(*}"* ]] || {
			printf '%s is %s in GTK and %s on %s\n' \
				"$name" "$reached" "$value" "${PAGE##*/}" >&2
			return 1
		}

		for reference in $(printf '%s\n' "$value" | grep -oE '@[a-z_]+'); do
			[[ $reached == *"$reference"* ]] || {
				printf '%s is %s in GTK and %s on %s\n' \
					"$name" "$reached" "$value" "${PAGE##*/}" >&2
				return 1
			}
			expected=${reference#@}
			# 'run' without a code on purpose: a name that is not in the
			# dump leaves this empty and the report below says which one it
			# was. 'run -0' would end the test with no report at all.
			run bash -c "printf '%s\n' \"\$1\" | sed -n \"s/^\$2 //p\"" _ "$dump" "$expected"
			[ "$output" = "$(gtk_rgb_of "$(palette_value tokyonight "${expected^^}")")" ] || {
				printf '%s reaches %s, which is %s and not the %s of the theme\n' \
					"$name" "$reference" "$output" "${expected^^}" >&2
				return 1
			}
		done
		count=$((count + 1))
	done < <(page_map)

	# Every definition of the sheet was followed from the page into GTK and out
	# to a colour of the theme.
	[ "$count" -eq "$(style_definition_count)" ]
}

# Every focused name has an unfocused twin, and the two hold the same value.
# Leaving a twin out leaves every unfocused window in the colours of the stock
# theme, which is a split nobody chose and which nothing else here would catch.
#
# The twins are read out of the sheet by name. Two of them are irregular,
# because GTK named them so, and the table below is the whole of that
# irregularity.
@test "a window that does not hold the focus draws in the same colours" {
	local name twin value twin_value count=0
	while IFS= read -r twin; do
		case $twin in
		unfocused_insensitive_color) name=insensitive_fg_color ;;
		theme_unfocused_*) name=theme_${twin#theme_unfocused_} ;;
		unfocused_*) name=${twin#unfocused_} ;;
		*) name= ;;
		esac
		[ -n "$name" ] || {
			printf 'the style sheet defines %s and this test knows no twin of it\n' \
				"$twin" >&2
			return 1
		}

		value=$(sed -n "s/^@define-color $name //p" "$STYLE_FILE")
		twin_value=$(sed -n "s/^@define-color $twin //p" "$STYLE_FILE")
		[ -n "$value" ] || {
			printf 'the style sheet defines %s and no %s\n' "$twin" "$name" >&2
			return 1
		}
		[ "$value" = "$twin_value" ] || {
			printf '%s is %s and %s is %s\n' "$name" "$value" "$twin" "$twin_value" >&2
			return 1
		}
		count=$((count + 1))
	done < <(sed -n 's/^@define-color \([a-z_]*unfocused[a-z_]*\) .*/\1/p' "$STYLE_FILE")

	# Every unfocused name of the sheet was read and paired. The libadwaita
	# block has no twin at all, because libadwaita draws an unfocused window
	# with a separate set of names and this desktop draws no distinction.
	[ "$count" -eq "$(grep -c '^@define-color [a-z_]*unfocused' "$STYLE_FILE")" ]
	[ "$count" -ge 8 ]
}

# A border that holds the colour of the surface it is drawn on is not a border.
# This is arithmetic on the palettes rather than an observation: no GTK
# application has drawn these colours.
#
# The floor is 1.30. 1.00 is a line nobody can see, a border of adw-gtk3
# measures about 1.45, and the two values here measure 1.42 and 1.52. The floor
# is not a readability standard: the standard for a line that carries meaning
# is 3.00, and a subtle border does not meet it by design.
@test "the border of every theme is visible on both surfaces of it" {
	local theme count=0
	while IFS= read -r theme; do
		[ -n "$theme" ] || continue

		local against ratio
		for against in bg surface; do
			ratio=$(contrast_of "$theme" borders "$against")
			[ "$ratio" -ge 130 ] || {
				printf 'the border of %s measures %s.%s on the %s of it\n' \
					"$theme" "${ratio%??}" "${ratio: -2}" "$against" >&2
				return 1
			}
			ratio=$(contrast_of "$theme" unfocused_borders "$against")
			[ "$ratio" -ge 130 ]
		done

		# A widget that cannot be used has to differ from one that can. The
		# two surfaces of these palettes are 1.10 apart, so this floor is
		# lower, and the shipped value measures 1.20 and 1.23.
		ratio=$(contrast_of "$theme" insensitive_bg_color theme_base_color)
		[ "$ratio" -ge 115 ] || {
			printf 'a disabled widget of %s measures %s.%s on the surface behind it\n' \
				"$theme" "${ratio%??}" "${ratio: -2}" >&2
			return 1
		}
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 1 ]
}

# The map is written down twice: in the style sheet and on the bundle page. A
# page that drifts from the file is how a reader learns a colour that is not
# there, and a file that drifts from the page is how a widget quietly changes
# colour, so the two are compared name by name and value by value.
@test "the map the bundle page records is the map the style sheet defines" {
	local recorded defined
	recorded=$(page_map | LC_ALL=C sort)
	defined=$(style_definitions | LC_ALL=C sort)

	[ -n "$recorded" ]
	[ "$recorded" = "$defined" ] || {
		printf 'the page and the style sheet do not hold the same map:\n' >&2
		diff <(printf '%s\n' "$recorded") <(printf '%s\n' "$defined") >&2
		return 1
	}

	# The page states the number three times in prose and in a table, and a
	# number in prose is the one thing no reader checks. Every one of the three
	# is read here, because the last version of this page said "twenty" when
	# the file held twenty-one.
	local count phrase
	count=$(style_definition_count)
	while IFS= read -r phrase; do
		run -0 grep -Fq "$phrase" "$PAGE"
	done <<-PHRASES
		redefines $count of them
		| **$count**
		is $count colour names that reach nothing
	PHRASES
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

# --- what this suite does not prove -------------------------------------------

# A skipped test proves nothing, and two of the tests that can skip have no
# file-reading equivalent at all: the one that asks the package database
# whether a package really ships the theme, and the one that reads the rules of
# the installed theme. So the set of tests that can skip is a budget, and the
# bundle page holds it.
#
# Nothing else reports it. Continuous integration prints TAP, which marks a
# skip on the line of the test and prints no count at the end, so a run whose
# skip set doubled reads exactly like a run whose skip set did not.
@test "the tests that can skip are the ones the bundle page lists" {
	local budget listed
	budget=$(skipping_tests | LC_ALL=C sort)
	listed=$(page_rows_under '### The tests that can skip, and why' |
		sed -n 's/^| `\([^`]*\)`.*/\1/p' | LC_ALL=C sort)

	[ -n "$listed" ]
	[ "$budget" = "$listed" ] || {
		printf 'the tests that can skip and the list on %s differ:\n' "${PAGE##*/}" >&2
		diff <(printf '%s\n' "$listed") <(printf '%s\n' "$budget") >&2
		return 1
	}

	# The page states the two numbers in prose as well.
	local total
	total=$(grep -c '^@test "' "$SUITE_FILE")
	run -0 grep -Fq "$(printf '%s of the %s tests' "$(printf '%s\n' "$budget" | wc -l)" "$total")" "$PAGE"
}
