#!/usr/bin/env bash
#
# The knobs of xghost: the schema the project owns, the file the user edits,
# and how the two are read.
#
# Knobs are the third file category of ADR 0001. They are the preferences this
# desktop supports: a defined set, not a free-form override surface. The project
# owns the schema, which names every knob, the values that knob takes, and the
# value a machine takes when its own file names none. The user owns the file,
# and the project refuses a value the schema does not name.
#
# Two files, and neither one is a script. This module reads both line by line
# and never sources either, so neither can ever run code.
#
# The module prints nothing. It collects every problem in KNOBS_ERRORS and
# leaves the reporting to the caller. Both formats are documented in
# docs/knobs.md.

# The include sentinel. A library may be sourced more than once, because two
# modules may each need it. The second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_KNOBS_SOURCED:-}" ]; then
	return 0
fi
XGHOST_KNOBS_SOURCED=1

# Set by knobs_schema_load. KNOBS_NAMES holds every knob in the order the
# schema declares it, so 'xghost settings list' prints them in an order a
# person chose rather than in the order a hash table walks its keys.
#
# KNOBS_VALUES holds the allowed values of one knob, one per line. A value
# carries no control character, so a newline can separate them.
KNOBS_NAMES=()
declare -A KNOBS_SUMMARY=()
declare -A KNOBS_VALUES=()
declare -A KNOBS_DEFAULT=()

# Set by knobs_load. KNOBS_SCALARS holds the effective value of every knob: the
# value the user's file declares, or the default of the schema. Every knob is
# therefore always in the table, which is what lets a template name a knob that
# no knobs file mentions.
#
# KNOBS_DECLARED records which of them the user's file names, so a caller can
# tell a value that was chosen from a value that was never touched.
declare -A KNOBS_SCALARS=()
declare -A KNOBS_DECLARED=()

# Set by both readers.
KNOBS_ERRORS=()

# Set by knobs_write.
KNOBS_PROBLEM=

# Every knob key starts with this prefix. The prefix is what keeps a knob, a
# machine fact and a theme colour in three namespaces, so the renderer can hold
# all three in one substitution table and still name a collision.
readonly KNOBS_PREFIX=KNOB_

# A knob key holds upper case letters, digits and underscores after the prefix.
readonly KNOBS_KEY_PATTERN='^KNOB_[A-Z0-9][A-Z0-9_]*$'

# The fields of one schema record. 'knob' opens a record, 'value' repeats once
# per allowed value, and the other two are given once each.
readonly KNOBS_SCHEMA_FIELDS="'knob', 'summary', 'value' and 'default'"

# The file name of the knobs, and the directory that holds it.
readonly KNOBS_DIR_NAME=xghost
readonly KNOBS_FILE_NAME=knobs.conf

# The mode of the knobs file. The file holds no secret and it is read by the
# renderer, so it is readable by everybody and writable by its owner alone. The
# mode is set by the writer rather than left to the umask, so 'xghost settings
# set' produces the same file on every machine.
readonly KNOBS_FILE_MODE=0644

# The message every caller prints when the file has no home. It is written once
# here, so the commands and the renderer name the same three variables.
readonly KNOBS_NO_HOME_MESSAGE="cannot find the config directory: HOME, XDG_CONFIG_HOME and XGHOST_CONFIG_HOME are all empty"

# Print the path of the knobs file.
#
# The file belongs to the user, so it lives in the user's config directory and
# never in the checkout. That is what makes it survive a project update
# untouched: an update replaces the checkout and never writes here.
#
# Returns 1 when the file has no home, and the caller reports
# KNOBS_NO_HOME_MESSAGE. The value is printed rather than assigned, so this
# function is safe to call from a command substitution.
#
# Environment:
#   XGHOST_KNOBS_FILE   The path of the file itself. The tests use this.
#   XGHOST_CONFIG_HOME  The user's config directory.
#   XDG_CONFIG_HOME     The same directory, per the XDG base directory
#                       specification.
knobs_path() {
	local base

	if [ -n "${XGHOST_KNOBS_FILE:-}" ]; then
		printf '%s\n' "$XGHOST_KNOBS_FILE"
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

	printf '%s\n' "$base/$KNOBS_DIR_NAME/$KNOBS_FILE_NAME"
}

# Check that one path is a file this module can read.
#
#   knobs_readable FILE LABEL
#
# A user is invited to edit the knobs file, so a path that is not a readable
# file is named for what it is. "It does not exist" sent to somebody whose link
# points at nothing, or who made a directory of that name, sends them looking
# for the wrong thing.
#
# Returns 1 and appends one problem to KNOBS_ERRORS.
knobs_readable() {
	local file=$1 label=$2

	if [ -L "$file" ] && [ ! -e "$file" ]; then
		KNOBS_ERRORS+=("$label is a symbolic link that points at nothing: $file")
		return 1
	fi
	if [ ! -e "$file" ]; then
		KNOBS_ERRORS+=("$label does not exist: $file")
		return 1
	fi
	if [ -d "$file" ]; then
		KNOBS_ERRORS+=("$label is a directory, and it has to be a file: $file")
		return 1
	fi
	if [ ! -f "$file" ]; then
		KNOBS_ERRORS+=("$label is not a regular file: $file")
		return 1
	fi
	if [ ! -r "$file" ]; then
		KNOBS_ERRORS+=("$label cannot be read; check its permissions: $file")
		return 1
	fi
}

# Split one line of a data file into KNOBS_KEY and KNOBS_VALUE.
#
#   knobs_split_line LINE
#
# The white space at both ends of the line, of the name and of the value is
# dropped, and one pair of quotation marks around the value is dropped, exactly
# as the palette and the machine facts do it.
#
# Returns 1 when the line is empty or a comment, and 2 when it is neither of
# those and not 'KEY=value' either.
KNOBS_KEY=
KNOBS_VALUE=
knobs_split_line() {
	local line=$1

	KNOBS_KEY=
	KNOBS_VALUE=

	line=${line#"${line%%[![:space:]]*}"}
	line=${line%"${line##*[![:space:]]}"}

	if [ -z "$line" ] || [[ $line == '#'* ]]; then
		return 1
	fi
	if [[ ! $line =~ ^([^=]+)=(.*)$ ]]; then
		return 2
	fi

	KNOBS_KEY=${BASH_REMATCH[1]}
	KNOBS_VALUE=${BASH_REMATCH[2]}

	KNOBS_KEY=${KNOBS_KEY%"${KNOBS_KEY##*[![:space:]]}"}
	KNOBS_VALUE=${KNOBS_VALUE#"${KNOBS_VALUE%%[![:space:]]*}"}
	KNOBS_VALUE=${KNOBS_VALUE%"${KNOBS_VALUE##*[![:space:]]}"}

	if [ "${#KNOBS_VALUE}" -ge 2 ] &&
		{ { [ "${KNOBS_VALUE:0:1}" = '"' ] && [ "${KNOBS_VALUE: -1}" = '"' ]; } ||
			{ [ "${KNOBS_VALUE:0:1}" = "'" ] && [ "${KNOBS_VALUE: -1}" = "'" ]; }; }; then
		KNOBS_VALUE=${KNOBS_VALUE:1:${#KNOBS_VALUE}-2}
	fi
}

# Read the knob schema.
#
#   knobs_schema_load FILE
#
# The schema is one record per knob. A record starts with a 'knob' line and
# holds 'summary' once, 'value' once per allowed value, and 'default' once:
#
#   knob=KNOB_ANIMATIONS
#   summary=Whether a window animates.
#   value=on
#   value=off
#   default=on
#
# Every knob is chosen from a list the schema writes out. There is no range and
# no pattern, so validation is exact membership of that list and a graphical
# manager reads the same list as a set of choices.
#
# Fills KNOBS_NAMES, KNOBS_SUMMARY, KNOBS_VALUES and KNOBS_DEFAULT. Returns 1
# when the schema has at least one problem, and every problem lands in
# KNOBS_ERRORS. A problem is never dropped, so a schema with three mistakes
# reports three lines.
knobs_schema_load() {
	local file=$1

	KNOBS_NAMES=()
	KNOBS_SUMMARY=()
	KNOBS_VALUES=()
	KNOBS_DEFAULT=()
	KNOBS_ERRORS=()

	if ! knobs_readable "$file" 'the knob schema'; then
		return 1
	fi

	local -A declared=()
	local line key value current= refused=0 lineno=0 status name

	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))

		status=0
		knobs_split_line "$line" || status=$?
		if [ "$status" -eq 1 ]; then
			continue
		fi
		if [ "$status" -eq 2 ]; then
			KNOBS_ERRORS+=("the schema, line $lineno: expected 'field=value', found '$line'")
			continue
		fi
		key=$KNOBS_KEY
		value=$KNOBS_VALUE

		if [[ $value == *[[:cntrl:]]* ]]; then
			KNOBS_ERRORS+=("the schema, line $lineno: the value of '$key' holds a control character, such as a tab; a value is one line of plain text")
			continue
		fi
		if [ -z "$value" ]; then
			KNOBS_ERRORS+=("the schema, line $lineno: '$key' has no value")
			continue
		fi

		case $key in
		knob)
			# A refused record is named once, at its 'knob' line. Its fields are
			# then passed over, because one mistake is one report: naming each
			# of its four lines as well would bury the line to correct.
			current=
			refused=1
			if [[ ! $value =~ $KNOBS_KEY_PATTERN ]]; then
				KNOBS_ERRORS+=("the schema, line $lineno: '$value' is not a knob name; a name starts with '$KNOBS_PREFIX' and then holds upper case letters, digits and underscores")
				continue
			fi
			if [ -n "${declared[$value]+set}" ]; then
				KNOBS_ERRORS+=("the schema, line $lineno: '$value' is declared more than once")
				continue
			fi
			declared[$value]=1
			current=$value
			refused=0
			KNOBS_NAMES+=("$value")
			KNOBS_SUMMARY[$value]=
			KNOBS_VALUES[$value]=
			KNOBS_DEFAULT[$value]=
			;;
		summary | value | default)
			if [ -z "$current" ]; then
				if [ "$refused" -eq 0 ]; then
					KNOBS_ERRORS+=("the schema, line $lineno: '$key' belongs to no knob; a record starts with a 'knob' line")
				fi
				continue
			fi
			# A value is written back into the knobs file by 'xghost settings
			# set', and read from it again. A value that would lose text to the
			# rules of that reader could never make the round trip, so it is
			# refused here rather than written out and read back as something
			# else.
			if [ "$value" != "${value#[[:space:]]}" ] || [ "$value" != "${value%[[:space:]]}" ]; then
				KNOBS_ERRORS+=("the schema, line $lineno: the value of '$key' starts or ends with a space, and a knob value cannot")
				continue
			fi
			if [ "${#value}" -ge 2 ] && [ "${value:0:1}" = "${value: -1}" ] &&
				{ [ "${value:0:1}" = '"' ] || [ "${value:0:1}" = "'" ]; }; then
				KNOBS_ERRORS+=("the schema, line $lineno: the value of '$key' is wrapped in quotation marks, and a knob value cannot be")
				continue
			fi
			case $key in
			summary)
				if [ -n "${KNOBS_SUMMARY[$current]}" ]; then
					KNOBS_ERRORS+=("the schema, line $lineno: '$current' declares more than one 'summary'")
					continue
				fi
				KNOBS_SUMMARY[$current]=$value
				;;
			value)
				if knobs_allows "$current" "$value"; then
					KNOBS_ERRORS+=("the schema, line $lineno: '$current' declares the value '$value' more than once")
					continue
				fi
				if [ -z "${KNOBS_VALUES[$current]}" ]; then
					KNOBS_VALUES[$current]=$value
				else
					KNOBS_VALUES[$current]=${KNOBS_VALUES[$current]}$'\n'$value
				fi
				;;
			default)
				if [ -n "${KNOBS_DEFAULT[$current]}" ]; then
					KNOBS_ERRORS+=("the schema, line $lineno: '$current' declares more than one 'default'")
					continue
				fi
				KNOBS_DEFAULT[$current]=$value
				;;
			esac
			;;
		*)
			KNOBS_ERRORS+=("the schema, line $lineno: '$key' is not a field of the schema; the fields are $KNOBS_SCHEMA_FIELDS")
			;;
		esac
	done <"$file"

	# Every record is complete, and its default is one of its own values. A
	# knob whose default names nothing would leave a machine with no knobs file
	# holding a value the project refuses in that file.
	for name in ${KNOBS_NAMES[@]+"${KNOBS_NAMES[@]}"}; do
		if [ -z "${KNOBS_SUMMARY[$name]}" ]; then
			KNOBS_ERRORS+=("the schema: '$name' declares no 'summary'")
		fi
		if [ -z "${KNOBS_VALUES[$name]}" ]; then
			# The default is not checked against a list that is not there. One
			# mistake is one report.
			KNOBS_ERRORS+=("the schema: '$name' declares no 'value', and a knob is chosen from the values the schema names")
		elif [ -z "${KNOBS_DEFAULT[$name]}" ]; then
			KNOBS_ERRORS+=("the schema: '$name' declares no 'default'")
		elif ! knobs_allows "$name" "${KNOBS_DEFAULT[$name]}"; then
			KNOBS_ERRORS+=("the schema: '$name' defaults to '${KNOBS_DEFAULT[$name]}', which is not one of its values. It takes $(knobs_format_values "$name").")
		fi
	done

	if [ "${#KNOBS_NAMES[@]}" -eq 0 ] && [ "${#KNOBS_ERRORS[@]}" -eq 0 ]; then
		KNOBS_ERRORS+=("the schema declares no knob: $file")
	fi

	[ "${#KNOBS_ERRORS[@]}" -eq 0 ]
}

# Return 0 when one value is one of the values a knob takes.
#
#   knobs_allows NAME VALUE
#
# The values are compared one by one rather than searched inside one string, so
# a value that holds a space, such as a font family, is matched exactly.
knobs_allows() {
	local name=$1 value=$2
	local allowed

	# A name that is not one is not an array subscript either, and an empty
	# subscript is a raw diagnostic of the shell rather than an answer.
	[ -n "$name" ] || return 1
	[ -n "${KNOBS_VALUES[$name]:-}" ] || return 1

	while IFS= read -r allowed; do
		if [ "$allowed" = "$value" ]; then
			return 0
		fi
	done <<<"${KNOBS_VALUES[$name]}"

	return 1
}

# Print the values one knob takes, as a list a person reads.
#
#   knobs_format_values NAME
#
# Each value is quoted, because a value may hold a space.
knobs_format_values() {
	local name=$1
	local allowed out=

	[ -n "$name" ] || return 0

	while IFS= read -r allowed; do
		[ -n "$allowed" ] || continue
		if [ -n "$out" ]; then
			out="$out, "
		fi
		out="$out'$allowed'"
	done <<<"${KNOBS_VALUES[$name]:-}"

	printf '%s' "$out"
}

# Read the schema and the knobs file, and fill in the effective values.
#
#   knobs_load SCHEMA_FILE KNOBS_FILE
#
# Fills KNOBS_SCALARS with every knob the schema declares: the value the knobs
# file gives it, or the default of the schema. KNOBS_DECLARED records which of
# them the knobs file names.
#
# An empty KNOBS_FILE means "absent", which is what a machine that has never run
# 'xghost settings set' passes. Every knob then takes its default, so a fresh
# machine renders and a knob added by a later version of xghost reaches an old
# knobs file as its default rather than as a failure.
#
# An empty SCHEMA_FILE means "no knob is declared at all". It is how a caller
# renders with the theme palette and the machine facts alone.
#
# A knob the schema does not name is refused rather than passed through. That is
# what makes this a supported preference surface instead of a free-form override
# surface: ADR 0001 records the decision.
#
# Returns 1 when either file has at least one problem, and every problem lands
# in KNOBS_ERRORS.
knobs_load() {
	local schema_file=$1 knobs_file=$2
	local name

	KNOBS_SCALARS=()
	KNOBS_DECLARED=()
	KNOBS_ERRORS=()

	if [ -z "$schema_file" ]; then
		KNOBS_NAMES=()
		KNOBS_SUMMARY=()
		KNOBS_VALUES=()
		KNOBS_DEFAULT=()
		# Without the schema there is nothing to validate a knobs file against,
		# and reading it as though every value were allowed is the guess this
		# project does not make.
		if [ -n "$knobs_file" ]; then
			KNOBS_ERRORS+=("no knob schema was given, so the knobs file cannot be read: $knobs_file")
			return 1
		fi
		return 0
	fi

	if ! knobs_schema_load "$schema_file"; then
		return 1
	fi

	for name in ${KNOBS_NAMES[@]+"${KNOBS_NAMES[@]}"}; do
		KNOBS_SCALARS[$name]=${KNOBS_DEFAULT[$name]}
	done

	if [ -z "$knobs_file" ]; then
		return 0
	fi

	if ! knobs_readable "$knobs_file" 'the knobs file'; then
		return 1
	fi

	local -A seen=()
	local line key value lineno=0 status

	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))

		status=0
		knobs_split_line "$line" || status=$?
		if [ "$status" -eq 1 ]; then
			continue
		fi
		if [ "$status" -eq 2 ]; then
			KNOBS_ERRORS+=("line $lineno: expected 'KNOB_NAME=value', found '$line'")
			continue
		fi
		key=$KNOBS_KEY
		value=$KNOBS_VALUE

		if [[ ! $key =~ $KNOBS_KEY_PATTERN ]]; then
			KNOBS_ERRORS+=("line $lineno: '$key' is not a knob; a knob starts with '$KNOBS_PREFIX' and then holds upper case letters, digits and underscores")
			continue
		fi
		if [ -z "${KNOBS_DEFAULT[$key]+set}" ]; then
			KNOBS_ERRORS+=("line $lineno: '$key' is not a knob this version of xghost has. Run 'xghost settings list' for every knob it has.")
			continue
		fi
		if [ -n "${seen[$key]+set}" ]; then
			KNOBS_ERRORS+=("line $lineno: '$key' is given more than once")
			continue
		fi
		if [[ $value == *[[:cntrl:]]* ]]; then
			KNOBS_ERRORS+=("line $lineno: the value of '$key' holds a control character, such as a tab; a value is one line of plain text")
			continue
		fi
		if ! knobs_allows "$key" "$value"; then
			KNOBS_ERRORS+=("line $lineno: '$value' is not a value of '$key'. It takes $(knobs_format_values "$key").")
			continue
		fi

		seen[$key]=1
		KNOBS_DECLARED[$key]=1
		KNOBS_SCALARS[$key]=$value
	done <"$knobs_file"

	[ "${#KNOBS_ERRORS[@]}" -eq 0 ]
}

# Write one knob into the knobs file.
#
#   knobs_write FILE NAME VALUE
#
# The file is human-edited, so the writer keeps every other line exactly as it
# is: the comments a user wrote, the order they chose, and every other knob. The
# line that declares this knob is replaced where it stands, and a knob the file
# does not yet name is appended. A file that does not exist is created with a
# header that says who owns it.
#
# The write is atomic. The new file is built beside the old one and moved onto
# it in one rename, so an interrupted write leaves the previous file whole.
#
# The caller has read the file with knobs_load already, so no line of it is
# invalid and no knob is declared twice.
#
# Returns 1 and sets KNOBS_PROBLEM when the file is not written.
knobs_write() {
	local file=$1 name=$2 value=$3
	local dir=${file%/*}
	local temp line replaced=0 status

	KNOBS_PROBLEM=

	if [ "$dir" = "$file" ]; then
		dir=.
	fi
	if ! mkdir -p "$dir" 2>/dev/null; then
		KNOBS_PROBLEM="cannot create the directory that holds the knobs: $dir"
		return 1
	fi

	if ! temp=$(mktemp "$file.XXXXXXXX" 2>/dev/null); then
		KNOBS_PROBLEM="cannot create a temporary file beside the knobs: $file"
		return 1
	fi

	{
		if [ -f "$file" ]; then
			while IFS= read -r line || [ -n "$line" ]; do
				status=0
				knobs_split_line "$line" || status=$?
				if [ "$status" -eq 0 ] && [ "$KNOBS_KEY" = "$name" ]; then
					printf '%s=%s\n' "$name" "$value"
					replaced=1
					continue
				fi
				printf '%s\n' "$line"
			done <"$file"
		else
			knobs_header
		fi
		if [ "$replaced" -eq 0 ]; then
			printf '%s=%s\n' "$name" "$value"
		fi
	} 2>/dev/null >"$temp" || {
		rm -f "$temp" 2>/dev/null
		KNOBS_PROBLEM="cannot write the knobs: $file"
		return 1
	}

	if ! chmod "$KNOBS_FILE_MODE" "$temp" 2>/dev/null; then
		rm -f "$temp" 2>/dev/null
		KNOBS_PROBLEM="cannot set the mode of the knobs: $file"
		return 1
	fi
	if ! mv -f "$temp" "$file" 2>/dev/null; then
		rm -f "$temp" 2>/dev/null
		KNOBS_PROBLEM="cannot move the new knobs into place: $file"
		return 1
	fi
}

# The header of a knobs file this module creates.
knobs_header() {
	cat <<-'EOF'
		# The knobs of xghost: the preferences this desktop supports.
		#
		# You own this file. An xghost update replaces the checkout and never
		# writes here, so every value below survives every update.
		#
		#   xghost settings list              every knob, its value, its values
		#   xghost settings set KNOB VALUE    change one knob and render again
		#
		# One 'KNOB_NAME=value' pair per line. A knob this file does not name
		# takes the default of the schema the project owns, so an absent line
		# and the default are the same thing. docs/knobs.md documents the format.

	EOF
}
