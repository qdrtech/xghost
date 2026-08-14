#!/usr/bin/env bats
#
# Tests for lib/json.sh, the JSON reader of the detection.
#
# The reader is a pure function: it takes one string and fills two arrays. It
# is therefore tested directly, against text this file writes, and no test here
# depends on anything about the machine that runs it.
bats_require_minimum_version 1.5.0

setup() {
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	FIXTURES="$BATS_TEST_DIRNAME/fixtures/detect"
}

# Run one snippet against the libraries. The snippet arrives on standard input,
# and it is given the checkout as $1 and the fixture directory as $2.
run_snippet() {
	local script="$BATS_TEST_TMPDIR/snippet.sh"
	cat >"$script"
	run bash "$script" "$ROOT_DIR" "$FIXTURES"
}

# Read one document and print what the reader holds for each path this test
# asks about, so that a test reads as the document beside the result.
#
#   show TEXT PATH...
show() {
	local script="$BATS_TEST_TMPDIR/show.sh"
	cat >"$script" <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		text=$2
		shift 2
		if ! json_parse "$text"; then
			printf 'problem: %s\n' "$JSON_ERROR"
			exit 1
		fi
		for path in "$@"; do
			if [ -n "${JSON_SIZE[$path]+set}" ]; then
				printf 'size %s = %s\n' "$path" "${JSON_SIZE[$path]}"
			fi
			if [ -n "${JSON_VALUE[$path]+set}" ]; then
				printf 'value %s = %s\n' "$path" "${JSON_VALUE[$path]}"
			fi
			if [ -z "${JSON_SIZE[$path]+set}" ] && [ -z "${JSON_VALUE[$path]+set}" ]; then
				printf 'absent %s\n' "$path"
			fi
		done
	EOF
	run bash "$script" "$ROOT_DIR" "$@"
}

# --- what the reader accepts ------------------------------------------------

@test "json reads the members of an object" {
	show '{"name": "DP-2", "width": 2560}' . name width
	[ "$status" -eq 0 ]
	[ "$output" = "size . = 2
value name = DP-2
value width = 2560" ]
}

@test "json names an array member by its index, counted from zero" {
	show '[{"name": "one"},{"name": "two"}]' . 0.name 1.name
	[ "$status" -eq 0 ]
	[ "$output" = "size . = 2
value 0.name = one
value 1.name = two" ]
}

@test "json reads a document nested three levels deep" {
	show '{"a": [{"b": {"c": 1}}]}' a.0.b.c
	[ "$status" -eq 0 ]
	[ "$output" = "value a.0.b.c = 1" ]
}

@test "json records the size of an empty object and of an empty array" {
	show '{"one": {}, "two": []}' one two
	[ "$status" -eq 0 ]
	[ "$output" = "size one = 0
size two = 0" ]
}

@test "json records the size of an array of scalars" {
	show '{"reserved": [0, 40, 0, 0]}' reserved reserved.1
	[ "$status" -eq 0 ]
	[ "$output" = "size reserved = 4
value reserved.1 = 40" ]
}

@test "json reads true, false and null as the words they are" {
	show '{"a": true, "b": false, "c": null}' a b c
	[ "$status" -eq 0 ]
	[ "$output" = "value a = true
value b = false
value c = null" ]
}

# The word null and the string "null" read back as the same four characters,
# and so do true and "true", and 1 and "1". The kind is what tells them apart.
# A caller that reads the value alone cannot tell "this member has no value"
# from "this member is the word null", and it would write the second one into a
# configuration file as though a program had reported it.
@test "json records the kind of every value" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		json_parse '{"a":null,"b":"null","c":true,"d":"true","e":1,"f":"1","g":{},"h":[]}' || exit 1
		for path in . a b c d e f g h; do
			printf '%s %s %s\n' "$path" "${JSON_KIND[$path]}" "${JSON_VALUE[$path]-<none>}"
		done
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = ". object <none>
a literal null
b string null
c literal true
d string true
e number 1
f string 1
g object <none>
h array <none>" ]
}

# An array and an object both record a size, and the size of an object is the
# number of its member names. A caller that reads a count needs to know which
# of the two it is holding, or it reports a member count as a monitor count.
@test "json tells an array at the root from an object at the root" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		for text in '[1,2,3]' '{"a":1,"b":2,"c":3}'; do
			json_parse "$text" || exit 1
			printf '%s is an %s of size %s\n' "$text" "${JSON_KIND[$JSON_ROOT]}" "${JSON_SIZE[$JSON_ROOT]}"
		done
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "[1,2,3] is an array of size 3
{\"a\":1,\"b\":2,\"c\":3} is an object of size 3" ]
}

@test "json keeps the digits of a number exactly as the document wrote them" {
	show '{"a": 59.99700, "b": 1.00, "c": -3, "d": 1e3}' a b c d
	[ "$status" -eq 0 ]
	[ "$output" = "value a = 59.99700
value b = 1.00
value c = -3
value d = 1e3" ]
}

@test "json reads the escapes of a string" {
	show '{"a": "one\ttwo", "b": "a\\b", "c": "say \"hi\"", "d": "a\/b"}' a b c d
	[ "$status" -eq 0 ]
	[ "$output" = "value a = one	two
value b = a\\b
value c = say \"hi\"
value d = a/b" ]
}

@test "json reads a string that holds UTF-8 text" {
	show '{"a": "été"}' a
	[ "$status" -eq 0 ]
	[ "$output" = "value a = été" ]
}

@test "json reads a code point escape and a surrogate pair" {
	show '{"a": "\u00e9 \ud83d\ude00"}' a
	[ "$status" -eq 0 ]
	[ "$output" = "value a = é 😀" ]
}

@test "json reads a string that holds a full stop in its member name" {
	show '{"a.b": 1}' a.b
	[ "$status" -eq 0 ]
	[ "$output" = "value a.b = 1" ]
}

@test "json keeps the last value of a member name that is given twice" {
	show '{"a": 1, "a": 2}' a
	[ "$status" -eq 0 ]
	[ "$output" = "value a = 2" ]
}

# "The last one wins" has to mean the whole member, not its scalar alone. A
# member that another replaces has to leave nothing of itself behind, or a
# caller reads a path of a value the document no longer holds. The size of the
# object counts the name once for the same reason.
@test "a member name given twice leaves nothing of the earlier one" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		for text in '{"a":2,"a":{"b":1}}' '{"a":{"b":1},"a":2}' '{"a":1,"a":2}'; do
			json_parse "$text" || { printf 'problem: %s\n' "$JSON_ERROR"; exit 1; }
			printf '%s -> a=%s size a=%s a.b=%s members=%s\n' "$text" \
				"${JSON_VALUE[a]-<absent>}" "${JSON_SIZE[a]-<absent>}" \
				"${JSON_VALUE[a.b]-<absent>}" "${JSON_SIZE[$JSON_ROOT]}"
		done
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = '{"a":2,"a":{"b":1}} -> a=<absent> size a=1 a.b=1 members=1
{"a":{"b":1},"a":2} -> a=2 size a=<absent> a.b=<absent> members=1
{"a":1,"a":2} -> a=2 size a=<absent> a.b=<absent> members=1' ]
}

@test "json accepts white space between every token" {
	show '  {  "a"  :  [  1  ,  2  ]  }  ' a a.1
	[ "$status" -eq 0 ]
	[ "$output" = "size a = 2
value a.1 = 2" ]
}

@test "json reports a path the document does not hold" {
	show '{"a": 1}' b
	[ "$status" -eq 0 ]
	[ "$output" = "absent b" ]
}

# --- what the reader refuses ------------------------------------------------

@test "json refuses text after the end of the document" {
	show '{"a": 1} trailing' a
	[ "$status" -eq 1 ]
	[[ $output == *"text follows the end of the document"* ]]
}

@test "json refuses an object with no comma between two members" {
	show '{"a": 1 "b": 2}' a
	[ "$status" -eq 1 ]
	[[ $output == *"a comma or a closing brace was expected"* ]]
}

@test "json refuses an array with no comma between two members" {
	show '[1 2]' 0
	[ "$status" -eq 1 ]
	[[ $output == *"a comma or a closing bracket was expected"* ]]
}

@test "json refuses a member with no colon" {
	show '{"a" 1}' a
	[ "$status" -eq 1 ]
	[[ $output == *"a colon was expected after the member name 'a'"* ]]
}

@test "json refuses a member name that is not a string" {
	show '{a: 1}' a
	[ "$status" -eq 1 ]
	[[ $output == *"a member name was expected"* ]]
}

@test "json refuses a number that is not a JSON number" {
	show '{"a": 01}' a
	[ "$status" -eq 1 ]
	[[ $output == *"'01' is not a JSON number"* ]]
}

@test "json refuses a word that is not a JSON value" {
	show '{"a": yes}' a
	[ "$status" -eq 1 ]
	[[ $output == *"is not a JSON value"* ]]
}

@test "json refuses a string that is never closed" {
	show '{"a": "open}' a
	[ "$status" -eq 1 ]
	[[ $output == *"the text ends inside a string"* ]]
}

@test "json refuses an escape it does not know" {
	show '{"a": "one\qtwo"}' a
	[ "$status" -eq 1 ]
	[[ $output == *"is not a JSON escape"* ]]
}

@test "json refuses a code point escape that is not four hexadecimal digits" {
	show '{"a": "\u12"}' a
	[ "$status" -eq 1 ]
	[[ $output == *"hexadecimal digits"* ]]
}

@test "json refuses a high surrogate with no low one after it" {
	show '{"a": "\ud83d!"}' a
	[ "$status" -eq 1 ]
	[[ $output == *"a high surrogate is not followed by a low one"* ]]
}

# A low surrogate means nothing on its own. Encoding it as a code point of its
# own produces CESU-8, which is not UTF-8, and the reader would then hand its
# caller bytes that cannot be written to a configuration file. Both halves are
# refused, not the high one alone.
@test "json refuses a low surrogate that stands on its own" {
	show '{"a": "\udc00"}' a
	[ "$status" -eq 1 ]
	[[ $output == *"a low surrogate stands on its own"* ]]
}

# Bash refuses an empty array subscript, and that is a fatal shell error rather
# than a return value. A reader that built the path anyway would kill its
# caller from inside the 'if !' that was meant to catch the problem.
@test "json refuses an empty member name, and the caller carries on" {
	run_snippet <<-'EOF'
		set -euo pipefail
		. "$1/lib/json.sh"
		if ! json_parse '{"":1}'; then printf 'root: %s\n' "$JSON_ERROR"; fi
		if ! json_parse '{"a":{"":1}}'; then printf 'nested: %s\n' "$JSON_ERROR"; fi
		printf 'the caller is still running\n'
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "root: offset 1: a member name is empty, and every value has to have a path
nested: offset 6: a member name is empty, and every value has to have a path
the caller is still running" ]
}

# The scan is quadratic, so a document far larger than the answers this reader
# exists for would take minutes rather than fail. It is refused by name and by
# its length instead.
@test "json refuses a document longer than the limit, and names the limit" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		printf -v filler '%*s' "$JSON_MAX_BYTES" ''
		if json_parse "{\"a\":\"$filler\"}"; then
			printf 'accepted\n'
		else
			printf '%s\n' "$JSON_ERROR"
		fi
	EOF
	[ "$status" -eq 0 ]
	[[ $output == *"and this reader accepts 262144"* ]]
}

# bash cannot hold a NUL byte in a variable, so a reader that dropped the byte
# would return a string that differs from the one the document holds.
@test "json refuses the escape for the code point zero" {
	show '{"a": "\u0000"}' a
	[ "$status" -eq 1 ]
	[[ $output == *"cannot hold a NUL byte"* ]]
}

@test "json refuses an empty document" {
	show '' .
	[ "$status" -eq 1 ]
	[[ $output == *"a value was expected, and the text ends"* ]]
}

@test "json refuses a document that nests deeper than the limit" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		text=
		for ((i = 0; i <= JSON_MAX_DEPTH + 2; i++)); do text=$text'['; done
		text=$text'1'
		for ((i = 0; i <= JSON_MAX_DEPTH + 2; i++)); do text=$text']'; done
		if json_parse "$text"; then printf 'accepted\n'; else printf '%s\n' "$JSON_ERROR"; fi
	EOF
	[ "$status" -eq 0 ]
	[[ $output == *"nests deeper than"* ]]
}

# The limit is a count of levels, and the whole document is level 1. A document
# of exactly JSON_MAX_DEPTH levels is read, and one level more is refused, so
# the number the reader names is the number it enforces.
@test "json reads exactly the depth limit and refuses one level more" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		# LEVELS levels is LEVELS - 1 arrays around one number.
		nest() {
			local levels=$1 i text=
			for ((i = 1; i < levels; i++)); do text=$text'['; done
			text=$text'1'
			for ((i = 1; i < levels; i++)); do text=$text']'; done
			printf '%s' "$text"
		}
		for levels in $((JSON_MAX_DEPTH - 1)) "$JSON_MAX_DEPTH" $((JSON_MAX_DEPTH + 1)); do
			if json_parse "$(nest "$levels")"; then
				printf '%s levels: read\n' "$levels"
			else
				printf '%s levels: refused\n' "$levels"
			fi
		done
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "31 levels: read
32 levels: read
33 levels: refused" ]
}

# --- the answers this reader exists for -------------------------------------

@test "json reads the answer of 'hyprctl monitors -j'" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		IFS= read -r -d '' text <"$2/monitors-two.json" || true
		if ! json_parse "$text"; then printf 'problem: %s\n' "$JSON_ERROR"; exit 1; fi
		printf '%s %s %s %s\n' "${JSON_SIZE[.]}" "${JSON_VALUE[0.name]}" \
			"${JSON_VALUE[1.refreshRate]}" "${JSON_VALUE[0.activeWorkspace.name]}"
		printf '%s %s\n' "${JSON_SIZE[0.reserved]}" "${JSON_SIZE[1.availableModes]}"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "2 DP-1 59.99900 1
4 1" ]
}

@test "json reads the answer of 'hyprctl devices -j'" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/json.sh"
		IFS= read -r -d '' text <"$2/devices-laptop.json" || true
		if ! json_parse "$text"; then printf 'problem: %s\n' "$JSON_ERROR"; exit 1; fi
		printf '%s %s %s %s %s\n' "${JSON_SIZE[mice]}" "${JSON_SIZE[keyboards]}" \
			"${JSON_SIZE[tablets]}" "${JSON_SIZE[touch]}" "${JSON_SIZE[switches]}"
		printf '%s %s\n' "${JSON_VALUE[keyboards.0.name]}" "${JSON_VALUE[keyboards.0.main]}"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "2 2 0 1 1
at-translated-set-2-keyboard true" ]
}

# The text a JSON reader is given comes from another program. This reader
# expands nothing and runs nothing, so that text can never become code.
@test "json runs nothing that the text it reads holds" {
	local evidence="$BATS_TEST_TMPDIR/evidence"
	show "{\"a\": \"\$(touch $evidence)\"}" a
	[ "$status" -eq 0 ]
	[ "$output" = "value a = \$(touch $evidence)" ]
	[ ! -e "$evidence" ]
}
