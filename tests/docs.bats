#!/usr/bin/env bats
#
# Tests for the documentation itself.
#
# Prose cannot be tested and is not tested here. What is tested is the part of
# the documentation that repeats a fact some file of this project already owns,
# because that is the part that drifts. Four such facts exist today:
#
#   - A link to another page of this repository. The target either is there or
#     it is not.
#   - The knobs. 'schema/knobs.conf' is the source of truth for every knob, the
#     values it takes and its default, and docs/knobs.md writes the same list
#     out for a reader.
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
