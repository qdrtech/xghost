#!/usr/bin/env bats
#
# Tests for the documentation itself.
#
# Prose cannot be tested and is not tested here. What is tested is the part of
# the documentation that repeats a fact some file of this project already owns,
# because that is the part that drifts. Five such facts exist today:
#
#   - A link to another page of this repository. The target either is there or
#     it is not.
#   - The knobs. 'schema/knobs.conf' is the source of truth for every knob, the
#     values it takes and its default, and docs/knobs.md writes the same list
#     out for a reader.
#   - The names a palette must declare. 'templates/' is the source of truth,
#     because a template that names a value no palette declares is what fails a
#     render, and docs/theming.md writes the same list out for the author of a
#     new theme.
#   - The commands. The metadata block of each file in commands/ is the source
#     of truth, the dispatcher prints it, and the README writes the same list
#     out under another layout.
#   - The packages. 'install/packages/base.txt' and 'aur.txt' are the source of
#     truth for the dependencies, and tests/install.bats holds that pair, both
#     ways round.
#
# A rule with no test is a rule that lasts one slice. These are the rules of
# issue #21 that a file can answer.
#
# The one command this suite runs is 'bin/xghost' with no argument, which
# prints the grouped help and does nothing else. Nothing here links a file,
# renders a theme, or signals anything.
bats_require_minimum_version 1.5.0

setup() {
	ROOT_DIR="$BATS_TEST_DIRNAME/.."
	SCHEMA="$ROOT_DIR/schema/knobs.conf"
	KNOBS_PAGE="$ROOT_DIR/docs/knobs.md"
	THEMING_PAGE="$ROOT_DIR/docs/theming.md"
	TEMPLATE_DIR="$ROOT_DIR/templates"
	README="$ROOT_DIR/README.md"
	XGHOST="$ROOT_DIR/bin/xghost"

	# The shipped commands, never the fixture directory of another test file
	# and never a directory the person running the suite happens to name.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"
}

# Every documentation file of this repository: the README and every page under
# docs/, at any depth. A file added later is read by the same list.
doc_files() {
	printf '%s\n' "$ROOT_DIR/README.md"
	find "$ROOT_DIR/docs" -name '*.md' -type f | sort
}

# The names the schema declares, one per line, in the order it declares them.
schema_knobs() {
	sed -n 's/^knob=\(.*\)$/\1/p' "$SCHEMA"
}

# The values one knob takes, one per line, in the order the schema declares
# them. The record of a knob starts at its 'knob=' line and ends at the next
# one.
schema_values() {
	awk -v want="$1" -v field="${2:-value}" '
		/^knob=/ { inside = (substr($0, 6) == want) }
		inside && index($0, field "=") == 1 { print substr($0, length(field) + 2) }
	' "$SCHEMA"
}

# The backticked spans of one field of a markdown table row, one per line.
# 'a`b`, `c`' yields 'b' and 'c'.
backticked() {
	printf '%s\n' "$1" | grep -o '`[^`]*`' | sed 's/^.//; s/.$//'
}

# One field of a markdown table row, counted from 1 after the leading pipe,
# with the white space at both ends dropped.
table_field() {
	printf '%s\n' "$1" | awk -F'|' -v n="$2" '{
		field = $(n + 1)
		gsub(/^[ \t]+|[ \t]+$/, "", field)
		print field
	}'
}

#
# The links.
#

# A link that names a file of this repository is a claim about the tree, so it
# is checkable. A link that goes out to the network is not checked: a test that
# reaches GitHub would fail on a runner with no network and would report the
# network rather than the documentation.
@test "every documentation link to this repository resolves" {
	local file dir target resolved checked=0
	while IFS= read -r file; do
		dir=${file%/*}
		while IFS= read -r target; do
			[ -n "$target" ] || continue
			# The anchor of a heading is not a path.
			target=${target%%#*}
			[ -n "$target" ] || continue
			checked=$((checked + 1))
			resolved=$dir/$target
			[ -e "$resolved" ] || {
				printf '%s links to %s and there is nothing there\n' \
					"${file#"$ROOT_DIR"/}" "$target" >&2
				return 1
			}
		done < <(grep -o '](\([^)]*\))' "$file" |
			sed 's/^](//; s/)$//' |
			grep -v '^[a-z][a-z0-9+.-]*:' |
			grep -v '^#')
	done < <(doc_files)

	# A pattern that stopped matching would pass this test without a link ever
	# being read.
	[ "$checked" -gt 100 ] || {
		printf 'only %d links were read, so the pattern is not reading the pages\n' \
			"$checked" >&2
		return 1
	}
}

#
# The knobs. schema/knobs.conf is the source of truth.
#

@test "the schema declares the knobs this project has" {
	# The floor under the two tests below: a schema this test cannot read
	# would let both of them pass with nothing compared.
	run -0 schema_knobs
	[ -n "$output" ]
	[ "$(printf '%s\n' "$output" | wc -l)" -ge 4 ]
}

@test "docs/knobs.md documents every knob of the schema, and no other" {
	local documented schema
	documented=$(sed -n 's/^| `\(KNOB_[A-Z0-9_]*\)`.*$/\1/p' "$KNOBS_PAGE" | sort -u)
	schema=$(schema_knobs | sort -u)

	[ "$documented" = "$schema" ] || {
		printf 'the knob table of docs/knobs.md and schema/knobs.conf differ\n' >&2
		printf 'documented:\n%s\nthe schema declares:\n%s\n' "$documented" "$schema" >&2
		return 1
	}
}

@test "docs/knobs.md documents the values and the default of every knob" {
	local knob row page_values page_default schema_values_list schema_default
	while IFS= read -r knob; do
		# The row of the table of allowed values. The page names a knob in
		# more than one table, and this is the one whose second field holds
		# every value and whose third holds the default.
		row=$(grep -m 1 "^| \`$knob\` *|" "$KNOBS_PAGE") || {
			printf 'docs/knobs.md carries no table row for %s\n' "$knob" >&2
			return 1
		}

		page_values=$(backticked "$(table_field "$row" 2)")
		page_default=$(backticked "$(table_field "$row" 3)")
		schema_values_list=$(schema_values "$knob" value)
		schema_default=$(schema_values "$knob" default)

		[ "$page_values" = "$schema_values_list" ] || {
			printf '%s: docs/knobs.md lists the values\n%s\nand the schema declares\n%s\n' \
				"$knob" "$page_values" "$schema_values_list" >&2
			return 1
		}
		[ "$page_default" = "$schema_default" ] || {
			printf '%s: docs/knobs.md gives the default as %s and the schema gives %s\n' \
				"$knob" "$page_default" "$schema_default" >&2
			return 1
		}
	done < <(schema_knobs)
}

# A knob name is written in more pages than the one that documents the list:
# the README names one, and every bundle page names the knobs it carries. A
# knob the project drops has to leave all of them, and this is what says so.
#
# 'KNOB_NAME' is the one exception, and it is a shape rather than a name.
# docs/knobs.md writes it three times to state the form a knob takes in a file
# and in a template. It is allowed on that page and on no other, because a
# placeholder on any other page is a page that meant a real knob.
@test "every knob name the documentation writes is declared by the schema" {
	local declared file name checked=0
	declared=$(schema_knobs)

	[[ $'\n'$declared$'\n' != *$'\n'KNOB_NAME$'\n'* ]] || {
		printf 'the schema declares KNOB_NAME, so it is no longer a placeholder\n' >&2
		return 1
	}

	while IFS= read -r file; do
		while IFS= read -r name; do
			checked=$((checked + 1))
			if [ "$name" = KNOB_NAME ]; then
				[ "$file" = "$KNOBS_PAGE" ] || {
					printf '%s writes the placeholder KNOB_NAME where a knob belongs\n' \
						"${file#"$ROOT_DIR"/}" >&2
					return 1
				}
				continue
			fi
			[[ $'\n'$declared$'\n' == *$'\n'"$name"$'\n'* ]] || {
				printf '%s writes %s and the schema does not declare it\n' \
					"${file#"$ROOT_DIR"/}" "$name" >&2
				return 1
			}
		done < <(grep -o 'KNOB_[A-Z0-9][A-Z0-9_]*' "$file" | sort -u)
	done < <(doc_files)

	[ "$checked" -gt 10 ] || {
		printf 'only %d knob names were read across the documentation\n' "$checked" >&2
		return 1
	}
}

#
# The names a palette must declare. templates/ is the source of truth.
#
# The source of truth is the templates rather than the shipped palettes, and
# the choice is the whole of this section. Two questions look like one:
#
#   - What do the shipped themes declare? That is what 'themes/*/palette.conf'
#     answers, and it is a fact about two themes.
#   - What must a palette declare? That is what the templates answer, because a
#     template that names a value the palette does not declare is what fails a
#     render, by name, in lib/renderer.sh.
#
# docs/theming.md is written for the author of a new theme, who has neither of
# the shipped palettes and who meets the second question alone. So the page
# follows the templates. A name every shipped palette happened to declare that
# no template read would be dead weight that author would copy, and the page
# would be teaching it.
#
# The two sets are identical today, and the tests below are what keep them so.
# tests/golden.bats holds one direction already: it renders every shipped theme
# against every template, so a template that read an eleventh name would fail
# there. Nothing held the other direction before this, and the last test of this
# section is it.
#

# Every palette name the templates read, one per line, sorted, each one given
# once.
#
#   template_palette_names DIR
#
# Three things a plain grep for '@[A-Z_]*@' would get wrong, and they are why
# the renderer's own patterns are read rather than copied:
#
#   - The escape. '@@NAME@@' writes the literal text '@NAME@' and reads no
#     value, so it is not a reference to anything. A grep would count it as one.
#     RENDER_TOKEN_PATTERN matches leftmost and longest, which is what tells the
#     two apart, and the loop below is the loop of render_substitute.
#   - The derived forms. A template names '@BG_HEX@' or '@BG_RGB@' where the
#     palette declares 'BG' alone. lib/palette.sh appends exactly one suffix to
#     a declared name, so exactly one comes off again. A palette key may not end
#     in either suffix, so the fold always lands on one declared name.
#   - The other two sources. A machine fact starts with 'MACHINE_' and a knob
#     with 'KNOB_'. Neither is a name a palette declares.
#
# A structural choice reads a name as well: '<file>.choice.<NAME>' needs NAME
# declared, exactly as a placeholder does. So the directory names are read too,
# the way render_choice_plan reads them. No shipped choice is keyed on a palette
# name today, and one added later is read here the day it lands.
template_palette_names() {
	# The collector runs in a shell of its own, which sources lib/renderer.sh at
	# the top level of that shell. A library sourced inside a bats setup() would
	# put its 'declare -A' arrays in the scope of that function, and they would
	# be gone by the time a test body ran. tests/renderer.bats and
	# tests/facts.bats read the libraries the same way.
	bash -c '
		set -euo pipefail
		. "$1/lib/renderer.sh"

		declare -A found=()
		path= rest= match= prefix= base= name=

		while IFS= read -r path; do
			[ -n "$path" ] || continue
			rest=$(cat "$path")
			while [[ $rest =~ $RENDER_TOKEN_PATTERN ]]; do
				match=${BASH_REMATCH[0]}
				prefix=${rest%%"$match"*}
				rest=${rest#"$prefix$match"}
				# The escape reads no value, so the name inside it is not a
				# reference to anything. This is the whole of the difference
				# between this collector and a grep.
				if [ "${match:0:2}" = "@@" ]; then
					continue
				fi
				found[${match:1:${#match}-2}]=1
			done
		done < <(find -L "$2" -type f)

		while IFS= read -r path; do
			[ -n "$path" ] || continue
			base=${path##*/}
			if [[ $base =~ $RENDER_CHOICE_PATTERN ]]; then
				found[${BASH_REMATCH[2]}]=1
			fi
		done < <(find -L "$2" -mindepth 1 -type d)

		for name in ${found[@]+"${!found[@]}"}; do
			case $name in
			MACHINE_* | KNOB_*) continue ;;
			esac
			case $name in
			*_HEX) name=${name%_HEX} ;;
			*_RGB) name=${name%_RGB} ;;
			esac
			printf "%s\n" "$name"
		done
	' _ "$ROOT_DIR" "$1" | LC_ALL=C sort -u
}

# The names the table of docs/theming.md lists, one per line, sorted. Only the
# rows of the one section are read, so a backticked name anywhere else on that
# page is never mistaken for a row of it.
page_palette_names() {
	awk '
		/^### The names a palette must declare$/ { inside = 1; next }
		inside && /^#/ { inside = 0 }
		inside && match($0, /^\| `[A-Z][A-Z0-9_]*`/) {
			print substr($0, 4, RLENGTH - 4)
		}
	' "$THEMING_PAGE" | LC_ALL=C sort -u
}

# The names one palette declares, one per line, sorted. lib/palette.sh is what
# reads the file, so this suite never grows a second reader of the format. The
# two derived forms are dropped: they are the renderer's and not the author's,
# and a declared key can never end in either suffix.
palette_names() {
	bash -c '
		set -euo pipefail
		. "$1/lib/palette.sh"
		palette_load "$2" || exit 1
		name=
		for name in ${PALETTE_SCALARS[@]+"${!PALETTE_SCALARS[@]}"}; do
			case $name in
			*_HEX | *_RGB) continue ;;
			esac
			printf "%s\n" "$name"
		done
	' _ "$ROOT_DIR" "$1" | LC_ALL=C sort -u
}

# The floor under the comparison below. A collector that read nothing would let
# the first of the two comparisons pass with no name ever compared, and that is
# how it read while the collector was still being written.
@test "the templates read the palette names this project has" {
	run -0 template_palette_names "$TEMPLATE_DIR"
	[ -n "$output" ]
	[ "$(printf '%s\n' "$output" | wc -l)" -ge 8 ]
}

@test "docs/theming.md lists every palette name the templates read" {
	local read_by_templates listed name
	read_by_templates=$(template_palette_names "$TEMPLATE_DIR")
	listed=$(page_palette_names)

	while IFS= read -r name; do
		[ -n "$name" ] || continue
		[[ $'\n'$listed$'\n' == *$'\n'"$name"$'\n'* ]] || {
			printf 'a template reads %s and docs/theming.md does not list it\n' "$name" >&2
			printf 'docs/theming.md lists:\n%s\n' "$listed" >&2
			return 1
		}
	done <<<"$read_by_templates"
}

# The other direction, and it is the half that makes the table derived rather
# than merely consistent. A name on the page that no template reads is a name
# the author of a new theme would declare for nothing, and the test above would
# never see it.
@test "every palette name docs/theming.md lists is read by a template" {
	local read_by_templates listed name rows=0
	read_by_templates=$(template_palette_names "$TEMPLATE_DIR")
	listed=$(page_palette_names)

	while IFS= read -r name; do
		[ -n "$name" ] || continue
		rows=$((rows + 1))
		[[ $'\n'$read_by_templates$'\n' == *$'\n'"$name"$'\n'* ]] || {
			printf 'docs/theming.md lists %s and no template reads it\n' "$name" >&2
			printf 'the templates read:\n%s\n' "$read_by_templates" >&2
			return 1
		}
	done <<<"$listed"

	# A table this test could not read would leave it comparing nothing.
	[ "$rows" -ge 8 ] || {
		printf 'only %d names were read out of the table of docs/theming.md\n' "$rows" >&2
		return 1
	}
}

# The shipped palettes are not the source of truth, and this is what keeps them
# equal to it anyway. A shipped palette that declared a name no template reads
# is the dead weight the section above describes: nothing would report it, and
# the next theme would be copied from it.
@test "every shipped palette declares the names docs/theming.md lists, and no other" {
	local listed theme declared themes=0
	listed=$(page_palette_names)

	[ -n "$listed" ] || {
		printf 'the table of docs/theming.md could not be read, so nothing was compared\n' >&2
		return 1
	}

	for theme in "$ROOT_DIR"/themes/*/palette.conf; do
		[ -f "$theme" ] || continue
		themes=$((themes + 1))
		declared=$(palette_names "$theme") || {
			printf '%s cannot be read\n' "${theme#"$ROOT_DIR"/}" >&2
			return 1
		}
		[ "$declared" = "$listed" ] || {
			printf '%s declares\n%s\nand docs/theming.md lists\n%s\n' \
				"${theme#"$ROOT_DIR"/}" "$declared" "$listed" >&2
			return 1
		}
	done

	[ "$themes" -ge 2 ] || {
		printf 'only %d shipped palettes were read\n' "$themes" >&2
		return 1
	}
}

# The collector against inputs that hold every case at once. Two of them reach
# no shipped template today: no template escapes a placeholder, and no shipped
# choice is keyed on a palette name. So the tests above would pass with a
# collector that got either of those two wrong, and this is where both are read.
@test "the palette-name collector reads the escape, the derived forms and the other two sources" {
	local dir="$BATS_TEST_TMPDIR/templates"
	mkdir -p "$dir/hypr" "$dir/panel.conf.choice.SURFACE_STYLE"
	cat >"$dir/hypr/demo.conf" <<-'EOF'
		plain   = @BG@
		derived = @ACCENT_HEX@ @ACCENT_RGB@
		escaped = @@GHOST@@
		fact    = @MACHINE_MONITOR_1_NAME@
		knob    = @KNOB_FONT@
	EOF
	printf 'x = @TEXT@\n' >"$dir/panel.conf.choice.SURFACE_STYLE/default"

	run -0 template_palette_names "$dir"
	[ "$output" = 'ACCENT
BG
SURFACE_STYLE
TEXT' ]
}

#
# The commands. The metadata block of each file in commands/ is the source of
# truth, and the dispatcher is what reads it.
#

# The README carries the list of commands a reader runs. That list is the
# grouped help under another layout, so a command added, renamed, hidden or
# resummarised has to reach the page as well. The dispatcher is asked rather
# than the files, because the dispatcher is what a user sees.
@test "the README lists every command with the summary the dispatcher prints" {
	local group verb summary key documented=0
	local -A shipped=()

	run -0 "$XGHOST"
	while IFS= read -r line; do
		case $line in
		'  '*)
			[ -n "$group" ] || continue
			verb=$(printf '%s\n' "$line" | sed -n 's/^  \([a-z-]*\)  *.*$/\1/p')
			summary=$(printf '%s\n' "$line" | sed -n 's/^  [a-z-]*  *\(.*[^ ]\) *$/\1/p')
			[ -n "$verb" ] || continue
			shipped["$group $verb"]=$summary
			;;
		'')
			;;
		[a-z]*)
			# A group heading is one word at the start of a line. Every other
			# line of that shape is prose, and it carries a space.
			case $line in
			*' '*) group="" ;;
			*) group=$line ;;
			esac
			;;
		*)
			group=""
			;;
		esac
	done <<<"$output"

	[ "${#shipped[@]}" -ge 12 ] || {
		printf 'the dispatcher reported %d commands, so this test read its help wrongly\n' \
			"${#shipped[@]}" >&2
		return 1
	}

	while IFS= read -r line; do
		key=$(printf '%s\n' "$line" | sed -n 's/^| `xghost \([a-z-]*\) \([a-z-]*\)[^|]*| *\(.*[^ ]\) *|$/\1 \2/p')
		summary=$(printf '%s\n' "$line" | sed -n 's/^| `xghost \([a-z-]*\) \([a-z-]*\)[^|]*| *\(.*[^ ]\) *|$/\3/p')
		[ -n "$key" ] || continue
		documented=$((documented + 1))

		[ -n "${shipped[$key]+set}" ] || {
			printf 'the README lists "xghost %s" and the dispatcher does not\n' "$key" >&2
			return 1
		}
		[ "$summary" = "${shipped[$key]}" ] || {
			printf 'xghost %s: the README says\n  %s\nand the dispatcher says\n  %s\n' \
				"$key" "$summary" "${shipped[$key]}" >&2
			return 1
		}
	done <"$README"

	[ "$documented" -eq "${#shipped[@]}" ] || {
		printf 'the dispatcher has %d commands and the README lists %d of them\n' \
			"${#shipped[@]}" "$documented" >&2
		return 1
	}
}
