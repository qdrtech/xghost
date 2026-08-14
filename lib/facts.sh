#!/usr/bin/env bash
#
# The machine facts file of xghost: where it lives, what it may hold, and how
# it is read.
#
# Machine facts are the second category of ADR 0001. They record what is
# physically true about this computer: the monitors, the keyboard layout, the
# timezone, the display scale, the input devices, and the default browser and
# terminal. 'xghost machine detect' writes the file. The renderer reads it
# beside the theme palette.
#
# The file is a data file, not a script. This module reads it line by line and
# never sources it, so a machine facts file can never run code.
#
# The module prints nothing. It collects every problem in FACTS_ERRORS and
# leaves the reporting to the caller. The format is documented in
# docs/machine-facts.md.

# The include sentinel. A library may be sourced more than once, because two
# modules may each need it. The second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_FACTS_SOURCED:-}" ]; then
	return 0
fi
XGHOST_FACTS_SOURCED=1

# Set by facts_load.
declare -A FACTS_SCALARS=()
FACTS_ERRORS=()

# Set by facts_clean_value and facts_quote_value.
FACTS_CLEANED=
FACTS_CLEAN_CHANGED=no

# Every key of the file starts with this prefix. The prefix is what keeps a
# machine fact and a theme colour in two namespaces, so the renderer can hold
# both in one substitution table and still name a collision.
readonly FACTS_PREFIX=MACHINE_

# A key holds upper case letters, digits and underscores after the prefix.
readonly FACTS_KEY_PATTERN='^MACHINE_[A-Z0-9][A-Z0-9_]*$'

# The version the file declares, and the only version this module reads. A
# later format change raises it, and this module then names a file it cannot
# read rather than guessing at it.
readonly FACTS_VERSION_KEY=MACHINE_FACTS_VERSION
readonly FACTS_VERSION=1

# The two defined values that stand for the absence of a fact. They are told
# apart on purpose: a wrong monitor layout presented as fact is worse than an
# absent one, so detection never invents a plausible value for either case.
#
#   unknown  detection could not read the source at all.
#   none     the source answered, and its answer was that nothing is set.
readonly FACTS_UNKNOWN=unknown
readonly FACTS_NONE=none

# The file name, and the name of the copy that 'machine detect' leaves behind
# when it replaces a file that was already there.
readonly FACTS_DIR_NAME=xghost
readonly FACTS_FILE_NAME=machine.conf
readonly FACTS_PREVIOUS_SUFFIX=.previous

# The mode of the file, and of the copy that sits beside it. The file holds no
# secret and it is read by the renderer, so it is readable by everybody and
# writable by its owner alone. The mode is set by the writer rather than left
# to the umask, so the same run produces the same file on every machine.
#
# The directory that holds the file has no mode of its own here. It is created
# by 'mkdir -p' and its mode follows the umask, which is right: the file is
# read by the renderer running as the same user, and a tight umask is a choice
# of the user that xghost has no reason to widen.
readonly FACTS_FILE_MODE=0644

# The message every caller prints when the file has no home. It is written
# once here, so the command and the renderer name the same three variables.
readonly FACTS_NO_HOME_MESSAGE="cannot find the config directory: HOME, XDG_CONFIG_HOME and XGHOST_CONFIG_HOME are all empty"

# Print the path of the machine facts file.
#
# The file belongs to the user, so it lives in the user's config directory and
# never in the checkout. That is what makes it survive a project update
# untouched: an update replaces the checkout and never writes here.
#
# Returns 1 when the file has no home, and the caller reports
# FACTS_NO_HOME_MESSAGE. The value is printed rather than assigned, so this
# function is safe to call from a command substitution.
#
# Environment:
#   XGHOST_MACHINE_FACTS  The path of the file itself. The tests use this.
#   XGHOST_CONFIG_HOME    The user's config directory.
#   XDG_CONFIG_HOME       The same directory, per the XDG base directory
#                         specification.
facts_path() {
	local base

	if [ -n "${XGHOST_MACHINE_FACTS:-}" ]; then
		printf '%s\n' "$XGHOST_MACHINE_FACTS"
		return 0
	fi

	if [ -n "${XGHOST_CONFIG_HOME:-}" ]; then
		base=$XGHOST_CONFIG_HOME
	elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
		base=$XDG_CONFIG_HOME
	elif [ -n "${HOME:-}" ]; then
		base=$HOME/.config
	else
		return 1
	fi

	printf '%s\n' "$base/$FACTS_DIR_NAME/$FACTS_FILE_NAME"
}

# Read one machine facts file.
#
#   facts_load FILE
#
# Fills FACTS_SCALARS with every declared value. Returns 1 when the file has at
# least one problem, and every problem lands in FACTS_ERRORS. A problem is
# never dropped, so a file with three mistakes reports three lines.
facts_load() {
	local file=$1

	FACTS_SCALARS=()
	FACTS_ERRORS=()

	# A user is invited to edit this file, so a path that is not a file it can
	# read is named for what it is. "It does not exist" sent to somebody whose
	# link points at nothing, or who made a directory of that name, sends them
	# looking for the wrong thing.
	if [ -L "$file" ] && [ ! -e "$file" ]; then
		FACTS_ERRORS+=("the machine facts path is a symbolic link that points at nothing: $file")
		return 1
	fi
	if [ ! -e "$file" ]; then
		FACTS_ERRORS+=("the machine facts file does not exist: $file")
		return 1
	fi
	if [ -d "$file" ]; then
		FACTS_ERRORS+=("the machine facts path is a directory, and it has to be a file: $file")
		return 1
	fi
	if [ ! -f "$file" ]; then
		FACTS_ERRORS+=("the machine facts path is not a regular file: $file")
		return 1
	fi
	if [ ! -r "$file" ]; then
		FACTS_ERRORS+=("the machine facts file cannot be read; check its permissions: $file")
		return 1
	fi

	local -A declared=()
	local line key value lineno=0

	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))

		# Drop the white space at both ends of the line.
		line=${line#"${line%%[![:space:]]*}"}
		line=${line%"${line##*[![:space:]]}"}

		if [ -z "$line" ] || [[ $line == '#'* ]]; then
			continue
		fi

		if [[ ! $line =~ ^([^=]+)=(.*)$ ]]; then
			FACTS_ERRORS+=("line $lineno: expected 'KEY=value', found '$line'")
			continue
		fi
		key=${BASH_REMATCH[1]}
		value=${BASH_REMATCH[2]}

		# Drop the white space around the name and around the value.
		key=${key%"${key##*[![:space:]]}"}
		value=${value#"${value%%[![:space:]]*}"}

		# One pair of quotation marks around the value is allowed, so that a
		# value may carry a leading or a trailing space.
		if [ "${#value}" -ge 2 ] && [ "${value:0:1}" = '"' ] && [ "${value: -1}" = '"' ]; then
			value=${value:1:${#value}-2}
		elif [ "${#value}" -ge 2 ] && [ "${value:0:1}" = "'" ] && [ "${value: -1}" = "'" ]; then
			value=${value:1:${#value}-2}
		fi

		if [[ ! $key =~ $FACTS_KEY_PATTERN ]]; then
			FACTS_ERRORS+=("line $lineno: '$key' is not a machine fact; a key starts with '$FACTS_PREFIX' and then holds upper case letters, digits and underscores")
			continue
		fi
		if [ -z "$value" ]; then
			FACTS_ERRORS+=("line $lineno: '$key' has no value; write '$FACTS_NONE' for a fact that is not set and '$FACTS_UNKNOWN' for one that is not known")
			continue
		fi
		# The writer replaces every control character of a value it detects,
		# and names the key it happened to. This file is a hand-edit surface as
		# well, so the same rule holds for a value a user wrote: a tab inside a
		# value would otherwise pass through into a rendered configuration
		# file. The line is named rather than mended, because mending it in
		# silence would change what the user wrote without telling them.
		if [[ $value == *[[:cntrl:]]* ]]; then
			FACTS_ERRORS+=("line $lineno: the value of '$key' holds a control character, such as a tab; a value is one line of plain text")
			continue
		fi
		if [ -n "${declared[$key]+set}" ]; then
			FACTS_ERRORS+=("line $lineno: '$key' is given more than once")
			continue
		fi

		declared[$key]=$value
		FACTS_SCALARS[$key]=$value
	done <"$file"

	facts_check_version

	[ "${#FACTS_ERRORS[@]}" -eq 0 ]
}

# Check the version the file declares, once every line has been read.
#
# The version is required. A file without it is a file this module cannot place
# in time, and reading it as though it were the current format is the guess
# this project does not make.
facts_check_version() {
	local declared=${FACTS_SCALARS[$FACTS_VERSION_KEY]:-}

	if [ -z "$declared" ]; then
		FACTS_ERRORS+=("the file declares no '$FACTS_VERSION_KEY'. Run 'xghost machine detect' to write it again.")
		return 1
	fi
	if [ "$declared" != "$FACTS_VERSION" ]; then
		FACTS_ERRORS+=("the file declares '$FACTS_VERSION_KEY=$declared', and this version of xghost reads version $FACTS_VERSION. Run 'xghost machine detect' to write it again.")
		return 1
	fi
}

# Replace every control character of one value with a space.
#
#   facts_clean_value VALUE
#
# The file holds one fact per line, so a value that carries a newline or a tab
# would split that line or reach the reader as another value. Sets
# FACTS_CLEANED to the result and FACTS_CLEAN_CHANGED to 'yes' when a character
# was replaced, so the writer can report the key it happened to.
#
# Returns 1 when nothing but space is left, which is a value the file cannot
# carry at all.
facts_clean_value() {
	local value=$1

	FACTS_CLEANED=${value//[[:cntrl:]]/ }
	FACTS_CLEAN_CHANGED=no
	if [ "$FACTS_CLEANED" != "$value" ]; then
		FACTS_CLEAN_CHANGED=yes
	fi

	if [ -z "${FACTS_CLEANED//[[:space:]]/}" ]; then
		return 1
	fi
}

# Print one value as the text that follows the equals sign.
#
#   facts_quote_value VALUE
#
# The reader drops the white space at both ends of a value and drops one pair
# of quotation marks. A value that would lose text to either rule is written
# inside a pair of double quotation marks, so what detection read is what the
# reader reads back.
facts_quote_value() {
	local value=$1
	local first=${value:0:1} last=${value: -1}

	if [ "$first" = ' ' ] || [ "$last" = ' ' ]; then
		printf '"%s"' "$value"
		return 0
	fi
	if [ "${#value}" -ge 2 ] && [ "$first" = "$last" ] &&
		{ [ "$first" = '"' ] || [ "$first" = "'" ]; }; then
		printf '"%s"' "$value"
		return 0
	fi

	printf '%s' "$value"
}
