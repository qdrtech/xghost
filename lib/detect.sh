#!/usr/bin/env bash
#
# The detection module of xghost.
#
# It reads what is physically true about this computer and writes the machine
# facts file. It reads only. It changes no system setting, needs no root, and
# runs the same way twice.
#
# The sources, and the program each one needs:
#
#   Monitors and display scale   hyprctl monitors -j          Hyprland
#   Input devices                hyprctl devices -j           Hyprland
#   Keyboard of the compositor   hyprctl getoption ... -j     Hyprland
#   Keyboard of the system       localectl status             systemd
#   Timezone                     timedatectl show -p Timezone systemd
#                                the link /etc/localtime      the C library
#   Default browser              xdg-settings get ...         xdg-utils
#   Default terminal             TERMINAL, xdg-terminals.list the environment
#
# A source that is missing is never guessed at. The fact is recorded as
# 'unknown', the run names the source it could not read, and the file stays
# well formed. A wrong monitor layout presented as fact is worse than an
# absent one.
#
# The module collects every problem in DETECT_WARNINGS and leaves the reporting
# to the caller. Only detect_document prints, and it prints the file.
#
# The parsing is separated from the probing on purpose. Every function that
# reads text is pure and is tested against fixture text, and every function
# that runs a program is a thin wrapper around detect_capture.

# The include sentinel. A library may be sourced more than once, because two
# modules may each need it. The second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_DETECT_SOURCED:-}" ]; then
	return 0
fi
XGHOST_DETECT_SOURCED=1

XGHOST_DETECT_LIB_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/json.sh
. "$XGHOST_DETECT_LIB_DIR/json.sh"
# shellcheck source=lib/facts.sh
. "$XGHOST_DETECT_LIB_DIR/facts.sh"

# The document being built. The two arrays run in step. An entry whose key is
# empty is a line of the file that carries no fact, such as a comment.
DETECT_KEYS=()
DETECT_VALUES=()

# Every source the run could not read, in the order it met them. A warning is
# recorded once, because one missing program is one fact for the user however
# many times the run reaches for it.
DETECT_WARNINGS=()
declare -A DETECT_WARNED=()

# Set by detect_write when it returns non-zero, and by detect_write to name the
# copy it left behind.
DETECT_PROBLEM=
DETECT_PREVIOUS=

# The scratch of the readers below.
DETECT_OUTPUT=
DETECT_FIELD=
DETECT_TERMINAL_PATHS=()
declare -A DETECT_LOCALECTL=()

# The value localectl prints for a setting that is not set.
readonly DETECT_NOT_APPLICABLE=n/a

# The file that declares the default terminal, per the freedesktop default
# terminal specification.
readonly DETECT_TERMINAL_LIST=xdg-terminals.list

# --- the document -----------------------------------------------------------

# Add one fact.
#
#   detect_add KEY VALUE
#
# The value is cleaned first, because the file holds one fact per line and a
# control character in a value would split that line. A replacement is
# reported rather than made in silence.
detect_add() {
	local key=$1 value=$2

	if ! facts_clean_value "$value"; then
		detect_warn "$key: the value held nothing but control characters, so it is recorded as '$FACTS_UNKNOWN'"
		DETECT_KEYS+=("$key")
		DETECT_VALUES+=("$FACTS_UNKNOWN")
		return 0
	fi
	if [ "$FACTS_CLEAN_CHANGED" = yes ]; then
		detect_warn "$key: the value held a control character, and each one is recorded as a space"
	fi

	DETECT_KEYS+=("$key")
	DETECT_VALUES+=("$FACTS_CLEANED")
}

# Add one line that carries no fact, such as a comment or an empty line.
detect_line() {
	DETECT_KEYS+=('')
	DETECT_VALUES+=("$1")
}

# Record one problem the caller has to report.
#
#   detect_warn TEXT
#
# The same text is recorded once. A run reaches for hyprctl four times, and a
# machine without Hyprland is one fact for the user rather than four lines.
detect_warn() {
	if [ -n "${DETECT_WARNED[$1]+set}" ]; then
		return 0
	fi
	DETECT_WARNED[$1]=1
	DETECT_WARNINGS+=("$1")
}

# Print the whole machine facts file.
#
# The header states, in the file itself, who owns the file and what happens to
# an edit. A user who opens the file to correct a detection reads the rule
# there, and never has to find it in the documentation.
detect_document() {
	local index banner

	# The banner is read into a variable rather than printed by 'cat', so the
	# whole module needs no program that a machine may not have.
	IFS= read -r -d '' banner <<-EOF || true
		# The machine facts of xghost: what is physically true about this computer.
		#
		# Written by:  xghost machine detect
		# Owned by:    you
		# Read by:     the xghost renderer, beside the theme palette
		#
		# 'xghost machine detect' replaces this whole file. It never patches it and
		# never merges into it, so it never reads a single line of what is below.
		#
		# You may edit any value to correct a wrong detection. Your edit survives
		# every xghost update, because an update never writes here. Your edit does
		# not survive the next 'xghost machine detect', which replaces the file.
		# That run first copies this file, with the suffix '$FACTS_PREVIOUS_SUFFIX'
		# added to its name, so a correction you lose that way is still on disk.
		#
		# Two values are defined, and neither one is a detected fact:
		#
		#   '$FACTS_UNKNOWN' means detection could not read the source of this fact.
		#   '$FACTS_NONE' means the source answered that nothing is set.
		#
		# The format is one 'KEY=value' per line. Every key starts with
		# '$FACTS_PREFIX'. A line that starts with a hash is a comment.
		# docs/machine-facts.md holds the rules and the meaning of every key.

	EOF
	printf '%s' "$banner"

	for ((index = 0; index < ${#DETECT_KEYS[@]}; index++)); do
		if [ -z "${DETECT_KEYS[index]}" ]; then
			printf '%s\n' "${DETECT_VALUES[index]}"
			continue
		fi
		printf '%s=' "${DETECT_KEYS[index]}"
		facts_quote_value "${DETECT_VALUES[index]}"
		printf '\n'
	done
}

# Write the machine facts file.
#
#   detect_write PATH
#
# The new file is written beside the old one and moved into place, so a run
# that fails part way leaves the old file whole. A file that was already there
# is copied to '<path>.previous' first, and DETECT_PREVIOUS names that copy.
#
# The copy is not a merge. Detection still writes the whole file and still
# reads nothing of what was there. The copy exists so that a correction a user
# made by hand is recoverable after a re-detection replaced it.
#
# A run that writes exactly the file that is already there makes no copy. Such
# a copy carries nothing, and making it would replace a copy that carries a
# correction: two runs with no edit between them would then leave a backup of
# the auto-detected file and the correction would be gone. Detection is offered
# twice during an installation and again at the start of a session, so the
# no-op re-run is the common one.
#
# Returns 1 and sets DETECT_PROBLEM when the file was not written.
detect_write() {
	local path=$1
	local dir=${path%/*}
	local previous=$path$FACTS_PREVIOUS_SUFFIX
	local temp=$path.new.$$

	DETECT_PROBLEM=
	DETECT_PREVIOUS=

	if [ "$dir" = "$path" ]; then
		dir=.
	fi
	if ! mkdir -p "$dir" 2>/dev/null; then
		DETECT_PROBLEM="cannot create the directory that holds the machine facts: $dir"
		return 1
	fi

	# A link that points at nothing is named rather than replaced. The user
	# made that link, and there is nothing behind it to copy, so detection says
	# what it found instead of deciding what the link was meant to be.
	if [ -L "$path" ] && [ ! -e "$path" ]; then
		DETECT_PROBLEM="the machine facts path is a symbolic link that points at nothing: $path. Remove the link, or point it at a file, and run detection again."
		return 1
	fi

	if ! detect_document 2>/dev/null >"$temp"; then
		rm -f "$temp" 2>/dev/null
		DETECT_PROBLEM="cannot write the machine facts to $temp"
		return 1
	fi
	if ! chmod "$FACTS_FILE_MODE" "$temp" 2>/dev/null; then
		rm -f "$temp" 2>/dev/null
		DETECT_PROBLEM="cannot set the mode of $temp"
		return 1
	fi

	if [ -e "$path" ] && ! detect_same "$path" "$temp"; then
		if ! detect_backup "$path" "$previous"; then
			rm -f "$temp" 2>/dev/null
			return 1
		fi
		DETECT_PREVIOUS=$previous
	fi

	if ! mv -- "$temp" "$path" 2>/dev/null; then
		rm -f "$temp" 2>/dev/null
		DETECT_PROBLEM="cannot move the new machine facts into place at $path"
		return 1
	fi
}

# Whether two files hold the same bytes.
#
#   detect_same PATH PATH
#
# The comparison is done in bash, so detection still needs no program a machine
# may not have. A machine facts file holds no NUL byte, because every value is
# cleaned before it is written, so a read that stops at a NUL byte stops only
# at the end of the file.
#
# Returns 1 when the bytes differ, and when either path is not a readable
# regular file.
detect_same() {
	local first second

	if [ ! -f "$1" ] || [ ! -r "$1" ] || [ ! -f "$2" ] || [ ! -r "$2" ]; then
		return 1
	fi

	IFS= read -r -d '' first <"$1" || true
	IFS= read -r -d '' second <"$2" || true

	[ "$first" = "$second" ]
}

# Copy the machine facts that are there to the copy that sits beside them.
#
#   detect_backup PATH PREVIOUS
#
# The copy is built beside its own place and moved in, and its mode is set for
# the same reason the mode of the file itself is set: the mode of a copy
# follows the umask otherwise, and one run would leave two files with two
# modes.
#
# Returns 1 and sets DETECT_PROBLEM when the copy was not made.
detect_backup() {
	local path=$1 previous=$2
	local temp=$previous.new.$$

	# 'cp' copies into a directory rather than over it. It would then report
	# success while the copy sits at a path this run never named.
	if [ -d "$previous" ]; then
		DETECT_PROBLEM="cannot copy the machine facts to $previous, because a directory is there; nothing was changed"
		return 1
	fi
	if ! cp -- "$path" "$temp" 2>/dev/null; then
		rm -f "$temp" 2>/dev/null
		DETECT_PROBLEM="cannot copy the machine facts that are already there to $previous; nothing was changed"
		return 1
	fi
	if ! chmod "$FACTS_FILE_MODE" "$temp" 2>/dev/null; then
		rm -f "$temp" 2>/dev/null
		DETECT_PROBLEM="cannot set the mode of the copy at $previous; nothing was changed"
		return 1
	fi
	if ! mv -- "$temp" "$previous" 2>/dev/null; then
		rm -f "$temp" 2>/dev/null
		DETECT_PROBLEM="cannot move the copy of the machine facts into place at $previous; nothing was changed"
		return 1
	fi
}

# --- reading a source -------------------------------------------------------

# Run one program and keep its standard output in DETECT_OUTPUT.
#
#   detect_capture LABEL PROGRAM [ARGUMENT...]
#
# The standard error of the program is dropped, so the warning this function
# records is the only report. Returns 1 when the program is not installed or
# did not succeed, and names the source in DETECT_WARNINGS.
detect_capture() {
	local label=$1
	shift
	local program=$1

	DETECT_OUTPUT=

	if ! command -v "$program" >/dev/null 2>&1; then
		detect_warn "the '$program' program is not installed, so $label is not known"
		return 1
	fi
	if ! DETECT_OUTPUT=$("$@" 2>/dev/null); then
		detect_warn "'$*' did not succeed, so $label is not known"
		return 1
	fi
}

# Drop the white space at both ends of a value, into DETECT_FIELD.
detect_trim() {
	local text=$1

	text=${text#"${text%%[![:space:]]*}"}
	text=${text%"${text##*[![:space:]]}"}
	DETECT_FIELD=$text
}

# Drop the trailing zeros of a decimal fraction, into DETECT_FIELD.
#
#   detect_trim_number VALUE
#
# Hyprland answers with '239.97000' and with '1.00', and a Hyprland monitor
# line is written with '239.97' and '1'. A value that is not a plain decimal
# fraction, such as an integer or a number with an exponent, is left as it is.
detect_trim_number() {
	local text=$1

	if [[ $text =~ ^-?[0-9]+\.[0-9]+$ ]]; then
		while [ "${text: -1}" = 0 ]; do
			text=${text%0}
		done
		if [ "${text: -1}" = . ]; then
			text=${text%.}
		fi
	fi

	DETECT_FIELD=$text
}

# Read one member of the JSON document into DETECT_FIELD, or 'unknown'.
#
#   detect_field PATH
#
# The JSON value null is not a fact. It is the answer that this member has no
# value, so it is recorded as 'unknown' and reported. JSON_KIND is what tells
# it from a string that holds the four letters of the word: a monitor really
# named "null" is a name, and a monitor whose name is null is a monitor this
# run could not read. Writing the word into the file would put it straight into
# a rendered 'monitor =' line as though the compositor had reported it.
detect_field() {
	local path=$1

	DETECT_FIELD=${JSON_VALUE[$path]:-$FACTS_UNKNOWN}

	if [ "$DETECT_FIELD" = null ] && [ "${JSON_KIND[$path]:-}" = literal ]; then
		detect_warn "the answer holds null at '$path', so that fact is recorded as '$FACTS_UNKNOWN'"
		DETECT_FIELD=$FACTS_UNKNOWN
	fi
}

# The number of members of one JSON array, into DETECT_FIELD.
#
#   detect_list_size PATH
#
# A JSON object records a size as well, and that size is the number of its
# member names rather than a count of anything a caller asked for. A path that
# holds an object is therefore not a list, and DETECT_FIELD is left empty, so a
# caller never turns a member count into a monitor count.
detect_list_size() {
	DETECT_FIELD=

	if [ "${JSON_KIND[$1]:-}" = array ]; then
		DETECT_FIELD=${JSON_SIZE[$1]}
	fi
}

# Read one number of the JSON document into DETECT_FIELD, without its trailing
# zeros.
detect_number() {
	detect_field "$1"
	if [ "$DETECT_FIELD" != "$FACTS_UNKNOWN" ]; then
		detect_trim_number "$DETECT_FIELD"
	fi
}

# Read one true or false of the JSON document into DETECT_FIELD, as yes or no.
detect_flag() {
	detect_field "$1"
	case $DETECT_FIELD in
	true) DETECT_FIELD=yes ;;
	false) DETECT_FIELD=no ;;
	*) DETECT_FIELD=$FACTS_UNKNOWN ;;
	esac
}

# Read the output of 'localectl status' into DETECT_LOCALECTL.
#
#   detect_parse_localectl TEXT
#
# The output is one 'Label: value' per line, and a label may hold a space:
#
#     System Locale: LANG=en_US.UTF-8
#         VC Keymap: us
#        X11 Layout: us
#
# This function is pure. It reads the text it is given and runs nothing.
detect_parse_localectl() {
	local text=$1
	local line label value

	DETECT_LOCALECTL=()

	while IFS= read -r line || [ -n "$line" ]; do
		if [[ ! $line =~ ^[[:space:]]*([A-Za-z0-9][A-Za-z0-9\ ]*):[[:space:]]*(.*)$ ]]; then
			continue
		fi
		label=${BASH_REMATCH[1]}
		value=${BASH_REMATCH[2]}
		value=${value%"${value##*[![:space:]]}"}
		DETECT_LOCALECTL[$label]=$value
	done <<<"$text"
}

# Read one setting of localectl into DETECT_FIELD.
#
#   detect_localectl_field LABEL FALLBACK
#
# A label localectl did not print, and the value it prints for a setting that
# is not set, both mean the same thing: the system declares nothing. The
# caller decides what that is, because an unset variant is 'none' and an unset
# layout still has another source to try.
detect_localectl_field() {
	local label=$1 fallback=$2
	local value=${DETECT_LOCALECTL[$label]:-}

	if [ -z "$value" ] || [ "$value" = "$DETECT_NOT_APPLICABLE" ]; then
		DETECT_FIELD=$fallback
		return 0
	fi

	DETECT_FIELD=$value
}

# Read one Hyprland setting into DETECT_FIELD.
#
#   detect_getoption OPTION
#
# 'hyprctl getoption input:kb_layout -j' answers
# '{"option": "input:kb_layout", "str": "us", "set": true }'. An empty string
# is 'none', because the compositor answered and its answer is that nothing is
# set.
detect_getoption() {
	local option=$1

	DETECT_FIELD=$FACTS_UNKNOWN

	if ! detect_capture "the compositor setting '$option'" hyprctl getoption "$option" -j; then
		return 0
	fi
	if ! json_parse "$DETECT_OUTPUT"; then
		detect_warn "'hyprctl getoption $option -j' did not answer with JSON: $JSON_ERROR"
		return 0
	fi
	if [ -z "${JSON_VALUE[str]+set}" ]; then
		detect_warn "'hyprctl getoption $option -j' answered without a 'str' value"
		return 0
	fi
	# A 'str' that is not a string is not a setting. The word null read as a
	# layout would reach a rendered 'kb_layout =' line as though the compositor
	# had reported it.
	if [ "${JSON_KIND[str]:-}" != string ]; then
		detect_warn "'hyprctl getoption $option -j' answered with a 'str' that is not a string"
		return 0
	fi

	if [ -z "${JSON_VALUE[str]}" ]; then
		DETECT_FIELD=$FACTS_NONE
		return 0
	fi
	DETECT_FIELD=${JSON_VALUE[str]}
}

# --- the displays -----------------------------------------------------------

detect_section_displays() {
	detect_line ''
	detect_line '# --- Displays ---------------------------------------------------------------'
	detect_line '#'
	detect_line '# One block per monitor, numbered from 1 in the order the compositor reports'
	detect_line '# them. MODE and POSITION are the two forms a Hyprland monitor line takes.'
	detect_line ''

	if ! detect_capture 'the monitor layout' hyprctl monitors -j; then
		detect_add MACHINE_COMPOSITOR "$FACTS_UNKNOWN"
		detect_displays_unknown
		return 0
	fi

	detect_add MACHINE_COMPOSITOR hyprland

	if ! json_parse "$DETECT_OUTPUT"; then
		detect_warn "'hyprctl monitors -j' did not answer with JSON: $JSON_ERROR"
		detect_displays_unknown
		return 0
	fi

	local count
	detect_list_size "$JSON_ROOT"
	count=$DETECT_FIELD
	if [ -z "$count" ]; then
		detect_warn "'hyprctl monitors -j' did not answer with a list of monitors"
		detect_displays_unknown
		return 0
	fi

	detect_add MACHINE_MONITOR_COUNT "$count"
	detect_monitor_primary "$count"
	detect_monitor_blocks "$count"
}

# Record that no monitor is known. Every other fact of the section keeps its
# key, so the file is well formed and a template that needs a monitor fails by
# name rather than rendering a guess.
detect_displays_unknown() {
	detect_add MACHINE_MONITOR_COUNT "$FACTS_UNKNOWN"
	detect_add MACHINE_PRIMARY_MONITOR "$FACTS_UNKNOWN"
	detect_add MACHINE_PRIMARY_SCALE "$FACTS_UNKNOWN"
}

# Name the monitor the desktop treats as the first one.
#
# The focused monitor is that monitor. A run with no monitor focused falls back
# to the first monitor the compositor reports, which is the same monitor
# Hyprland itself falls back to.
detect_monitor_primary() {
	local count=$1
	local index name scale
	local primary=$FACTS_UNKNOWN primary_scale=$FACTS_UNKNOWN

	for ((index = 0; index < count; index++)); do
		detect_field "$index.name"
		name=$DETECT_FIELD
		detect_number "$index.scale"
		scale=$DETECT_FIELD
		detect_flag "$index.focused"

		if [ "$index" -eq 0 ]; then
			primary=$name
			primary_scale=$scale
		fi
		if [ "$DETECT_FIELD" = yes ]; then
			primary=$name
			primary_scale=$scale
			break
		fi
	done

	detect_add MACHINE_PRIMARY_MONITOR "$primary"
	detect_add MACHINE_PRIMARY_SCALE "$primary_scale"
}

detect_monitor_blocks() {
	local count=$1
	local index number base
	local name description width height refresh x y scale transform focused

	for ((index = 0; index < count; index++)); do
		number=$((index + 1))
		base=MACHINE_MONITOR_$number

		detect_field "$index.name"
		name=$DETECT_FIELD
		detect_field "$index.description"
		description=$DETECT_FIELD
		detect_number "$index.width"
		width=$DETECT_FIELD
		detect_number "$index.height"
		height=$DETECT_FIELD
		detect_number "$index.refreshRate"
		refresh=$DETECT_FIELD
		detect_number "$index.x"
		x=$DETECT_FIELD
		detect_number "$index.y"
		y=$DETECT_FIELD
		detect_number "$index.scale"
		scale=$DETECT_FIELD
		detect_field "$index.transform"
		transform=$DETECT_FIELD
		detect_flag "$index.focused"
		focused=$DETECT_FIELD

		if [ "$name" = "$FACTS_UNKNOWN" ]; then
			detect_warn "monitor $number has no name in the answer of 'hyprctl monitors -j'"
		fi

		detect_line ''
		detect_add "${base}_NAME" "$name"
		detect_add "${base}_DESCRIPTION" "$description"
		detect_add "${base}_WIDTH" "$width"
		detect_add "${base}_HEIGHT" "$height"
		detect_add "${base}_REFRESH" "$refresh"
		detect_add "${base}_X" "$x"
		detect_add "${base}_Y" "$y"
		detect_add "${base}_SCALE" "$scale"
		detect_add "${base}_TRANSFORM" "$transform"
		detect_add "${base}_FOCUSED" "$focused"

		if [ "$width" = "$FACTS_UNKNOWN" ] || [ "$height" = "$FACTS_UNKNOWN" ] ||
			[ "$refresh" = "$FACTS_UNKNOWN" ]; then
			detect_add "${base}_MODE" "$FACTS_UNKNOWN"
		else
			detect_add "${base}_MODE" "${width}x${height}@${refresh}"
		fi
		if [ "$x" = "$FACTS_UNKNOWN" ] || [ "$y" = "$FACTS_UNKNOWN" ]; then
			detect_add "${base}_POSITION" "$FACTS_UNKNOWN"
		else
			detect_add "${base}_POSITION" "${x}x${y}"
		fi
	done
}

# --- the timezone and the keyboard ------------------------------------------

detect_section_system() {
	detect_line ''
	detect_line '# --- Time and keyboard ------------------------------------------------------'
	detect_line '#'
	detect_line '# The layout is the setting of the system. The two COMPOSITOR values are what'
	detect_line '# Hyprland is using now, which differs when a session was started by hand.'
	detect_line ''

	detect_timezone
	detect_keyboard
}

# The timezone, from systemd first and from the link the C library reads next.
detect_timezone() {
	local target

	if detect_capture 'the timezone' timedatectl show -p Timezone --value; then
		detect_trim "$DETECT_OUTPUT"
		if [ -n "$DETECT_FIELD" ]; then
			detect_add MACHINE_TIMEZONE "$DETECT_FIELD"
			return 0
		fi
		detect_warn "'timedatectl show -p Timezone --value' answered with nothing"
	fi

	# The second source. /etc/localtime is a link into the zone database, and
	# the part of the path below 'zoneinfo' is the name of the zone.
	if [ -L /etc/localtime ] && command -v readlink >/dev/null 2>&1; then
		target=$(readlink -f /etc/localtime 2>/dev/null || true)
		if [ -n "$target" ] && [ "${target#*/zoneinfo/}" != "$target" ]; then
			detect_add MACHINE_TIMEZONE "${target#*/zoneinfo/}"
			return 0
		fi
	fi

	detect_add MACHINE_TIMEZONE "$FACTS_UNKNOWN"
}

# The keyboard layout of the system, and the layout the compositor is using.
detect_keyboard() {
	local layout=$FACTS_UNKNOWN variant=$FACTS_UNKNOWN
	local model=$FACTS_UNKNOWN options=$FACTS_UNKNOWN
	local compositor_layout compositor_variant

	if detect_capture 'the keyboard layout of the system' localectl status; then
		detect_parse_localectl "$DETECT_OUTPUT"

		detect_localectl_field 'X11 Layout' ''
		layout=$DETECT_FIELD
		if [ -z "$layout" ]; then
			# The console keymap is the same fact under another name, and it is
			# the setting a machine without an X11 layout still carries.
			detect_localectl_field 'VC Keymap' ''
			layout=$DETECT_FIELD
		fi

		detect_localectl_field 'X11 Variant' "$FACTS_NONE"
		variant=$DETECT_FIELD
		detect_localectl_field 'X11 Model' "$FACTS_NONE"
		model=$DETECT_FIELD
		detect_localectl_field 'X11 Options' "$FACTS_NONE"
		options=$DETECT_FIELD
	fi

	detect_getoption input:kb_layout
	compositor_layout=$DETECT_FIELD
	detect_getoption input:kb_variant
	compositor_variant=$DETECT_FIELD

	# The system declares no layout, so the compositor is the only source left.
	if [ -z "$layout" ] || [ "$layout" = "$FACTS_UNKNOWN" ]; then
		layout=$FACTS_UNKNOWN
		if [ "$compositor_layout" != "$FACTS_UNKNOWN" ] && [ "$compositor_layout" != "$FACTS_NONE" ]; then
			layout=$compositor_layout
		fi
	fi

	detect_add MACHINE_KEYBOARD_LAYOUT "$layout"
	detect_add MACHINE_KEYBOARD_VARIANT "$variant"
	detect_add MACHINE_KEYBOARD_MODEL "$model"
	detect_add MACHINE_KEYBOARD_OPTIONS "$options"
	detect_add MACHINE_COMPOSITOR_KB_LAYOUT "$compositor_layout"
	detect_add MACHINE_COMPOSITOR_KB_VARIANT "$compositor_variant"
}

# --- the input devices ------------------------------------------------------

detect_section_input() {
	local keyboards mice

	detect_line ''
	detect_line '# --- Input devices ----------------------------------------------------------'
	detect_line '#'
	detect_line '# The name of a device is the name a per-device Hyprland input rule uses.'
	detect_line '# A pointer whose name holds "touchpad" or "trackpad" is counted as a'
	detect_line '# touchpad, which is how Hyprland itself is configured for one.'
	detect_line ''

	if ! detect_capture 'the input devices' hyprctl devices -j; then
		detect_input_unknown
		return 0
	fi
	if ! json_parse "$DETECT_OUTPUT"; then
		detect_warn "'hyprctl devices -j' did not answer with JSON: $JSON_ERROR"
		detect_input_unknown
		return 0
	fi
	detect_list_size keyboards
	keyboards=$DETECT_FIELD
	detect_list_size mice
	mice=$DETECT_FIELD
	if [ -z "$keyboards" ] && [ -z "$mice" ]; then
		detect_warn "'hyprctl devices -j' did not answer with a list of devices"
		detect_input_unknown
		return 0
	fi

	detect_keyboard_devices
	detect_pointer_devices
	detect_device_count touch MACHINE_TOUCHSCREEN_COUNT
	detect_device_count tablets MACHINE_TABLET_COUNT
	detect_switch_devices
}

detect_input_unknown() {
	detect_add MACHINE_KEYBOARD_DEVICE_COUNT "$FACTS_UNKNOWN"
	detect_add MACHINE_KEYBOARD_DEVICE_MAIN "$FACTS_UNKNOWN"
	detect_add MACHINE_POINTER_COUNT "$FACTS_UNKNOWN"
	detect_add MACHINE_TOUCHPAD_COUNT "$FACTS_UNKNOWN"
	detect_add MACHINE_TOUCHSCREEN_COUNT "$FACTS_UNKNOWN"
	detect_add MACHINE_TABLET_COUNT "$FACTS_UNKNOWN"
	detect_add MACHINE_SWITCH_COUNT "$FACTS_UNKNOWN"
}

# The number of members of one device list.
#
#   detect_device_count LIST KEY
detect_device_count() {
	local list=$1 key=$2
	local count

	detect_list_size "$list"
	count=$DETECT_FIELD

	if [ -z "$count" ]; then
		detect_warn "'hyprctl devices -j' answered without a '$list' list"
		detect_add "$key" "$FACTS_UNKNOWN"
		return 0
	fi

	detect_add "$key" "$count"
}

detect_keyboard_devices() {
	local count
	local index number main=$FACTS_NONE

	detect_list_size keyboards
	count=$DETECT_FIELD

	if [ -z "$count" ]; then
		detect_warn "'hyprctl devices -j' answered without a 'keyboards' list"
		detect_add MACHINE_KEYBOARD_DEVICE_COUNT "$FACTS_UNKNOWN"
		detect_add MACHINE_KEYBOARD_DEVICE_MAIN "$FACTS_UNKNOWN"
		return 0
	fi

	for ((index = 0; index < count; index++)); do
		detect_flag "keyboards.$index.main"
		if [ "$DETECT_FIELD" = yes ]; then
			detect_field "keyboards.$index.name"
			main=$DETECT_FIELD
			break
		fi
	done

	detect_add MACHINE_KEYBOARD_DEVICE_COUNT "$count"
	detect_add MACHINE_KEYBOARD_DEVICE_MAIN "$main"

	for ((index = 0; index < count; index++)); do
		number=$((index + 1))
		detect_field "keyboards.$index.name"
		detect_add "MACHINE_KEYBOARD_DEVICE_${number}_NAME" "$DETECT_FIELD"
		detect_field "keyboards.$index.layout"
		detect_add "MACHINE_KEYBOARD_DEVICE_${number}_LAYOUT" "$DETECT_FIELD"
	done
}

detect_pointer_devices() {
	local count
	local index number name
	local -a touchpads=()

	detect_list_size mice
	count=$DETECT_FIELD

	if [ -z "$count" ]; then
		detect_warn "'hyprctl devices -j' answered without a 'mice' list"
		detect_add MACHINE_POINTER_COUNT "$FACTS_UNKNOWN"
		detect_add MACHINE_TOUCHPAD_COUNT "$FACTS_UNKNOWN"
		return 0
	fi

	for ((index = 0; index < count; index++)); do
		detect_field "mice.$index.name"
		name=$DETECT_FIELD
		# Hyprland lists every pointer under 'mice', so the name is what tells
		# a touchpad from a mouse. It is the same name a per-device Hyprland
		# input rule is written against.
		case ${name,,} in
		*touchpad* | *trackpad*) touchpads+=("$name") ;;
		esac
	done

	detect_add MACHINE_POINTER_COUNT "$count"
	detect_add MACHINE_TOUCHPAD_COUNT "${#touchpads[@]}"

	for ((index = 0; index < count; index++)); do
		number=$((index + 1))
		detect_field "mice.$index.name"
		detect_add "MACHINE_POINTER_${number}_NAME" "$DETECT_FIELD"
	done
	for ((index = 0; index < ${#touchpads[@]}; index++)); do
		number=$((index + 1))
		detect_add "MACHINE_TOUCHPAD_${number}_NAME" "${touchpads[index]}"
	done
}

detect_switch_devices() {
	local count
	local index number

	detect_list_size switches
	count=$DETECT_FIELD

	if [ -z "$count" ]; then
		detect_warn "'hyprctl devices -j' answered without a 'switches' list"
		detect_add MACHINE_SWITCH_COUNT "$FACTS_UNKNOWN"
		return 0
	fi

	detect_add MACHINE_SWITCH_COUNT "$count"

	for ((index = 0; index < count; index++)); do
		number=$((index + 1))
		detect_field "switches.$index.name"
		detect_add "MACHINE_SWITCH_${number}_NAME" "$DETECT_FIELD"
	done
}

# --- the default applications -----------------------------------------------

detect_section_applications() {
	detect_line ''
	detect_line '# --- Default applications ---------------------------------------------------'
	detect_line '#'
	detect_line '# The browser is the desktop entry xdg-settings names. The terminal is the'
	detect_line '# entry TERMINAL or an xdg-terminals.list names. Neither is guessed from the'
	detect_line '# terminal this run happens to be printing to.'
	detect_line ''

	detect_browser
	detect_terminal
}

detect_browser() {
	if ! detect_capture 'the default browser' xdg-settings get default-web-browser; then
		detect_add MACHINE_BROWSER "$FACTS_UNKNOWN"
		return 0
	fi

	detect_trim "$DETECT_OUTPUT"
	if [ -z "$DETECT_FIELD" ]; then
		detect_add MACHINE_BROWSER "$FACTS_NONE"
		return 0
	fi

	detect_add MACHINE_BROWSER "$DETECT_FIELD"
}

# The default terminal.
#
# There is no xdg-settings property for a terminal, so the two sources are the
# TERMINAL variable and the freedesktop default terminal specification. The
# TERM variable is not a source: it names the terminal this run is printing to,
# which during an installation is a virtual console rather than the terminal
# the desktop will use.
detect_terminal() {
	local value=${TERMINAL:-}
	local path

	if [ -n "$value" ]; then
		detect_add MACHINE_TERMINAL "$value"
		return 0
	fi

	detect_terminal_lists
	for path in "${DETECT_TERMINAL_PATHS[@]}"; do
		if detect_first_entry "$path"; then
			detect_add MACHINE_TERMINAL "$DETECT_FIELD"
			return 0
		fi
	done

	detect_warn "no default terminal is declared: TERMINAL is empty and no '$DETECT_TERMINAL_LIST' names one"
	detect_add MACHINE_TERMINAL "$FACTS_UNKNOWN"
}

# Every path that may declare the default terminal, most specific first.
#
# Sets DETECT_TERMINAL_PATHS. The specification looks in the user's config
# directory and then in each system config directory, and in each one it reads
# the list of the current desktop before the list that has no desktop.
detect_terminal_lists() {
	local -a dirs=() names=()
	local home=${XDG_CONFIG_HOME:-} desktop dir name

	DETECT_TERMINAL_PATHS=()

	if [ -z "$home" ] && [ -n "${HOME:-}" ]; then
		home=$HOME/.config
	fi
	if [ -n "$home" ]; then
		dirs+=("$home")
	fi

	local system=${XDG_CONFIG_DIRS:-/etc/xdg}
	local rest=$system
	while [ -n "$rest" ]; do
		dir=${rest%%:*}
		if [ "$dir" = "$rest" ]; then
			rest=
		else
			rest=${rest#*:}
		fi
		if [ -n "$dir" ]; then
			dirs+=("$dir")
		fi
	done

	rest=${XDG_CURRENT_DESKTOP:-}
	while [ -n "$rest" ]; do
		desktop=${rest%%:*}
		if [ "$desktop" = "$rest" ]; then
			rest=
		else
			rest=${rest#*:}
		fi
		if [ -n "$desktop" ]; then
			names+=("${desktop,,}-$DETECT_TERMINAL_LIST")
		fi
	done
	names+=("$DETECT_TERMINAL_LIST")

	for dir in "${dirs[@]}"; do
		for name in "${names[@]}"; do
			DETECT_TERMINAL_PATHS+=("$dir/$name")
		done
	done
}

# The first entry of one list file, into DETECT_FIELD.
#
#   detect_first_entry PATH
#
# A line that is empty or starts with a hash is not an entry. Returns 1 when
# the file does not exist or names no entry.
detect_first_entry() {
	local path=$1 line

	DETECT_FIELD=

	if [ ! -f "$path" ] || [ ! -r "$path" ]; then
		return 1
	fi

	while IFS= read -r line || [ -n "$line" ]; do
		detect_trim "$line"
		line=$DETECT_FIELD
		if [ -z "$line" ] || [[ $line == '#'* ]]; then
			continue
		fi
		DETECT_FIELD=$line
		return 0
	done <"$path"

	DETECT_FIELD=
	return 1
}

# --- the whole run ----------------------------------------------------------

# Read every source and build the document.
#
# The run never fails. A source it cannot read is a warning and an 'unknown'
# value, so the file it produces is well formed on any machine.
detect_all() {
	DETECT_KEYS=()
	DETECT_VALUES=()
	DETECT_WARNINGS=()
	DETECT_WARNED=()

	detect_add "$FACTS_VERSION_KEY" "$FACTS_VERSION"
	detect_section_displays
	detect_section_system
	detect_section_input
	detect_section_applications
}
