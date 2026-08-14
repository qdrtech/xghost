#!/usr/bin/env bats
#
# Tests for lib/facts.sh, the machine facts format, and for the renderer that
# reads a machine facts file beside the theme palette.
#
# The format is pure: it is a reader and two text functions. It is therefore
# tested directly. The renderer is tested through the real command, as every
# other renderer test is. No test here depends on the hardware of the machine
# that runs it.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)

	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	# The renderer writes under the state directory of the user, so each test
	# gets a home of its own and touches nothing outside it.
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_STATE_HOME"

	# The knobs are the third input of the renderer, and no test here asserts on
	# one. They are pinned all the same, so a knobs file of whoever runs the
	# suite never reaches a render.
	use_own_knobs

	GENERATED="$XDG_STATE_HOME/xghost/generated"

	# A machine facts file of this test, never the one of the user.
	export XGHOST_MACHINE_FACTS="$BATS_TEST_TMPDIR/machine.conf"
}

# Point the theme commands at inputs this test writes.
use_own_inputs() {
	export XGHOST_THEMES_DIR="$BATS_TEST_TMPDIR/themes"
	export XGHOST_TEMPLATE_DIR="$BATS_TEST_TMPDIR/templates"
	mkdir -p "$XGHOST_THEMES_DIR" "$XGHOST_TEMPLATE_DIR"
}

make_theme() {
	mkdir -p "$XGHOST_THEMES_DIR/$1"
	cat >"$XGHOST_THEMES_DIR/$1/palette.conf"
}

make_template() {
	local relative=$1
	local dir=$XGHOST_TEMPLATE_DIR
	if [[ $relative == */* ]]; then
		dir=$XGHOST_TEMPLATE_DIR/${relative%/*}
	fi
	mkdir -p "$dir"
	cat >"$XGHOST_TEMPLATE_DIR/$relative"
}

# Write the machine facts file from standard input.
make_facts() {
	cat >"$XGHOST_MACHINE_FACTS"
}

# A machine facts file that declares the version and one fact.
plain_facts() {
	cat <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_MONITOR_1_NAME=DP-9
		MACHINE_TIMEZONE=Etc/UTC
	EOF
}

# Read the machine facts file and print the outcome: every problem, and then
# every value this test asks about.
#
#   load KEY...
load() {
	local script="$BATS_TEST_TMPDIR/load.sh"
	cat >"$script" <<-'EOF'
		set -uo pipefail
		. "$1/lib/facts.sh"
		file=$2
		shift 2
		if ! facts_load "$file"; then
			printf 'problem: %s\n' "${FACTS_ERRORS[@]}"
			exit 1
		fi
		for key in "$@"; do
			printf '%s=%s\n' "$key" "${FACTS_SCALARS[$key]-<absent>}"
		done
	EOF
	run bash "$script" "$ROOT_DIR" "$XGHOST_MACHINE_FACTS" "$@"
}

# Run one snippet against lib/facts.sh, with the checkout as $1 and a scratch
# directory of this test as $2.
run_snippet() {
	local script="$BATS_TEST_TMPDIR/snippet.sh"
	cat >"$script"
	run bash "$script" "$ROOT_DIR" "$BATS_TEST_TMPDIR"
}

# --- the format the reader accepts ------------------------------------------

@test "facts reads a key and its value" {
	plain_facts | make_facts
	load MACHINE_MONITOR_1_NAME MACHINE_TIMEZONE
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_MONITOR_1_NAME=DP-9
MACHINE_TIMEZONE=Etc/UTC" ]
}

@test "facts accepts a comment, an empty line and white space around a pair" {
	make_facts <<-'EOF'
		# The machine facts of a test.

		MACHINE_FACTS_VERSION=1
		   MACHINE_TIMEZONE   =   Etc/UTC
	EOF
	load MACHINE_TIMEZONE
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_TIMEZONE=Etc/UTC" ]
}

@test "facts drops one pair of quotation marks around a value" {
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_MONITOR_1_DESCRIPTION="Acme Display 1234"
	EOF
	load MACHINE_MONITOR_1_DESCRIPTION
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_MONITOR_1_DESCRIPTION=Acme Display 1234" ]
}

@test "facts keeps a value that holds an equals sign" {
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_KEYBOARD_OPTIONS=ctrl:nocaps,terminate:ctrl_alt_bksp
		MACHINE_MONITOR_1_MODE=1920x1080@60
	EOF
	load MACHINE_KEYBOARD_OPTIONS MACHINE_MONITOR_1_MODE
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_KEYBOARD_OPTIONS=ctrl:nocaps,terminate:ctrl_alt_bksp
MACHINE_MONITOR_1_MODE=1920x1080@60" ]
}

# The file is a data file. The reader never sources it, so a fact can never
# run code, however it was written or edited.
@test "facts never runs the text of the file" {
	local evidence="$BATS_TEST_TMPDIR/evidence"
	make_facts <<-EOF
		MACHINE_FACTS_VERSION=1
		MACHINE_BROWSER=\$(touch "$evidence")
	EOF
	load MACHINE_BROWSER
	[ "$status" -eq 0 ]
	[ ! -e "$evidence" ]
	[ "$output" = "MACHINE_BROWSER=\$(touch \"$evidence\")" ]
}

# --- what the reader refuses ------------------------------------------------

@test "facts reports a key that does not start with the machine prefix" {
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		BG=#111111
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 2: 'BG' is not a machine fact"* ]]
}

@test "facts reports a key that is not upper case" {
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		machine_timezone=Etc/UTC
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"'machine_timezone' is not a machine fact"* ]]
}

@test "facts reports a key that is given more than once" {
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_TIMEZONE=Etc/UTC
		MACHINE_TIMEZONE=US/Pacific
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 3: 'MACHINE_TIMEZONE' is given more than once"* ]]
}

@test "facts reports a key with no value, and names the two defined words" {
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_TIMEZONE=
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"'MACHINE_TIMEZONE' has no value"* ]]
	[[ $output == *"'none'"* ]]
	[[ $output == *"'unknown'"* ]]
}

@test "facts reports a line that is not a pair, with its line number" {
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		this is not a pair
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 2: expected 'KEY=value'"* ]]
}

@test "facts reports every problem of one file, not only the first" {
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		BG=#111111
		MACHINE_TIMEZONE=
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"'BG' is not a machine fact"* ]]
	[[ $output == *"'MACHINE_TIMEZONE' has no value"* ]]
}

@test "facts reports a file that declares no version" {
	make_facts <<-'EOF'
		MACHINE_TIMEZONE=Etc/UTC
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"declares no 'MACHINE_FACTS_VERSION'"* ]]
	[[ $output == *"xghost machine detect"* ]]
}

@test "facts reports a version it does not read" {
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=2
		MACHINE_TIMEZONE=Etc/UTC
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"reads version 1"* ]]
}

@test "facts reports a file that is not there" {
	load
	[ "$status" -eq 1 ]
	[[ $output == *"does not exist"* ]]
}

# A user is invited to edit this file, so a path that is not a file it can read
# is named for what it is. "It does not exist", sent to somebody whose link
# points at nothing, sends them looking for the wrong thing.
@test "facts names a path that is a directory" {
	mkdir "$XGHOST_MACHINE_FACTS"
	load
	[ "$status" -eq 1 ]
	[[ $output == *"is a directory, and it has to be a file"* ]]
	[[ $output != *"does not exist"* ]]
}

@test "facts names a path that is a link to nothing" {
	ln -s "$BATS_TEST_TMPDIR/nowhere" "$XGHOST_MACHINE_FACTS"
	load
	[ "$status" -eq 1 ]
	[[ $output == *"symbolic link that points at nothing"* ]]
	[[ $output != *"does not exist"* ]]
}

# The writer replaces every control character of a value it detects. The file
# is a hand-edit surface as well, so the same rule holds for a value a user
# wrote: a tab inside a value would otherwise pass through into a rendered
# configuration file. The line is named rather than mended, because mending it
# in silence would change what the user wrote without telling them.
@test "facts reports a value that holds a control character" {
	printf 'MACHINE_FACTS_VERSION=1\nMACHINE_MONITOR_1_NAME=DP\t2\n' \
		>"$XGHOST_MACHINE_FACTS"
	load
	[ "$status" -eq 1 ]
	[[ $output == *"the value of 'MACHINE_MONITOR_1_NAME' holds a control character"* ]]
}

# --- the two text functions the writer uses ---------------------------------

@test "facts replaces every control character of a value with a space" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/facts.sh"
		facts_clean_value "$(printf 'one\ttwo\nthree')"
		printf '[%s] %s\n' "$FACTS_CLEANED" "$FACTS_CLEAN_CHANGED"
		facts_clean_value 'plain value'
		printf '[%s] %s\n' "$FACTS_CLEANED" "$FACTS_CLEAN_CHANGED"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "[one two three] yes
[plain value] no" ]
}

@test "facts refuses a value that is nothing but control characters" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/facts.sh"
		if facts_clean_value "$(printf '\t\t')"; then
			printf 'accepted\n'
		else
			printf 'refused\n'
		fi
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = refused ]
}

# The writer and the reader have to agree, so a value the writer quotes must
# read back as the value it was given.
@test "facts writes a value the reader reads back unchanged" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/facts.sh"
		file=$2/round-trip.conf
		for value in 'plain' ' leading' 'trailing ' '"quoted"' "'quoted'" 'a "b" c' '#hash'; do
			{
				printf 'MACHINE_FACTS_VERSION=1\n'
				printf 'MACHINE_PROBE='
				facts_quote_value "$value"
				printf '\n'
			} >"$file"
			if facts_load "$file"; then
				printf '[%s]\n' "${FACTS_SCALARS[MACHINE_PROBE]}"
			else
				printf 'problem: %s\n' "${FACTS_ERRORS[@]}"
			fi
		done
		rm -f "$file"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "[plain]
[ leading]
[trailing ]
[\"quoted\"]
['quoted']
[a \"b\" c]
[#hash]" ]
}

# --- the path of the file ---------------------------------------------------

@test "the machine facts live in the config directory of the user" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/facts.sh"
		unset XGHOST_MACHINE_FACTS XGHOST_CONFIG_HOME XDG_CONFIG_HOME
		HOME=/home/ada
		facts_path
		XDG_CONFIG_HOME=/elsewhere/config
		facts_path
		XGHOST_CONFIG_HOME=/override/config
		facts_path
		XGHOST_MACHINE_FACTS=/exact/machine.conf
		facts_path
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "/home/ada/.config/xghost/machine.conf
/elsewhere/config/xghost/machine.conf
/override/config/xghost/machine.conf
/exact/machine.conf" ]
}

@test "the machine facts live outside the checkout" {
	run bash -c '
		set -uo pipefail
		. "$1/lib/facts.sh"
		unset XGHOST_MACHINE_FACTS XGHOST_CONFIG_HOME XDG_CONFIG_HOME
		facts_path
	' _ "$ROOT_DIR"
	[ "$status" -eq 0 ]
	[[ $output != "$ROOT_DIR"/* ]]
}

@test "facts_path reports a machine with no config directory" {
	run env -i bash -c '
		set -uo pipefail
		. "$1/lib/facts.sh"
		if facts_path; then printf "found\n"; else printf "%s\n" "$FACTS_NO_HOME_MESSAGE"; fi
	' _ "$ROOT_DIR"
	[ "$status" -eq 0 ]
	[[ $output == *"HOME, XDG_CONFIG_HOME and XGHOST_CONFIG_HOME are all empty"* ]]
}

# --- the renderer reads the machine facts -----------------------------------

@test "a template names a machine fact and the renderer substitutes it" {
	use_own_inputs
	plain_facts | make_facts
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template hypr/monitors.conf <<-'EOF'
		monitor = @MACHINE_MONITOR_1_NAME@
		bg = @BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 0 ]
	run cat "$GENERATED/hypr/monitors.conf"
	[ "$output" = "monitor = DP-9
bg = #1a2b3c" ]
}

# The renderer is a pure function of its inputs, and the machine facts are one
# of them. A change to the file therefore changes the output.
@test "an edit to the machine facts reaches the output of the next render" {
	use_own_inputs
	plain_facts | make_facts
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template monitors.conf <<-'EOF'
		monitor = @MACHINE_MONITOR_1_NAME@
	EOF
	"$XGHOST" theme set demo

	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_MONITOR_1_NAME=HDMI-A-1
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/monitors.conf"
	[ "$output" = "monitor = HDMI-A-1" ]
}

# A machine that has not run detection has no such file. That is not a failure
# of the render by itself: it fails only when a template needs a fact, and it
# then names the fact rather than writing a monitor the renderer guessed at.
@test "a render with no machine facts file still renders a template that needs none" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template plain.conf <<-'EOF'
		bg = @BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 0 ]
	run cat "$GENERATED/plain.conf"
	[ "$output" = "bg = #1a2b3c" ]
}

@test "a template that needs a machine fact fails by name when there is no file" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template monitors.conf <<-'EOF'
		monitor = @MACHINE_MONITOR_1_NAME@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"no value for 'MACHINE_MONITOR_1_NAME' in the theme palette, the machine facts or the knobs"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

# A directory, and a link that points at nothing, are both a broken file rather
# than an absent one. Passing over them would report a missing value and send
# the user looking for the wrong thing.
@test "a machine facts path that is a directory fails the render and names it" {
	use_own_inputs
	mkdir "$XGHOST_MACHINE_FACTS"
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template plain.conf <<-'EOF'
		bg = @BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"machine facts: the machine facts path is a directory"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

@test "a machine facts path that is a link to nothing fails the render and names it" {
	use_own_inputs
	ln -s "$BATS_TEST_TMPDIR/nowhere" "$XGHOST_MACHINE_FACTS"
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template plain.conf <<-'EOF'
		bg = @BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"machine facts: the machine facts path is a symbolic link that points at nothing"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

@test "a machine facts file with a problem fails the render and names the problem" {
	use_own_inputs
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_TIMEZONE=
	EOF
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template plain.conf <<-'EOF'
		bg = @BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"machine facts: line 2: 'MACHINE_TIMEZONE' has no value"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

# The palette and the machine facts are two files with two owners. A name both
# declare is a mistake in one of them, and preferring either one quietly would
# make the output depend on a rule nobody wrote down.
@test "a name the palette and the machine facts both declare is reported" {
	use_own_inputs
	make_facts <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_TIMEZONE=Etc/UTC
	EOF
	make_theme demo <<-'EOF'
		BG=#1a2b3c
		MACHINE_TIMEZONE=Europe/Paris
	EOF
	make_template plain.conf <<-'EOF'
		bg = @BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"'MACHINE_TIMEZONE' is declared by the theme palette as well"* ]]
}

# The knobs are the third input of the renderer, beside the palette and these
# facts. tests/knobs.bats covers them; this asserts the shape of the interface,
# which is the promise this file made while the knobs did not exist yet.
@test "the renderer takes the knobs as its third input" {
	run bash -c '
		set -uo pipefail
		. "$1/lib/palette.sh"
		. "$1/lib/facts.sh"
		. "$1/lib/knobs.sh"
		. "$1/lib/renderer.sh"
		render_tree "$1/templates" "$1/themes/tokyonight" "$3" \
			"$1/schema/knobs.conf" "" "$2/out" || true
		printf "%s\n" ${RENDER_ERRORS[@]+"${RENDER_ERRORS[@]}"}
		grep -Fx "    gaps_in = 10" "$2/out/hypr/knobs.conf"
	' _ "$ROOT_DIR" "$BATS_TEST_TMPDIR" "$BATS_TEST_DIRNAME/fixtures/machine/golden.conf"
	[ "$status" -eq 0 ]
	[[ $output != *"knobs are not an input"* ]]
}
