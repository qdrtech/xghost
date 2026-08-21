#!/usr/bin/env bats
#
# Tests for 'xghost machine detect' and for lib/detect.sh behind it.
#
# Detection reads the machine it runs on, so it gets smoke tests: enough to
# prove that it runs, that it writes the file, and that the file it writes is
# well formed. Testing it more deeply would mean standing a fake Hyprland up,
# and a test of a fake proves the fake.
#
# The parsing is another matter. Every function that turns the answer of a
# source into facts is pure, and each one is tested here against fixture text
# under tests/fixtures/detect. No test in this file depends on the hardware of
# the machine that runs it.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	FIXTURES="$BATS_TEST_DIRNAME/fixtures/detect"

	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"

	# The machine facts file of this test, never the one of the user.
	export XGHOST_MACHINE_FACTS="$BATS_TEST_TMPDIR/machine.conf"
}

# Run one snippet against the libraries, with the checkout as $1 and the
# fixture directory as $2.
run_snippet() {
	local script="$BATS_TEST_TMPDIR/snippet.sh"
	cat >"$script"
	run bash "$script" "$ROOT_DIR" "$FIXTURES"
}

# Print the value of one key of the file that was written.
fact() {
	local key=$1 line
	while IFS= read -r line; do
		if [ "${line%%=*}" = "$key" ]; then
			printf '%s\n' "${line#*=}"
			return 0
		fi
	done <"$XGHOST_MACHINE_FACTS"
	printf '<absent>\n'
}

# --- the monitors of one answer ---------------------------------------------

@test "two monitors produce two blocks, a count and a primary" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		IFS= read -r -d '' text <"$2/monitors-two.json" || true
		json_parse "$text" || exit 1
		detect_monitor_primary 2
		detect_monitor_blocks 2
		detect_document | grep '^MACHINE_'
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_PRIMARY_MONITOR=eDP-1
MACHINE_PRIMARY_SCALE=1.5
MACHINE_MONITOR_1_NAME=DP-1
MACHINE_MONITOR_1_DESCRIPTION=Dell Inc. DELL U2720Q H4NM13
MACHINE_MONITOR_1_WIDTH=3840
MACHINE_MONITOR_1_HEIGHT=2160
MACHINE_MONITOR_1_REFRESH=59.997
MACHINE_MONITOR_1_X=0
MACHINE_MONITOR_1_Y=0
MACHINE_MONITOR_1_SCALE=2
MACHINE_MONITOR_1_TRANSFORM=0
MACHINE_MONITOR_1_FOCUSED=no
MACHINE_MONITOR_1_MODE=3840x2160@59.997
MACHINE_MONITOR_1_POSITION=0x0
MACHINE_MONITOR_2_NAME=eDP-1
MACHINE_MONITOR_2_DESCRIPTION=BOE 0x0803
MACHINE_MONITOR_2_WIDTH=2256
MACHINE_MONITOR_2_HEIGHT=1504
MACHINE_MONITOR_2_REFRESH=59.999
MACHINE_MONITOR_2_X=3840
MACHINE_MONITOR_2_Y=240
MACHINE_MONITOR_2_SCALE=1.5
MACHINE_MONITOR_2_TRANSFORM=0
MACHINE_MONITOR_2_FOCUSED=yes
MACHINE_MONITOR_2_MODE=2256x1504@59.999
MACHINE_MONITOR_2_POSITION=3840x240" ]
}

# The compositor reports no focused monitor when nothing holds the focus, and
# the first monitor is then the one the desktop treats as the first.
@test "the first monitor is the primary one when none is focused" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		IFS= read -r -d '' text <"$2/monitors-none-focused.json" || true
		json_parse "$text" || exit 1
		detect_monitor_primary 2
		detect_document | grep '^MACHINE_PRIMARY'
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_PRIMARY_MONITOR=HDMI-A-1
MACHINE_PRIMARY_SCALE=1" ]
}

@test "an answer with no monitor gives a count of zero and no primary" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		IFS= read -r -d '' text <"$2/monitors-empty.json" || true
		json_parse "$text" || exit 1
		printf 'count=%s\n' "${JSON_SIZE[.]}"
		detect_monitor_primary "${JSON_SIZE[.]}"
		detect_monitor_blocks "${JSON_SIZE[.]}"
		detect_document | grep '^MACHINE_'
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "count=0
MACHINE_PRIMARY_MONITOR=unknown
MACHINE_PRIMARY_SCALE=unknown" ]
}

@test "a monitor with a member missing records that member as unknown" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		json_parse '[{"name": "DP-1", "x": 0, "y": 0, "scale": 1.00}]' || exit 1
		detect_monitor_blocks 1
		detect_document | grep -E '^MACHINE_MONITOR_1_(WIDTH|MODE|POSITION)='
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_MONITOR_1_WIDTH=unknown
MACHINE_MONITOR_1_MODE=unknown
MACHINE_MONITOR_1_POSITION=0x0" ]
}

# A source that answers with the JSON value null has answered that the member
# has no value. Recording the word would put 'monitor = null,...' into a
# rendered Hyprland file as though the compositor had reported that name.
@test "a null in the answer is recorded as unknown and reported" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		json_parse '[{"name": null, "description": "Acme", "width": 1920, "height": 1080, "refreshRate": 60, "x": 0, "y": 0, "scale": 1, "transform": 0, "focused": true}]' || exit 1
		detect_monitor_primary 1
		detect_monitor_blocks 1
		detect_document | grep -E '^MACHINE_(PRIMARY_MONITOR|MONITOR_1_NAME|MONITOR_1_MODE)='
		printf '%s\n' "${DETECT_WARNINGS[@]}"
	EOF
	[ "$status" -eq 0 ]
	[[ $output == *"MACHINE_PRIMARY_MONITOR=unknown"* ]]
	[[ $output == *"MACHINE_MONITOR_1_NAME=unknown"* ]]
	[[ $output == *"MACHINE_MONITOR_1_MODE=1920x1080@60"* ]]
	[[ $output == *"the answer holds null at '0.name'"* ]]
	[[ $output != *=null* ]]
}

# The difference is a real one, and it runs the other way too: a monitor whose
# name really is the string "null" has a name, and detection keeps it.
@test "a monitor whose name is the string null keeps that name" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		json_parse '[{"name": "null", "scale": 1}]' || exit 1
		detect_monitor_primary 1
		detect_document | grep '^MACHINE_PRIMARY_MONITOR='
		printf 'warnings: %s\n' "${#DETECT_WARNINGS[@]}"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_PRIMARY_MONITOR=null
warnings: 0" ]
}

# A JSON object records a size as well, and that size is the number of its
# member names. Reading it as a count would put a hard number into the file
# that no compositor reported, and a template consumes that number.
@test "an object where a list was expected yields no count" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		json_parse '{"a": 1, "b": 2, "c": 3}' || exit 1
		detect_list_size "$JSON_ROOT"
		printf 'monitors: [%s]\n' "$DETECT_FIELD"

		json_parse '{"keyboards": {"a": 1, "b": 2}, "mice": {"x": 1}, "switches": {}, "touch": {}}' || exit 1
		detect_keyboard_devices
		detect_pointer_devices
		detect_switch_devices
		detect_device_count touch MACHINE_TOUCHSCREEN_COUNT
		detect_document | grep '^MACHINE_'
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "monitors: []
MACHINE_KEYBOARD_DEVICE_COUNT=unknown
MACHINE_KEYBOARD_DEVICE_MAIN=unknown
MACHINE_POINTER_COUNT=unknown
MACHINE_TOUCHPAD_COUNT=unknown
MACHINE_SWITCH_COUNT=unknown
MACHINE_TOUCHSCREEN_COUNT=unknown" ]
}

@test "the trailing zeros of a number are dropped and an integer is left alone" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		for value in 239.97000 1.00 1.25 0.20 60 2560 -1.50 1e3; do
			detect_trim_number "$value"
			printf '%s -> %s\n' "$value" "$DETECT_FIELD"
		done
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "239.97000 -> 239.97
1.00 -> 1
1.25 -> 1.25
0.20 -> 0.2
60 -> 60
2560 -> 2560
-1.50 -> -1.5
1e3 -> 1e3" ]
}

# --- the input devices of one answer ----------------------------------------

@test "a laptop answer names the touchpad, the keyboards and the lid switch" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		IFS= read -r -d '' text <"$2/devices-laptop.json" || true
		json_parse "$text" || exit 1
		detect_keyboard_devices
		detect_pointer_devices
		detect_device_count touch MACHINE_TOUCHSCREEN_COUNT
		detect_device_count tablets MACHINE_TABLET_COUNT
		detect_switch_devices
		detect_document | grep '^MACHINE_'
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_KEYBOARD_DEVICE_COUNT=2
MACHINE_KEYBOARD_DEVICE_MAIN=at-translated-set-2-keyboard
MACHINE_KEYBOARD_DEVICE_1_NAME=at-translated-set-2-keyboard
MACHINE_KEYBOARD_DEVICE_1_LAYOUT=gb
MACHINE_KEYBOARD_DEVICE_2_NAME=power-button
MACHINE_KEYBOARD_DEVICE_2_LAYOUT=us
MACHINE_POINTER_COUNT=2
MACHINE_TOUCHPAD_COUNT=1
MACHINE_POINTER_1_NAME=elan1200:00-04f3:30fc-touchpad
MACHINE_POINTER_2_NAME=logitech-usb-receiver-mouse
MACHINE_TOUCHPAD_1_NAME=elan1200:00-04f3:30fc-touchpad
MACHINE_TOUCHSCREEN_COUNT=1
MACHINE_TABLET_COUNT=0
MACHINE_SWITCH_COUNT=1
MACHINE_SWITCH_1_NAME=lid-switch" ]
}

@test "a desktop answer with no device records a count of zero" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		IFS= read -r -d '' text <"$2/devices-empty.json" || true
		json_parse "$text" || exit 1
		detect_keyboard_devices
		detect_pointer_devices
		detect_switch_devices
		detect_document | grep -E '^MACHINE_(KEYBOARD_DEVICE_COUNT|KEYBOARD_DEVICE_MAIN|POINTER_COUNT|TOUCHPAD_COUNT|SWITCH_COUNT)='
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_KEYBOARD_DEVICE_COUNT=0
MACHINE_KEYBOARD_DEVICE_MAIN=none
MACHINE_POINTER_COUNT=0
MACHINE_TOUCHPAD_COUNT=0
MACHINE_SWITCH_COUNT=0" ]
}

# --- the backlight ----------------------------------------------------------

# Build one directory of backlights, the way the kernel exposes them, and print
# its path.
#
#   backlight_fixture NAME:TYPE...
#
# An entry written without a ':' gets no 'type' file, which is the backlight
# whose kind this run cannot read. The directory is inside the temporary
# directory of the test, so nothing here reads /sys and nothing here depends on
# the hardware of the machine running the suite.
backlight_fixture() {
	local dir="$BATS_TEST_TMPDIR/backlight" entry name
	rm -rf "$dir"
	mkdir -p "$dir"
	for entry in "$@"; do
		name=${entry%%:*}
		mkdir -p "$dir/$name"
		if [ "$entry" != "$name" ]; then
			printf '%s\n' "${entry#*:}" >"$dir/$name/type"
		fi
	done
	printf '%s\n' "$dir"
}

# Read one directory of backlights and print the facts, and then the warnings.
#
#   run_backlight DIRECTORY
run_backlight() {
	run bash -c '
		set -uo pipefail
		. "$1/lib/detect.sh"
		detect_backlight "$2"
		detect_document | grep "^MACHINE_BACKLIGHT"
		# printf repeats its format once with no argument at all, so an empty
		# list would print one warning line that no run produced.
		if [ "${#DETECT_WARNINGS[@]}" -gt 0 ]; then
			printf "warning: %s\n" "${DETECT_WARNINGS[@]}"
		fi
	' _ "$ROOT_DIR" "$1"
}

# The machine this bundle was written on takes this path: /sys/class/backlight
# exists and holds nothing. A count of 0 is an answer, and it is the answer
# that decides a notification centre gets no brightness slider.
@test "a machine with no backlight records a count of zero and no block" {
	run_backlight "$(backlight_fixture)"
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_BACKLIGHT_COUNT=0" ]
}

@test "one backlight is recorded by its name and by its kind" {
	run_backlight "$(backlight_fixture intel_backlight:raw)"
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_BACKLIGHT_COUNT=1
MACHINE_BACKLIGHT_1_NAME=intel_backlight
MACHINE_BACKLIGHT_1_TYPE=raw" ]
}

# A laptop with a discrete graphics card has two, and the kind is the only
# thing that tells them apart. Both are recorded, so whatever reads them later
# chooses between them rather than being handed one this module picked.
@test "two backlights are both recorded, in the order the kernel names them" {
	run_backlight "$(backlight_fixture acpi_video0:firmware amdgpu_bl0:raw)"
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_BACKLIGHT_COUNT=2
MACHINE_BACKLIGHT_1_NAME=acpi_video0
MACHINE_BACKLIGHT_1_TYPE=firmware
MACHINE_BACKLIGHT_2_NAME=amdgpu_bl0
MACHINE_BACKLIGHT_2_TYPE=raw" ]
}

# The entry is a backlight whether or not its 'type' can be read, so the block
# is written and the one value that is missing is the one that says 'unknown'.
@test "a backlight whose kind cannot be read is still a backlight, and says so" {
	run_backlight "$(backlight_fixture nvidia_wmi_ec_backlight)"
	[ "$status" -eq 0 ]
	[[ $output == "MACHINE_BACKLIGHT_COUNT=1
MACHINE_BACKLIGHT_1_NAME=nvidia_wmi_ec_backlight
MACHINE_BACKLIGHT_1_TYPE=unknown"* ]]
	[[ $output == *"warning: '"*"/nvidia_wmi_ec_backlight/type' could not be read"* ]]
}

# An empty directory and no directory are two different answers, and the file
# tells them apart: 0 is a machine with no backlight, 'unknown' is a run that
# could not read whether it has one.
@test "a backlight directory that is not there records unknown rather than zero" {
	run_backlight "$BATS_TEST_TMPDIR/no-such-directory"
	[ "$status" -eq 0 ]
	[[ $output == "MACHINE_BACKLIGHT_COUNT=unknown"* ]]
	[[ $output == *"warning: '"*"/no-such-directory' is not a directory"* ]]
}

# The rule of the whole module: a fact this run could not read keeps the value
# of the previous run. A count that is kept names blocks, and those blocks are
# written again with it, so the file never holds a count of two and no block.
@test "a run that read no backlight keeps the count and the blocks of the last one" {
	run bash -c '
		set -uo pipefail
		. "$1/lib/detect.sh"
		DETECT_PREVIOUS_SCALARS[MACHINE_BACKLIGHT_COUNT]=2
		DETECT_PREVIOUS_SCALARS[MACHINE_BACKLIGHT_1_NAME]=acpi_video0
		DETECT_PREVIOUS_SCALARS[MACHINE_BACKLIGHT_1_TYPE]=firmware
		DETECT_PREVIOUS_SCALARS[MACHINE_BACKLIGHT_2_NAME]=amdgpu_bl0
		DETECT_PREVIOUS_SCALARS[MACHINE_BACKLIGHT_2_TYPE]=raw
		detect_backlight "$2"
		detect_document | grep "^MACHINE_BACKLIGHT"
	' _ "$ROOT_DIR" "$BATS_TEST_TMPDIR/no-such-directory"
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_BACKLIGHT_COUNT=2
MACHINE_BACKLIGHT_1_NAME=acpi_video0
MACHINE_BACKLIGHT_1_TYPE=firmware
MACHINE_BACKLIGHT_2_NAME=amdgpu_bl0
MACHINE_BACKLIGHT_2_TYPE=raw" ]
}

# --- the keyboard of the system ---------------------------------------------

@test "the settings of localectl are read from its output" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		IFS= read -r -d '' text <"$2/localectl-full.txt" || true
		detect_parse_localectl "$text"
		for label in 'X11 Layout' 'X11 Model' 'X11 Variant' 'X11 Options' 'VC Keymap' 'System Locale'; do
			detect_localectl_field "$label" none
			printf '%s = %s\n' "$label" "$DETECT_FIELD"
		done
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "X11 Layout = gb
X11 Model = pc105
X11 Variant = colemak
X11 Options = ctrl:nocaps,compose:ralt
VC Keymap = uk
System Locale = LANG=en_GB.UTF-8" ]
}

# localectl prints 'n/a' for a setting that is not set, which means the same as
# a line it did not print at all.
@test "a localectl setting that is not set falls back to the value the caller names" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		IFS= read -r -d '' text <"$2/localectl-console-only.txt" || true
		detect_parse_localectl "$text"
		detect_localectl_field 'X11 Layout' ''
		printf 'x11 layout = [%s]\n' "$DETECT_FIELD"
		detect_localectl_field 'VC Keymap' ''
		printf 'console keymap = [%s]\n' "$DETECT_FIELD"
		detect_localectl_field 'X11 Variant' none
		printf 'variant = [%s]\n' "$DETECT_FIELD"
		detect_localectl_field 'Nothing At All' none
		printf 'absent = [%s]\n' "$DETECT_FIELD"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "x11 layout = []
console keymap = [dvorak]
variant = [none]
absent = [none]" ]
}

@test "the output of a localectl that printed nothing yields no setting" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		detect_parse_localectl ''
		detect_localectl_field 'X11 Layout' unknown
		printf '[%s]\n' "$DETECT_FIELD"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "[unknown]" ]
}

# --- the default terminal ---------------------------------------------------

@test "the first entry of a terminal list is the default terminal" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		list=$2/terminals.list
		printf '# a comment\n\nghostty.desktop\nalacritty.desktop\n' >"$list"
		if detect_first_entry "$list"; then printf '%s\n' "$DETECT_FIELD"; fi
		printf 'empty file: '
		printf '# only a comment\n' >"$list"
		if detect_first_entry "$list"; then printf '%s\n' "$DETECT_FIELD"; else printf 'no entry\n'; fi
		printf 'no file: '
		if detect_first_entry "$2/absent.list"; then printf '%s\n' "$DETECT_FIELD"; else printf 'no entry\n'; fi
		rm -f "$list"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "ghostty.desktop
empty file: no entry
no file: no entry" ]
}

@test "the terminal list of the current desktop is read before the plain one" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		export XDG_CONFIG_HOME=/home/ada/.config
		export XDG_CONFIG_DIRS=/etc/xdg
		export XDG_CURRENT_DESKTOP=Hyprland
		detect_terminal_lists
		printf '%s\n' "${DETECT_TERMINAL_PATHS[@]}"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "/home/ada/.config/hyprland-xdg-terminals.list
/home/ada/.config/xdg-terminals.list
/etc/xdg/hyprland-xdg-terminals.list
/etc/xdg/xdg-terminals.list" ]
}

# TERM names the terminal this run prints to, which during an installation is a
# virtual console. It is not the default terminal, so it is not a source.
@test "the TERMINAL variable is a source and TERM is not" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		export TERM=xterm-ghostty
		export TERMINAL=alacritty
		export XDG_CONFIG_HOME=$2/none
		export XDG_CONFIG_DIRS=$2/none
		detect_terminal
		detect_document | grep '^MACHINE_TERMINAL='

		DETECT_KEYS=()
		DETECT_VALUES=()
		unset TERMINAL
		detect_terminal
		detect_document | grep '^MACHINE_TERMINAL='
		printf '%s\n' "${DETECT_WARNINGS[@]}"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "MACHINE_TERMINAL=alacritty
MACHINE_TERMINAL=unknown
no default terminal is declared: TERMINAL is empty and no 'xdg-terminals.list' names one" ]
}

# --- the same problem is reported once --------------------------------------

@test "one missing program is reported once, however often the run reaches for it" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		detect_capture 'the first fact' this-program-does-not-exist a || true
		detect_capture 'the first fact' this-program-does-not-exist a || true
		detect_capture 'the second fact' this-program-does-not-exist b || true
		printf '%s\n' "${DETECT_WARNINGS[@]}"
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "the 'this-program-does-not-exist' program is not installed, so the first fact is not known
the 'this-program-does-not-exist' program is not installed, so the second fact is not known" ]
}

# The set that reports one problem once has to be cleared by a new run, or a
# second run in one process reports nothing at all and the whole honesty
# channel goes silent. The CLI is one run per process today, and detection is
# documented as safe to run twice.
@test "a second detect_all reports the problems of the second run" {
	run_snippet <<-'EOF'
		set -uo pipefail
		. "$1/lib/detect.sh"
		for run in 1 2 3; do
			detect_all
			before=${#DETECT_WARNINGS[@]}
			detect_capture 'a fact of this test' this-program-does-not-exist || true
			printf 'run %s: %s new\n' "$run" "$((${#DETECT_WARNINGS[@]} - before))"
		done
	EOF
	[ "$status" -eq 0 ]
	[ "$output" = "run 1: 1 new
run 2: 1 new
run 3: 1 new" ]
}

# --- the command ------------------------------------------------------------

@test "machine detect writes the machine facts file and names it" {
	run "$XGHOST" machine detect
	[ "$status" -eq 0 ]
	[ -f "$XGHOST_MACHINE_FACTS" ]
	[[ $output == *"the machine facts are at $XGHOST_MACHINE_FACTS"* ]]
	[[ $output == *"edit that file to correct a detection"* ]]
}

@test "the file machine detect writes is one the reader accepts" {
	"$XGHOST" machine detect >/dev/null 2>&1
	run bash -c '
		set -uo pipefail
		. "$1/lib/facts.sh"
		if facts_load "$2"; then
			printf "well formed, %s facts\n" "${#FACTS_SCALARS[@]}"
		else
			printf "problem: %s\n" "${FACTS_ERRORS[@]}"
			exit 1
		fi
	' _ "$ROOT_DIR" "$XGHOST_MACHINE_FACTS"
	[ "$status" -eq 0 ]
	[[ $output == "well formed, "* ]]
}

# Every fact the issue asks for has a key, on every machine. A source that is
# missing changes the value to 'unknown' and never removes the key.
@test "the file covers every fact, whatever this machine can answer" {
	"$XGHOST" machine detect >/dev/null 2>&1
	local key
	for key in MACHINE_FACTS_VERSION MACHINE_COMPOSITOR \
		MACHINE_MONITOR_COUNT MACHINE_PRIMARY_MONITOR MACHINE_PRIMARY_SCALE \
		MACHINE_TIMEZONE MACHINE_KEYBOARD_LAYOUT MACHINE_KEYBOARD_VARIANT \
		MACHINE_KEYBOARD_MODEL MACHINE_KEYBOARD_OPTIONS \
		MACHINE_COMPOSITOR_KB_LAYOUT MACHINE_COMPOSITOR_KB_VARIANT \
		MACHINE_KEYBOARD_DEVICE_COUNT MACHINE_POINTER_COUNT \
		MACHINE_TOUCHPAD_COUNT MACHINE_TOUCHSCREEN_COUNT \
		MACHINE_TABLET_COUNT MACHINE_SWITCH_COUNT \
		MACHINE_BACKLIGHT_COUNT \
		MACHINE_BROWSER MACHINE_TERMINAL; do
		[ "$(fact "$key")" != '<absent>' ] || fail "$key is not in the file"
	done
}

@test "the file states what happens to an edit" {
	"$XGHOST" machine detect >/dev/null 2>&1
	run cat "$XGHOST_MACHINE_FACTS"
	[[ $output == *"replaces this whole file"* ]]
	[[ $output == *"never patches"* ]]
	[[ $output == *"survives"* ]]
}

@test "detection run twice writes the same file" {
	"$XGHOST" machine detect >/dev/null 2>&1
	cp "$XGHOST_MACHINE_FACTS" "$BATS_TEST_TMPDIR/first.conf"
	"$XGHOST" machine detect >/dev/null 2>&1
	diff "$BATS_TEST_TMPDIR/first.conf" "$XGHOST_MACHINE_FACTS"
}

# The ADR gives detection the whole file: it never patches and never merges. A
# correction a user made is therefore replaced, and the run that replaces it
# leaves the file it replaced beside the new one.
@test "detection replaces the whole file and leaves the previous one beside it" {
	"$XGHOST" machine detect >/dev/null 2>&1
	printf '\n# a note a user wrote\nMACHINE_MONITOR_9_NAME=CORRECTED\n' \
		>>"$XGHOST_MACHINE_FACTS"

	run "$XGHOST" machine detect
	[ "$status" -eq 0 ]
	[[ $output == *"copied to $XGHOST_MACHINE_FACTS.previous"* ]]

	run cat "$XGHOST_MACHINE_FACTS"
	[[ $output != *CORRECTED* ]]
	[[ $output != *"a note a user wrote"* ]]

	run cat "$XGHOST_MACHINE_FACTS.previous"
	[[ $output == *CORRECTED* ]]
}

# The copy exists to make a lost correction recoverable. A run that writes
# exactly the file that is already there would copy the auto-detected file over
# the copy that holds the correction, and the copy that destroyed it would
# carry nothing. The documented run at every login makes this the common case.
@test "a detection that changes nothing keeps the copy that was already there" {
	"$XGHOST" machine detect >/dev/null 2>&1

	printf 'MACHINE_MONITOR_9_NAME=CORRECTED\n' >>"$XGHOST_MACHINE_FACTS"
	"$XGHOST" machine detect >/dev/null 2>&1
	grep -q CORRECTED "$XGHOST_MACHINE_FACTS.previous"

	# This run writes the file that is already there, so it makes no copy and
	# says nothing about one.
	run "$XGHOST" machine detect
	[ "$status" -eq 0 ]
	[[ $output != *"copied to"* ]]
	grep -q CORRECTED "$XGHOST_MACHINE_FACTS.previous"

	# And again, because a login happens more than twice.
	"$XGHOST" machine detect >/dev/null 2>&1
	grep -q CORRECTED "$XGHOST_MACHINE_FACTS.previous"
}

# The copy is written by the same run as the file, so it carries the same mode.
@test "the copy of the machine facts has the mode of the file, not the umask" {
	(
		umask 077
		"$XGHOST" machine detect >/dev/null 2>&1
		printf 'MACHINE_MONITOR_9_NAME=CORRECTED\n' >>"$XGHOST_MACHINE_FACTS"
		"$XGHOST" machine detect >/dev/null 2>&1
	)
	[ "$(stat -c %a "$XGHOST_MACHINE_FACTS.previous")" = 644 ]
}

# 'cp' copies into a directory rather than over it. It would report success
# while the copy sat at a path this run never named, and the message would
# point the user at a path that holds nothing.
@test "detection refuses to make the copy when a directory sits where it goes" {
	"$XGHOST" machine detect >/dev/null 2>&1
	printf 'MACHINE_MONITOR_9_NAME=CORRECTED\n' >>"$XGHOST_MACHINE_FACTS"
	mkdir "$XGHOST_MACHINE_FACTS.previous"

	run "$XGHOST" machine detect
	[ "$status" -eq 1 ]
	[[ $output == *"because a directory is there"* ]]

	# Nothing was changed, so the correction is still in the file.
	grep -q CORRECTED "$XGHOST_MACHINE_FACTS"
}

# A link that points at nothing has nothing behind it to copy. The user made
# that link, so detection names it rather than deciding what it was meant to
# be, and the message says what to do about it.
@test "detection names a machine facts path that is a link to nothing" {
	ln -s "$BATS_TEST_TMPDIR/nowhere" "$XGHOST_MACHINE_FACTS"

	run "$XGHOST" machine detect
	[ "$status" -eq 1 ]
	[[ $output == *"symbolic link that points at nothing"* ]]
	[[ $output == *"$XGHOST_MACHINE_FACTS"* ]]
	[[ $output == *"Remove the link"* ]]
}

@test "the machine facts file is readable by everybody and writable by its owner" {
	"$XGHOST" machine detect >/dev/null 2>&1
	[ "$(stat -c %a "$XGHOST_MACHINE_FACTS")" = 644 ]
}

@test "the mode of the machine facts file does not follow the umask of the caller" {
	(
		umask 077
		"$XGHOST" machine detect >/dev/null 2>&1
	)
	[ "$(stat -c %a "$XGHOST_MACHINE_FACTS")" = 644 ]
}

@test "machine detect creates the directory that holds the file" {
	export XGHOST_MACHINE_FACTS="$BATS_TEST_TMPDIR/deep/down/machine.conf"
	run "$XGHOST" machine detect
	[ "$status" -eq 0 ]
	[ -f "$XGHOST_MACHINE_FACTS" ]
}

@test "machine detect takes no argument" {
	run "$XGHOST" machine detect extra
	[ "$status" -eq 2 ]
	[[ $output == *"takes no argument"* ]]
}

@test "machine detect names a machine with no config directory" {
	run env -i "$XGHOST" machine detect
	[ "$status" -eq 1 ]
	[[ $output == *"HOME, XDG_CONFIG_HOME and XGHOST_CONFIG_HOME are all empty"* ]]
}

@test "machine detect reports a file it cannot write" {
	if [ "$(id -u)" -eq 0 ]; then
		skip "root writes into a directory whose mode forbids it"
	fi
	mkdir -p "$BATS_TEST_TMPDIR/locked"
	chmod 500 "$BATS_TEST_TMPDIR/locked"
	export XGHOST_MACHINE_FACTS="$BATS_TEST_TMPDIR/locked/machine.conf"
	run "$XGHOST" machine detect
	[ "$status" -eq 1 ]
	[[ $output == *"cannot write the machine facts"* ]]
	[[ $output != *"Permission denied"* ]]
}

# A machine without Hyprland is a real machine, not a fake one: the four
# programs detection reads are simply not on its PATH. The file must still be
# well formed there, and every fact it could not read must say so.
@test "a machine without any of the detection programs still gets a well-formed file" {
	local bin="$BATS_TEST_TMPDIR/bin" tool path
	mkdir -p "$bin"
	for tool in bash dirname readlink mkdir chmod cp mv rm; do
		path=$(command -v "$tool") || skip "$tool is not installed"
		ln -s "$path" "$bin/$tool"
	done

	# The command file is run directly, because the dispatcher needs programs
	# of its own and this test is about what detection does without any.
	run env -i PATH="$bin" HOME="$HOME" \
		XGHOST_MACHINE_FACTS="$XGHOST_MACHINE_FACTS" \
		"$ROOT_DIR/commands/machine-detect"
	[ "$status" -eq 0 ]
	[ -f "$XGHOST_MACHINE_FACTS" ]

	[[ $output == *"the 'hyprctl' program is not installed"* ]]
	[[ $output == *"the 'localectl' program is not installed"* ]]
	[[ $output == *"the 'timedatectl' program is not installed"* ]]
	[[ $output == *"the 'xdg-settings' program is not installed"* ]]

	[ "$(fact MACHINE_COMPOSITOR)" = unknown ]
	[ "$(fact MACHINE_MONITOR_COUNT)" = unknown ]
	[ "$(fact MACHINE_PRIMARY_MONITOR)" = unknown ]
	[ "$(fact MACHINE_PRIMARY_SCALE)" = unknown ]
	[ "$(fact MACHINE_KEYBOARD_LAYOUT)" = unknown ]
	[ "$(fact MACHINE_KEYBOARD_DEVICE_COUNT)" = unknown ]
	[ "$(fact MACHINE_TOUCHPAD_COUNT)" = unknown ]
	[ "$(fact MACHINE_BROWSER)" = unknown ]

	# The backlight is the one fact of the file that needs no program at all:
	# the kernel exposes it as a directory. So it is read on this machine even
	# here, and the value is a count or the word for a directory that is not
	# there.
	[[ $(fact MACHINE_BACKLIGHT_COUNT) =~ ^([0-9]+|unknown)$ ]]

	# It is still a file the reader accepts.
	run bash -c '
		set -uo pipefail
		. "$1/lib/facts.sh"
		facts_load "$2" || { printf "problem: %s\n" "${FACTS_ERRORS[@]}"; exit 1; }
		printf "well formed\n"
	' _ "$ROOT_DIR" "$XGHOST_MACHINE_FACTS"
	[ "$status" -eq 0 ]
	[ "$output" = "well formed" ]
}
