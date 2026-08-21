#!/usr/bin/env bats
#
# Tests for lib/knobs.sh, the two knob file formats, the renderer that reads
# them as its third input, and the two 'settings' commands.
#
# The readers are pure, so they are tested directly. Everything else is tested
# through the real command, which is what every other suite of this project
# does: a test asserts what lands on disk, what is printed, and which exit
# status comes back.
#
# The knobs are documented in docs/knobs.md.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	SHIPPED_SCHEMA="$ROOT_DIR/schema/knobs.conf"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# Every path the commands read comes from this setup, so no override that
	# the person who runs the tests happens to export reaches a command.
	unset XGHOST_ROOT
	unset XGHOST_THEMES_DIR
	unset XGHOST_TEMPLATE_DIR
	unset XGHOST_CONFIG_SOURCE
	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR
	unset XGHOST_KNOBS_SCHEMA

	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	# The shipped templates make a structural choice from a machine fact, so a
	# render of them needs facts whatever the test is about.
	use_fixed_machine_facts

	# The knobs file of this test. It does not exist yet, which is the state of
	# a machine that has never run 'xghost settings set'.
	export XGHOST_KNOBS_FILE="$BATS_TEST_TMPDIR/knobs.conf"

	# The schema this suite reads. It starts as a copy of the schema the project
	# ships, and a test that needs another one rewrites the copy with
	# use_own_schema.
	#
	# The path is exported here and nowhere else, so no helper of this file
	# exports anything. A helper that did would lose the export the moment it
	# was called on the right of a pipe, because that side runs in a subshell:
	# the file would be written, the export would not survive, and every test of
	# it would quietly read the shipped schema instead and prove nothing.
	SCHEMA="$BATS_TEST_TMPDIR/schema.conf"
	cp "$SHIPPED_SCHEMA" "$SCHEMA"
	export XGHOST_KNOBS_SCHEMA="$SCHEMA"

	GENERATED="$XDG_STATE_HOME/xghost/generated"
}

# Point the theme commands at inputs this test writes.
use_own_inputs() {
	export XGHOST_THEMES_DIR="$BATS_TEST_TMPDIR/themes"
	export XGHOST_TEMPLATE_DIR="$BATS_TEST_TMPDIR/templates"
	mkdir -p "$XGHOST_THEMES_DIR" "$XGHOST_TEMPLATE_DIR"
}

# Rewrite the schema this suite reads, from standard input.
#
# It writes a file and changes nothing else, so it is safe on either side of a
# pipe. setup() is what points xghost at that file.
use_own_schema() {
	cat >"$SCHEMA"
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

# Write one fragment of a structural choice from standard input.
#
#   make_fragment DIRECTORY NAME
make_fragment() {
	mkdir -p "$XGHOST_TEMPLATE_DIR/$1"
	cat >"$XGHOST_TEMPLATE_DIR/$1/$2"
}

# Write the knobs file of this test from standard input.
make_knobs() {
	cat >"$XGHOST_KNOBS_FILE"
}

# A schema with one knob of each kind: two values, and a value that holds a
# space.
plain_schema() {
	cat <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape of a window corner.
		value=round
		value=square
		default=round

		knob=KNOB_LABEL
		summary=The label the desktop draws.
		value=Plain Label
		value=Other Label
		default=Plain Label
	EOF
}

# Read the schema and the knobs file, and print the outcome: every problem, and
# then the effective value of every knob this test asks about.
#
#   load KEY...
load() {
	local script="$BATS_TEST_TMPDIR/load.sh"
	cat >"$script" <<-'EOF'
		set -uo pipefail
		. "$1/lib/knobs.sh"
		schema=$2
		file=$3
		shift 3
		if ! knobs_load "$schema" "$file"; then
			printf 'problem: %s\n' "${KNOBS_ERRORS[@]}"
			exit 1
		fi
		for key in "$@"; do
			printf '%s=%s\n' "$key" "${KNOBS_SCALARS[$key]-<absent>}"
		done
	EOF
	# The schema is the one setup() pointed xghost at, so this reader and the
	# commands always read the same file. There is no fallback: a fallback is
	# what turned a lost export into a green test.
	local file=$XGHOST_KNOBS_FILE
	[ -e "$file" ] || file=
	run bash "$script" "$ROOT_DIR" "$XGHOST_KNOBS_SCHEMA" "$file" "$@"
}

# Run one snippet against lib/knobs.sh, with the checkout as $1 and a scratch
# directory of this test as $2.
run_snippet() {
	local script="$BATS_TEST_TMPDIR/snippet.sh"
	cat >"$script"
	run bash "$script" "$ROOT_DIR" "$BATS_TEST_TMPDIR"
}

# --- the schema the project owns ---------------------------------------------

@test "the schema reads a knob, its values and its default" {
	plain_schema | use_own_schema
	load KNOB_SHAPE KNOB_LABEL
	[ "$status" -eq 0 ]
	[ "$output" = "KNOB_SHAPE=round
KNOB_LABEL=Plain Label" ]
}

@test "the shipped schema declares the four knobs of this desktop" {
	load KNOB_ANIMATIONS KNOB_GAP_SIZE KNOB_FONT KNOB_BAR_POSITION
	[ "$status" -eq 0 ]
	[ "$output" = "KNOB_ANIMATIONS=on
KNOB_GAP_SIZE=10
KNOB_FONT=JetBrainsMono Nerd Font
KNOB_BAR_POSITION=top" ]
}

# Every other test of this file points xghost at a copy of the schema, so this
# is the one that proves where xghost finds the schema when nothing points at
# it: in the checkout, beside the templates.
@test "xghost reads the schema of the checkout when nothing overrides it" {
	unset XGHOST_KNOBS_SCHEMA
	run "$XGHOST" settings list
	[ "$status" -eq 0 ]
	[[ $output == *"KNOB_ANIMATIONS = on"* ]]
	[[ $output == *"KNOB_GAP_SIZE = 10"* ]]
	[[ $output == *"KNOB_FONT = JetBrainsMono Nerd Font"* ]]
	[[ $output == *"KNOB_BAR_POSITION = top"* ]]
}

@test "the schema reports a field that belongs to no knob" {
	use_own_schema <<-'EOF'
		summary=A summary with no knob above it.
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		default=round
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"the schema, line 1: 'summary' belongs to no knob"* ]]
}

@test "the schema reports a field it does not have" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		default=round
		colour=blue
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 5: 'colour' is not a field of the schema"* ]]
	[[ $output == *"'knob', 'summary', 'value' and 'default'"* ]]
}

@test "the schema reports a knob name without the knob prefix" {
	use_own_schema <<-'EOF'
		knob=SHAPE
		summary=The shape.
		value=round
		default=round
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 1: 'SHAPE' is not a knob name"* ]]
	[[ $output == *"starts with 'KNOB_'"* ]]
}

# A knob and a machine fact can never carry the same name, because one starts
# with 'KNOB_' and the other with 'MACHINE_'. This is what makes that true.
@test "the schema reports a knob that names a machine fact" {
	use_own_schema <<-'EOF'
		knob=MACHINE_TIMEZONE
		summary=Not a knob at all.
		value=Etc/UTC
		default=Etc/UTC
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"'MACHINE_TIMEZONE' is not a knob name"* ]]
}

@test "the schema reports a knob declared more than once" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		default=round

		knob=KNOB_SHAPE
		summary=The shape again.
		value=square
		default=square
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 6: 'KNOB_SHAPE' is declared more than once"* ]]
}

@test "the schema reports a repeated summary, value and default" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		summary=The shape once more.
		value=round
		value=round
		default=round
		default=round
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 3: 'KNOB_SHAPE' declares more than one 'summary'"* ]]
	[[ $output == *"line 5: 'KNOB_SHAPE' declares the value 'round' more than once"* ]]
	[[ $output == *"line 7: 'KNOB_SHAPE' declares more than one 'default'"* ]]
}

# A default that names nothing would leave every machine with no knobs file
# holding a value that the same project refuses inside that file.
@test "the schema reports a default that is not one of the values" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		value=square
		default=oval
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"'KNOB_SHAPE' defaults to 'oval', which is not one of its values"* ]]
	[[ $output == *"'round', 'square'"* ]]
}

@test "the schema reports a record with no summary, no value or no default" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		value=round
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"'KNOB_SHAPE' declares no 'summary'"* ]]
	[[ $output == *"'KNOB_SHAPE' declares no 'default'"* ]]
}

@test "the schema reports a knob that declares no value" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		default=round
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"'KNOB_SHAPE' declares no 'value'"* ]]
}

@test "the schema reports a file that declares no knob" {
	use_own_schema <<-'EOF'
		# A schema with a comment and nothing else.
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"the schema declares no knob"* ]]
}

@test "the schema reports a file that is not there" {
	export XGHOST_KNOBS_SCHEMA="$BATS_TEST_TMPDIR/nowhere.conf"
	load
	[ "$status" -eq 1 ]
	[[ $output == *"the knob schema does not exist"* ]]
}

# A value makes a round trip: 'xghost settings set' writes it into the knobs
# file and the reader reads it back. A value that would lose text to the rules
# of that reader could never make that trip, so the schema refuses it.
@test "the schema reports a value that cannot survive being written and read" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=" round "
		value="'square'"
		default=round
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 3: the value of 'value' starts or ends with a space"* ]]
	[[ $output == *"line 4: the value of 'value' is wrapped in quotation marks"* ]]
}

@test "the schema reports every problem of one file, not only the first" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		default=oval
		colour=blue
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"'colour' is not a field of the schema"* ]]
	[[ $output == *"defaults to 'oval'"* ]]
}

# The schema is a data file. The reader never sources it, so it can never run
# code, whatever a checkout holds.
@test "the schema is never run" {
	local evidence="$BATS_TEST_TMPDIR/evidence"
	use_own_schema <<-EOF
		knob=KNOB_SHAPE
		summary=The shape.
		value=\$(touch "$evidence")
		default=\$(touch "$evidence")
	EOF
	load KNOB_SHAPE
	[ "$status" -eq 0 ]
	[ ! -e "$evidence" ]
	[ "$output" = "KNOB_SHAPE=\$(touch \"$evidence\")" ]
}

# --- the knobs file the user owns --------------------------------------------

# An absent file is the state of a machine that has never changed a preference,
# and it is not a problem: every knob then holds the default of the schema.
@test "an absent knobs file gives every knob its default" {
	plain_schema | use_own_schema
	[ ! -e "$XGHOST_KNOBS_FILE" ]
	load KNOB_SHAPE KNOB_LABEL
	[ "$status" -eq 0 ]
	[ "$output" = "KNOB_SHAPE=round
KNOB_LABEL=Plain Label" ]
}

@test "a knob the file declares wins over the default of the schema" {
	plain_schema | use_own_schema
	make_knobs <<-'EOF'
		KNOB_SHAPE=square
	EOF
	load KNOB_SHAPE KNOB_LABEL
	[ "$status" -eq 0 ]
	[ "$output" = "KNOB_SHAPE=square
KNOB_LABEL=Plain Label" ]
}

@test "the knobs file accepts a comment, an empty line and white space" {
	plain_schema | use_own_schema
	make_knobs <<-'EOF'
		# The preferences of a test.

		   KNOB_SHAPE   =   square
	EOF
	load KNOB_SHAPE
	[ "$status" -eq 0 ]
	[ "$output" = "KNOB_SHAPE=square" ]
}

@test "the knobs file keeps a value that holds a space" {
	plain_schema | use_own_schema
	make_knobs <<-'EOF'
		KNOB_LABEL=Other Label
	EOF
	load KNOB_LABEL
	[ "$status" -eq 0 ]
	[ "$output" = "KNOB_LABEL=Other Label" ]
}

@test "the knobs file reports a value the schema does not name" {
	plain_schema | use_own_schema
	make_knobs <<-'EOF'
		KNOB_SHAPE=oval
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 1: 'oval' is not a value of 'KNOB_SHAPE'"* ]]
	[[ $output == *"'round', 'square'"* ]]
}

@test "the knobs file reports a knob this version of xghost does not have" {
	plain_schema | use_own_schema
	make_knobs <<-'EOF'
		KNOB_DROPPED=round
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 1: 'KNOB_DROPPED' is not a knob this version of xghost has"* ]]
	[[ $output == *"xghost settings list"* ]]
}

@test "the knobs file reports a key that is not a knob at all" {
	plain_schema | use_own_schema
	make_knobs <<-'EOF'
		BG=#111111
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 1: 'BG' is not a knob"* ]]
}

@test "the knobs file reports a knob given more than once" {
	plain_schema | use_own_schema
	make_knobs <<-'EOF'
		KNOB_SHAPE=round
		KNOB_SHAPE=square
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 2: 'KNOB_SHAPE' is given more than once"* ]]
}

@test "the knobs file reports a line that is not a pair" {
	plain_schema | use_own_schema
	make_knobs <<-'EOF'
		this is not a pair
	EOF
	load
	[ "$status" -eq 1 ]
	[[ $output == *"line 1: expected 'KNOB_NAME=value'"* ]]
}

# 'read' drops a NUL byte without a word, so 'of<NUL>f' would reach the schema
# as 'off' and be accepted: the file on disk and the value the desktop runs
# would differ, and nothing would say so. The renderer refuses a template that
# holds one for the same reason.
@test "the knobs file reports a NUL byte rather than dropping it" {
	plain_schema | use_own_schema
	printf 'KNOB_SHAPE=squ\000are\n' >"$XGHOST_KNOBS_FILE"
	load KNOB_SHAPE
	[ "$status" -eq 1 ]
	[[ $output == *"holds a NUL byte"* ]]
	[[ $output != *"KNOB_SHAPE=square"* ]]
}

# A line of a knobs file may be as long as the file. The report names enough of
# it to recognise and never empties a screen for one line.
@test "an error message carries the start of a very long line and no more" {
	plain_schema | use_own_schema
	local junk
	junk=$(printf 'J%.0s' $(seq 1 2000))
	printf '%s\n' "$junk" >"$XGHOST_KNOBS_FILE"
	load
	[ "$status" -eq 1 ]
	[[ $output == *"expected 'KNOB_NAME=value'"* ]]
	[[ $output == *"... (2000 characters in all)"* ]]
	[ "${#output}" -lt 400 ]
}

@test "the knobs file is never run" {
	local evidence="$BATS_TEST_TMPDIR/evidence"
	use_own_schema <<-EOF
		knob=KNOB_SHAPE
		summary=The shape.
		value=\$(touch "$evidence")
		default=\$(touch "$evidence")
	EOF
	make_knobs <<-EOF
		KNOB_SHAPE=\$(touch "$evidence")
	EOF
	load KNOB_SHAPE
	[ "$status" -eq 0 ]
	[ ! -e "$evidence" ]
}

# --- where the file lives ----------------------------------------------------

# The file belongs to the user, so it lives in the config directory and never in
# the checkout. That is what makes it survive an update: an update replaces the
# checkout and never writes to the config directory.
@test "the knobs live in the config directory of the user" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/knobs.sh"
		unset XGHOST_KNOBS_FILE XGHOST_CONFIG_HOME XDG_CONFIG_HOME
		HOME=/home/ada
		knobs_path
		XDG_CONFIG_HOME=/elsewhere/config
		knobs_path
		XGHOST_CONFIG_HOME=/xghost/config
		knobs_path
		XGHOST_KNOBS_FILE=/exact/knobs.conf
		knobs_path
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "/home/ada/.config/xghost/knobs.conf
/elsewhere/config/xghost/knobs.conf
/xghost/config/xghost/knobs.conf
/exact/knobs.conf" ]
}

# 'settings set' writes to the config directory and nowhere else. The schema of
# the project is read and never written, so an update that replaces the checkout
# carries no preference of the user away with it.
@test "settings set writes the config directory and never the checkout" {
	unset XGHOST_KNOBS_FILE
	local before after
	before=$(find "$ROOT_DIR/schema" "$ROOT_DIR/templates" -type f -printf '%p %T@\n' | sort)

	"$XGHOST" settings set KNOB_GAP_SIZE 20 >/dev/null
	[ -f "$XDG_CONFIG_HOME/xghost/knobs.conf" ]
	[[ $XDG_CONFIG_HOME != "$ROOT_DIR"/* ]]

	after=$(find "$ROOT_DIR/schema" "$ROOT_DIR/templates" -type f -printf '%p %T@\n' | sort)
	[ "$before" = "$after" ]
}

# --- the renderer reads the knobs --------------------------------------------

@test "a scalar knob substitutes into a template" {
	use_own_inputs
	plain_schema | use_own_schema
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template plain.conf <<-'EOF'
		shape = @KNOB_SHAPE@
		label = @KNOB_LABEL@
	EOF

	"$XGHOST" theme set demo >/dev/null
	run cat "$GENERATED/plain.conf"
	[ "$output" = "shape = round
label = Plain Label" ]

	"$XGHOST" settings set KNOB_SHAPE square >/dev/null
	run cat "$GENERATED/plain.conf"
	[ "$output" = "shape = square
label = Plain Label" ]
}

# A knob drives a structural choice exactly as a machine fact does. The
# mechanism is the one of issue #10, and no second mechanism was written for
# the knobs.
@test "a structural knob selects a prescribed fragment" {
	use_own_inputs
	plain_schema | use_own_schema
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_fragment corners.conf.choice.KNOB_SHAPE round <<-'EOF'
		rounding = 6
	EOF
	make_fragment corners.conf.choice.KNOB_SHAPE square <<-'EOF'
		rounding = 0
	EOF

	"$XGHOST" theme set demo >/dev/null
	run cat "$GENERATED/corners.conf"
	[ "$output" = "rounding = 6" ]
	[ ! -e "$GENERATED/corners.conf.choice.KNOB_SHAPE" ]

	"$XGHOST" settings set KNOB_SHAPE square >/dev/null
	run cat "$GENERATED/corners.conf"
	[ "$output" = "rounding = 0" ]
}

# The value is never used to build a path. The fragment is looked up among the
# files the renderer already found, so a value can reach nothing outside the
# choice directory. The schema is the second lock on the same door.
@test "a knob value never names a file outside the choice" {
	use_own_inputs
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		value=../../escape
		default=round
	EOF
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_fragment corners.conf.choice.KNOB_SHAPE round <<-'EOF'
		rounding = 6
	EOF
	make_knobs <<-'EOF'
		KNOB_SHAPE=../../escape
	EOF

	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"corners.conf.choice.KNOB_SHAPE: 'KNOB_SHAPE' is '../../escape'"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
	[ ! -e "$BATS_TEST_TMPDIR/escape" ]
}

# The palette and the knobs are two files with two owners, exactly as the
# palette and the machine facts are. A name both declare is a mistake in one of
# them, and preferring either one quietly would make the output depend on a rule
# nobody wrote down.
@test "a name the palette and the knobs both declare is reported" {
	use_own_inputs
	plain_schema | use_own_schema
	make_theme demo <<-'EOF'
		BG=#1a2b3c
		KNOB_SHAPE=oval
	EOF
	make_template plain.conf <<-'EOF'
		bg = @BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"knobs: 'KNOB_SHAPE' is declared by the theme palette as well"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

@test "a knobs file with a problem fails the render and names the problem" {
	use_own_inputs
	plain_schema | use_own_schema
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template plain.conf <<-'EOF'
		bg = @BG@
	EOF
	make_knobs <<-'EOF'
		KNOB_SHAPE=oval
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"knobs: line 1: 'oval' is not a value of 'KNOB_SHAPE'"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

@test "a broken knob schema fails the render and names the schema" {
	use_own_inputs
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		default=oval
	EOF
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template plain.conf <<-'EOF'
		bg = @BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"knobs: the schema: 'KNOB_SHAPE' defaults to 'oval'"* ]]
}

# --- settings list -----------------------------------------------------------

@test "settings list names every knob, its value and the values it takes" {
	run "$XGHOST" settings list
	[ "$status" -eq 0 ]
	[[ $output == *"KNOB_ANIMATIONS = on"* ]]
	[[ $output == *"allowed: 'on', 'off'"* ]]
	[[ $output == *"KNOB_GAP_SIZE = 10"* ]]
	[[ $output == *"allowed: '0', '5', '10', '15', '20'"* ]]
	[[ $output == *"KNOB_FONT = JetBrainsMono Nerd Font"* ]]
	[[ $output == *"allowed: 'JetBrainsMono Nerd Font', 'CaskaydiaCove Nerd Font'"* ]]
	[[ $output == *"default: 'JetBrainsMono Nerd Font'"* ]]
	[[ $output == *"KNOB_BAR_POSITION = top"* ]]
	[[ $output == *"allowed: 'top', 'bottom'"* ]]
	[[ $output == *"the knobs are at $XGHOST_KNOBS_FILE"* ]]
}

@test "settings list names every knob of the schema" {
	local knob count=0
	run "$XGHOST" settings list
	[ "$status" -eq 0 ]
	while IFS= read -r knob; do
		[[ $output == *"$knob = "* ]]
		count=$((count + 1))
	done < <(sed -n 's/^knob=//p' "$SHIPPED_SCHEMA")
	[ "$count" -gt 0 ]
}

@test "settings list reports the value that was set" {
	"$XGHOST" settings set KNOB_ANIMATIONS off >/dev/null
	run "$XGHOST" settings list
	[ "$status" -eq 0 ]
	[[ $output == *"KNOB_ANIMATIONS = off"* ]]
	# The default is still reported as the default, so a reader can tell one
	# from the other.
	[[ $output == *"default: 'on'"* ]]
}

@test "settings list reports a knobs file it cannot read, and lists nothing" {
	make_knobs <<-'EOF'
		KNOB_GAP_SIZE=7
	EOF
	run "$XGHOST" settings list
	[ "$status" -eq 1 ]
	[[ $output == *"knobs: line 1: '7' is not a value of 'KNOB_GAP_SIZE'"* ]]
	[[ $output != *"KNOB_ANIMATIONS = "* ]]
}

# The schema is a file of the project and the knobs file is a file of the user.
# A schema defect that told the user to correct their own file would name a file
# that has nothing wrong with it, and that a machine which has never run
# 'settings set' does not even have.
@test "settings list names the schema when the schema is what failed" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		default=oval
	EOF
	[ ! -e "$XGHOST_KNOBS_FILE" ]
	run "$XGHOST" settings list
	[ "$status" -eq 1 ]
	[[ $output == *"the knob schema has a problem: $XGHOST_KNOBS_SCHEMA"* ]]
	[[ $output == *"defect of xghost rather than of your machine"* ]]
	[[ $output != *"Correct that file"* ]]
	[[ $output != *"the knobs at $XGHOST_KNOBS_FILE"* ]]
}

@test "settings list names the knobs file when the knobs file is what failed" {
	make_knobs <<-'EOF'
		KNOB_GAP_SIZE=7
	EOF
	run "$XGHOST" settings list
	[ "$status" -eq 1 ]
	[[ $output == *"the knobs at $XGHOST_KNOBS_FILE cannot be read"* ]]
	[[ $output != *"defect of xghost"* ]]
}

@test "settings list takes no argument" {
	run "$XGHOST" settings list extra
	[ "$status" -eq 2 ]
	[[ $output == *"takes no argument"* ]]
}

# --- settings set ------------------------------------------------------------

@test "settings set writes the value into the knobs file" {
	run "$XGHOST" settings set KNOB_GAP_SIZE 20
	[ "$status" -eq 0 ]
	[[ $output == *"KNOB_GAP_SIZE is now '20'"* ]]
	run grep -Fx 'KNOB_GAP_SIZE=20' "$XGHOST_KNOBS_FILE"
	[ "$status" -eq 0 ]
}

@test "settings set creates the knobs file with a header that says who owns it" {
	[ ! -e "$XGHOST_KNOBS_FILE" ]
	"$XGHOST" settings set KNOB_GAP_SIZE 20 >/dev/null
	run head -1 "$XGHOST_KNOBS_FILE"
	[ "$output" = "# The knobs of xghost: the preferences this desktop supports." ]
	run grep -F 'survives every update' "$XGHOST_KNOBS_FILE"
	[ "$status" -eq 0 ]
	[ "$(stat -c '%a' "$XGHOST_KNOBS_FILE")" = 644 ]
}

# The file is human-edited, so a write keeps every line the user wrote. A
# rewritten file would drop their comments and their order, which is the cost
# the machine facts pay and the knobs must not.
@test "settings set keeps the comments and the other knobs of the file" {
	make_knobs <<-'EOF'
		# My preferences. I like this one small.
		KNOB_GAP_SIZE=5

		# And the animations off.
		KNOB_ANIMATIONS=off
	EOF
	"$XGHOST" settings set KNOB_GAP_SIZE 20 >/dev/null
	run cat "$XGHOST_KNOBS_FILE"
	[ "$output" = "# My preferences. I like this one small.
KNOB_GAP_SIZE=20

# And the animations off.
KNOB_ANIMATIONS=off" ]
}

@test "settings set appends a knob the file does not yet name" {
	make_knobs <<-'EOF'
		KNOB_GAP_SIZE=5
	EOF
	"$XGHOST" settings set KNOB_ANIMATIONS off >/dev/null
	run cat "$XGHOST_KNOBS_FILE"
	[ "$output" = "KNOB_GAP_SIZE=5
KNOB_ANIMATIONS=off" ]
}

@test "settings set renders the configuration again" {
	"$XGHOST" theme set tokyonight >/dev/null
	run grep -Fx '    gaps_in = 10' "$GENERATED/hypr/knobs.conf"
	[ "$status" -eq 0 ]

	run "$XGHOST" settings set KNOB_GAP_SIZE 20
	[ "$status" -eq 0 ]
	[[ $output == *"the generated output is rebuilt at"* ]]
	run grep -Fx '    gaps_in = 20' "$GENERATED/hypr/knobs.conf"
	[ "$status" -eq 0 ]

	# The theme is untouched by a knob change.
	run "$XGHOST" theme current
	[ "$output" = "tokyonight" ]
}

# A knob change writes the new configuration and stops there. It restarts
# nothing and it signals nothing, so the command says so rather than implying a
# desktop that changes on its own. Reloading a running component is issue #24.
# The command used to end by saying that a running program keeps the
# configuration it started with. That is no longer true: issue #24 gave the
# render a reload, and lib/reload.sh owns it. What is asserted here is that the
# command reaches that step at all, and that the switch which turns it off
# reaches the command with it.
#
# tests/setup_suite.bash has the reload off for this suite, because nothing here
# stubs a signalling program and the machine this project is developed on runs
# every component the table names. tests/reload.bats is where the reload itself
# is proved, against stubs.
@test "settings set ends by reloading the running components" {
	"$XGHOST" theme set tokyonight >/dev/null
	run "$XGHOST" settings set KNOB_GAP_SIZE 20
	[ "$status" -eq 0 ]
	[[ $output == *"reload the running components"* ]]
}

@test "settings set reloads nothing when the reload is switched off, and says so" {
	"$XGHOST" theme set tokyonight >/dev/null
	run env XGHOST_RELOAD=no "$XGHOST" settings set KNOB_GAP_SIZE 20
	[ "$status" -eq 0 ]
	[[ $output == *"reload is off: XGHOST_RELOAD is 'no'"* ]]
	[[ $output != *"waybar: reloaded"* ]]
}

# The value is stored whether or not there is something to render into, and the
# command says which of the two happened.
@test "settings set stores the value when no theme is active" {
	run "$XGHOST" settings set KNOB_GAP_SIZE 20
	[ "$status" -eq 0 ]
	[[ $output == *"no theme is active, so nothing was rendered."* ]]
	run grep -Fx 'KNOB_GAP_SIZE=20' "$XGHOST_KNOBS_FILE"
	[ "$status" -eq 0 ]
}

@test "settings set refuses a value the schema does not name, and changes nothing" {
	"$XGHOST" theme set tokyonight >/dev/null
	run "$XGHOST" settings set KNOB_GAP_SIZE 7
	[ "$status" -eq 2 ]
	[[ $output == *"'7' is not a value of 'KNOB_GAP_SIZE'"* ]]
	[[ $output == *"It takes '0', '5', '10', '15', '20'."* ]]
	[[ $output == *"Nothing is changed."* ]]

	[ ! -e "$XGHOST_KNOBS_FILE" ]
	run grep -Fx '    gaps_in = 10' "$GENERATED/hypr/knobs.conf"
	[ "$status" -eq 0 ]
}

@test "settings set refuses a knob the schema does not name, and changes nothing" {
	run "$XGHOST" settings set KNOB_NOSUCH on
	[ "$status" -eq 2 ]
	[[ $output == *"'KNOB_NOSUCH' is not a knob"* ]]
	[[ $output == *"xghost settings list"* ]]
	[[ $output == *"Nothing is changed."* ]]
	[ ! -e "$XGHOST_KNOBS_FILE" ]
}

@test "settings set refuses a value that only differs in case" {
	run "$XGHOST" settings set KNOB_ANIMATIONS OFF
	[ "$status" -eq 2 ]
	[[ $output == *"'OFF' is not a value of 'KNOB_ANIMATIONS'"* ]]
	[ ! -e "$XGHOST_KNOBS_FILE" ]
}

# A name that is not a knob name is refused before it is looked up, so an empty
# argument is an answer rather than a raw diagnostic of the shell.
@test "settings set refuses a name that is not a knob name" {
	local name
	for name in '' 'a]b' 'KNOB_@' '*'; do
		run "$XGHOST" settings set "$name" on
		[ "$status" -eq 2 ]
		[[ $output == *"is not a knob"* ]]
		[[ $output != *"bad array subscript"* ]]
	done
	[ ! -e "$XGHOST_KNOBS_FILE" ]
}

# The value is only ever compared with the list the schema names, so a value
# that carries a second line cannot write one into the knobs file.
@test "settings set refuses a value that carries a newline" {
	run "$XGHOST" settings set KNOB_ANIMATIONS "$(printf 'on\nKNOB_GAP_SIZE=0')"
	[ "$status" -eq 2 ]
	[[ $output == *"is not a value of 'KNOB_ANIMATIONS'"* ]]
	[ ! -e "$XGHOST_KNOBS_FILE" ]
}

@test "settings set takes one knob and one value" {
	run "$XGHOST" settings set KNOB_GAP_SIZE
	[ "$status" -eq 2 ]
	[[ $output == *"takes one knob and one value"* ]]
	run "$XGHOST" settings set KNOB_GAP_SIZE 20 extra
	[ "$status" -eq 2 ]
	[[ $output == *"takes one knob and one value"* ]]
	[ ! -e "$XGHOST_KNOBS_FILE" ]
}

@test "settings set accepts a value that holds a space" {
	run "$XGHOST" settings set KNOB_FONT 'CaskaydiaCove Nerd Font'
	[ "$status" -eq 0 ]
	run grep -Fx 'KNOB_FONT=CaskaydiaCove Nerd Font' "$XGHOST_KNOBS_FILE"
	[ "$status" -eq 0 ]
	run "$XGHOST" settings list
	[[ $output == *"KNOB_FONT = CaskaydiaCove Nerd Font"* ]]
}

# One bad line must not cost a user the rest of their preferences, so the whole
# file is read before anything is written.
@test "settings set refuses to write a knobs file that has a problem" {
	make_knobs <<-'EOF'
		KNOB_GAP_SIZE=7
		KNOB_ANIMATIONS=off
	EOF
	run "$XGHOST" settings set KNOB_ANIMATIONS on
	[ "$status" -eq 1 ]
	[[ $output == *"knobs: line 1: '7' is not a value of 'KNOB_GAP_SIZE'"* ]]
	[[ $output == *"Nothing is changed."* ]]
	run grep -Fx 'KNOB_ANIMATIONS=off' "$XGHOST_KNOBS_FILE"
	[ "$status" -eq 0 ]
}

@test "settings set names the schema when the schema is what failed" {
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		default=oval
	EOF
	[ ! -e "$XGHOST_KNOBS_FILE" ]
	run "$XGHOST" settings set KNOB_SHAPE round
	[ "$status" -eq 1 ]
	[[ $output == *"the knob schema has a problem: $XGHOST_KNOBS_SCHEMA"* ]]
	[[ $output == *"defect of xghost rather than of your machine"* ]]
	[[ $output != *"Correct that file"* ]]
	[ ! -e "$XGHOST_KNOBS_FILE" ]
}

# --- the write itself --------------------------------------------------------
#
# These tests are about what the write does to the file of the user rather than
# about the value in it: the link they made, the mode they set, a write that
# runs out of room, a write two commands make at once, and an interrupt. Every
# one of them costs a user their preferences when it goes wrong, and none of
# them shows up in the value the command prints.

# Somebody who keeps their knobs in a dotfiles repository links the file into
# the config directory. The write goes through the link, and the link is still a
# link afterwards. A regular file in its place is a preference that the next
# 'stow' silently puts back, with nothing to say why the desktop changed.
@test "settings set writes through a symbolic link and keeps the link" {
	local repo="$BATS_TEST_TMPDIR/dotfiles"
	mkdir -p "$repo"
	cat >"$repo/knobs.conf" <<-'EOF'
		# My knobs, kept in a dotfiles repository.
		KNOB_GAP_SIZE=5
	EOF
	ln -s "$repo/knobs.conf" "$XGHOST_KNOBS_FILE"

	run "$XGHOST" settings set KNOB_GAP_SIZE 20
	[ "$status" -eq 0 ]

	[ -L "$XGHOST_KNOBS_FILE" ]
	[ "$(readlink "$XGHOST_KNOBS_FILE")" = "$repo/knobs.conf" ]
	run grep -Fx 'KNOB_GAP_SIZE=20' "$repo/knobs.conf"
	[ "$status" -eq 0 ]
	# The comment of the user survives the trip through the link.
	run grep -F 'kept in a dotfiles repository' "$repo/knobs.conf"
	[ "$status" -eq 0 ]
	# The temporary file was made beside the target and renamed onto it, so
	# neither end of the link holds one now.
	run find "$BATS_TEST_TMPDIR" "$repo" -maxdepth 1 -name 'knobs.conf.????????'
	[ -z "$output" ]
}

@test "settings set reports a knobs link that points at nothing" {
	ln -s "$BATS_TEST_TMPDIR/nowhere/knobs.conf" "$XGHOST_KNOBS_FILE"
	run "$XGHOST" settings set KNOB_GAP_SIZE 20
	[ "$status" -eq 1 ]
	[[ $output == *"points at nothing"* ]]
}

# A user who narrowed their own file chose that. A writer that widened it again
# would undo the choice and say nothing.
@test "settings set keeps the mode of a file that is already there" {
	make_knobs <<-'EOF'
		KNOB_GAP_SIZE=5
	EOF
	chmod 0600 "$XGHOST_KNOBS_FILE"
	"$XGHOST" settings set KNOB_GAP_SIZE 20 >/dev/null
	[ "$(stat -c '%a' "$XGHOST_KNOBS_FILE")" = 600 ]
}

# A write that runs out of room fails part way through the copy. The rename must
# not happen, because the file it would install is cut off mid-line and the
# knobs of the user are on the other end of it.
#
# The limit is set with 'ulimit -f', and SIGXFSZ is ignored so that an
# over-limit write returns EFBIG to the writer rather than killing it. That is
# the failure a full disk gives, and it is the one shape of it a test can make
# without a full disk.
@test "settings set reports a write that fails, and leaves the knobs whole" {
	local line
	{
		printf '# My preferences.\n'
		for line in $(seq 1 200); do
			printf '# comment line %03d: a line of prose the user wrote by hand.\n' "$line"
		done
		printf 'KNOB_GAP_SIZE=5\n'
	} >"$XGHOST_KNOBS_FILE"
	local before
	before=$(md5sum <"$XGHOST_KNOBS_FILE")
	[ "$(stat -c %s "$XGHOST_KNOBS_FILE")" -gt 2048 ]

	cat >"$BATS_TEST_TMPDIR/limited" <<-'EOF'
		#!/usr/bin/env bash
		# An over-limit write returns EFBIG instead of raising SIGXFSZ. The
		# ignored signal survives the exec, and so does the limit.
		trap '' XFSZ
		ulimit -f 2
		exec "$@"
	EOF
	chmod +x "$BATS_TEST_TMPDIR/limited"

	run "$BATS_TEST_TMPDIR/limited" "$XGHOST" settings set KNOB_GAP_SIZE 20
	[ "$status" -ne 0 ]
	[[ $output == *"cannot write the knobs"* ]]
	[[ $output != *"KNOB_GAP_SIZE is now"* ]]

	# The file of the user is exactly as it was.
	[ "$(md5sum <"$XGHOST_KNOBS_FILE")" = "$before" ]
	# And the file that was cut off is gone.
	run find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'knobs.conf.????????'
	[ -z "$output" ]
}

# Two 'settings set' commands at once. Without a lock both read the same file
# and the second rename drops the knob the first one wrote, while both commands
# report success. Issue #11 names a settings application, so two writers are
# expected rather than exotic.
@test "two settings set commands at once keep both knobs" {
	local trial first second
	for trial in 1 2 3 4 5 6 7 8 9 10; do
		rm -f "$XGHOST_KNOBS_FILE"
		"$XGHOST" settings set KNOB_GAP_SIZE 20 >/dev/null 2>&1 &
		first=$!
		"$XGHOST" settings set KNOB_ANIMATIONS off >/dev/null 2>&1 &
		second=$!
		wait "$first"
		wait "$second"
		run grep -Fx 'KNOB_GAP_SIZE=20' "$XGHOST_KNOBS_FILE"
		[ "$status" -eq 0 ]
		run grep -Fx 'KNOB_ANIMATIONS=off' "$XGHOST_KNOBS_FILE"
		[ "$status" -eq 0 ]
	done
}

# The lock sits beside the knobs file rather than under the state directory,
# because a machine that has never rendered anything still sets a knob.
@test "the knobs are locked beside the file, and need no state directory" {
	unset XDG_STATE_HOME
	unset HOME
	run "$XGHOST" settings set KNOB_GAP_SIZE 20
	[ "$status" -eq 0 ]
	[[ $output == *"no theme is active"* ]]
	[ -f "$XGHOST_KNOBS_FILE.lock" ]
	run grep -Fx 'KNOB_GAP_SIZE=20' "$XGHOST_KNOBS_FILE"
	[ "$status" -eq 0 ]
}

# --- the knobs survive an update ---------------------------------------------

# The file is in the config directory and an update replaces the checkout, so
# nothing an update does can reach it. A knob added by a later version reaches
# an old file as its default rather than as a failure.
@test "a knobs file that names no new knob still renders" {
	use_own_inputs
	use_own_schema <<-'EOF'
		knob=KNOB_SHAPE
		summary=The shape.
		value=round
		value=square
		default=round
	EOF
	make_knobs <<-'EOF'
		KNOB_SHAPE=square
	EOF
	make_theme demo <<-'EOF'
		BG=#1a2b3c
	EOF
	make_template plain.conf <<-'EOF'
		shape = @KNOB_SHAPE@
		label = @KNOB_LABEL@
	EOF

	# The version that adds KNOB_LABEL. The knobs file still names one knob.
	plain_schema | use_own_schema
	"$XGHOST" theme set demo >/dev/null
	run cat "$GENERATED/plain.conf"
	[ "$output" = "shape = square
label = Plain Label" ]
}
