#!/usr/bin/env bash
#
# The JSON reader of the xghost detection.
#
# Hyprland answers 'hyprctl monitors -j' and 'hyprctl devices -j' in JSON, and
# xghost has to read that answer without adding a dependency. This module reads
# JSON in bash alone. It runs nothing and expands nothing, so text from a
# program can never become code.
#
# The reader is a pure function. It takes one string and fills three
# associative arrays. It reads no file, runs no program, and prints nothing.
#
# The result is flat. Every scalar of the document lands in JSON_VALUE under a
# path, every object and array lands in JSON_SIZE under the same path with the
# number of its members, and every value of either sort lands in JSON_KIND
# under the name of what it is: 'string', 'number', 'literal', 'object' or
# 'array'. A path joins its parts with a full stop, an array member is named by
# its index counted from zero, and the whole document is the path JSON_ROOT,
# which is one full stop.
#
#   [{"name": "DP-2", "reserved": [0, 63]}]
#
#   JSON_KIND["."]             array
#   JSON_SIZE["."]             1
#   JSON_KIND["0"]             object
#   JSON_SIZE["0"]             2
#   JSON_VALUE["0.name"]       DP-2
#   JSON_KIND["0.name"]        string
#   JSON_KIND["0.reserved"]    array
#   JSON_SIZE["0.reserved"]    2
#   JSON_VALUE["0.reserved.0"] 0
#
# JSON_KIND is what tells the literal null from the string "null", and the
# array from the object. A caller that reads JSON_VALUE alone cannot tell the
# answer "this member has no value" from the answer "this member is the word
# null", and it would write the second one into a configuration file as though
# a program had reported it.
#
# A path is therefore ambiguous for a document whose member name holds a full
# stop or looks like an index. Neither hyprctl answer holds such a name, and
# this module is for those answers.
#
# What the reader accepts is RFC 8259 with four limits, and it names each one
# rather than reading past it:
#
#   - A document longer than JSON_MAX_BYTES is refused. The scan is quadratic,
#     as the next paragraph explains, and the answers this module reads are a
#     few kilobytes.
#   - A document nested deeper than JSON_MAX_DEPTH levels is refused. The
#     answers this module reads are three levels deep.
#   - A string that holds the escape for the code point zero is refused,
#     because bash cannot hold a NUL byte in a variable.
#   - A member name that is empty is refused, because every value is named by a
#     path and bash has no empty array subscript.
#
# The scan is quadratic in the length of the document, not linear. Bash indexes
# a string by character rather than by byte offset, so '${text:i:1}' walks the
# string from its start, and appending one character to a result copies that
# result. Doubling the input multiplies the time by about four. That is what
# JSON_MAX_BYTES is for: a document far larger than the answers this module
# exists for is refused by name rather than ground through for minutes.
#
# A member name given twice keeps the value that comes last, and everything the
# earlier name recorded is forgotten, so no part of the value it replaced is
# left behind.

# The include sentinel. A library may be sourced more than once, because two
# modules may each need it. The second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_JSON_SOURCED:-}" ]; then
	return 0
fi
XGHOST_JSON_SOURCED=1

# Set by json_parse.
declare -A JSON_VALUE=()
declare -A JSON_SIZE=()
declare -A JSON_KIND=()
JSON_ERROR=

# The reading position and the text being read. They are the state of the
# recursive descent below, and no caller reads them.
JSON_TEXT=
JSON_LEN=0
JSON_POS=0
JSON_STR=
JSON_CODE=0

# The path of the whole document. A child path never equals it and never
# starts with a full stop, so the two can never be confused. Bash refuses an
# empty subscript, which is why the root carries a name of its own.
readonly JSON_ROOT=.

# The deepest nesting the reader accepts, counted in levels. The whole document
# is level 1, a member of it is level 2, and '[{"name": "DP-2"}]' is three
# levels deep. A document deeper than this is refused by name rather than read,
# so a malformed answer cannot drive the recursion until bash runs out of
# stack.
readonly JSON_MAX_DEPTH=32

# The longest document the reader accepts, in bytes. The scan is quadratic, so
# a document far larger than the answers this module reads would take minutes
# rather than fail. It is refused by name instead. 'hyprctl monitors -j' on a
# machine with four monitors is about eight kilobytes, so this limit is far
# above anything the reader meets.
readonly JSON_MAX_BYTES=262144

# A JSON number, as RFC 8259 defines it.
readonly JSON_NUMBER_PATTERN='^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$'

# The first and the last code point of each half of a surrogate pair.
readonly JSON_HIGH_FIRST=55296 # 0xD800
readonly JSON_HIGH_LAST=56319  # 0xDBFF
readonly JSON_LOW_FIRST=56320  # 0xDC00
readonly JSON_LOW_LAST=57343   # 0xDFFF

# Read one JSON document.
#
#   json_parse TEXT
#
# Fills JSON_VALUE, JSON_SIZE and JSON_KIND. Returns 1 when the text is not one
# JSON document, and names the problem with its byte offset in JSON_ERROR.
json_parse() {
	# The C locale makes every index of this module a byte index, so every
	# offset this module reports is a byte offset and a UTF-8 sequence passes
	# through whole rather than through a locale that may not hold it. It does
	# not make the scan linear; read the head of this file for the cost.
	local LC_ALL=C

	JSON_VALUE=()
	JSON_SIZE=()
	JSON_KIND=()
	JSON_ERROR=
	JSON_TEXT=$1
	JSON_LEN=${#JSON_TEXT}
	JSON_POS=0

	if [ "$JSON_LEN" -gt "$JSON_MAX_BYTES" ]; then
		JSON_ERROR="the document is $JSON_LEN bytes, and this reader accepts $JSON_MAX_BYTES"
		return 1
	fi

	json_skip_space
	if ! json_read_value "$JSON_ROOT" 0; then
		return 1
	fi
	json_skip_space

	if [ "$JSON_POS" -lt "$JSON_LEN" ]; then
		JSON_ERROR="offset $JSON_POS: text follows the end of the document"
		return 1
	fi
}

# Step over the white space JSON allows between two tokens.
json_skip_space() {
	local c
	while [ "$JSON_POS" -lt "$JSON_LEN" ]; do
		c=${JSON_TEXT:JSON_POS:1}
		case $c in
		' ' | $'\t' | $'\n' | $'\r') JSON_POS=$((JSON_POS + 1)) ;;
		*) return 0 ;;
		esac
	done
}

# Read one value and record it under one path.
#
#   json_read_value PATH DEPTH
#
# DEPTH is the number of values this one is inside, so the whole document has
# depth 0 and stands at level 1.
json_read_value() {
	local path=$1 depth=$2 c

	if [ "$depth" -ge "$JSON_MAX_DEPTH" ]; then
		JSON_ERROR="offset $JSON_POS: the document nests deeper than $JSON_MAX_DEPTH levels"
		return 1
	fi
	if [ "$JSON_POS" -ge "$JSON_LEN" ]; then
		JSON_ERROR="offset $JSON_POS: a value was expected, and the text ends"
		return 1
	fi

	c=${JSON_TEXT:JSON_POS:1}
	case $c in
	'{')
		json_read_object "$path" "$depth"
		;;
	'[')
		json_read_array "$path" "$depth"
		;;
	'"')
		if ! json_read_string; then
			return 1
		fi
		JSON_VALUE[$path]=$JSON_STR
		JSON_KIND[$path]=string
		;;
	t | f | n)
		json_read_literal "$path"
		;;
	*)
		json_read_number "$path"
		;;
	esac
}

# Read 'true', 'false' or 'null'.
#
# The kind is recorded as 'literal', which is what tells the value null from a
# string that holds the four letters of the word.
json_read_literal() {
	local path=$1 word

	for word in true false null; do
		if [ "${JSON_TEXT:JSON_POS:${#word}}" = "$word" ]; then
			JSON_VALUE[$path]=$word
			JSON_KIND[$path]=literal
			JSON_POS=$((JSON_POS + ${#word}))
			return 0
		fi
	done

	JSON_ERROR="offset $JSON_POS: '${JSON_TEXT:JSON_POS:8}' is not a JSON value"
	return 1
}

# Read a number, and keep the digits exactly as the document wrote them.
json_read_number() {
	local path=$1 start=$JSON_POS c text

	while [ "$JSON_POS" -lt "$JSON_LEN" ]; do
		c=${JSON_TEXT:JSON_POS:1}
		case $c in
		[-+.0-9eE]) JSON_POS=$((JSON_POS + 1)) ;;
		*) break ;;
		esac
	done

	if [ "$JSON_POS" -eq "$start" ]; then
		JSON_ERROR="offset $start: '${JSON_TEXT:start:8}' is not a JSON value"
		return 1
	fi

	text=${JSON_TEXT:start:JSON_POS - start}
	if [[ ! $text =~ $JSON_NUMBER_PATTERN ]]; then
		JSON_ERROR="offset $start: '$text' is not a JSON number"
		return 1
	fi

	JSON_VALUE[$path]=$text
	JSON_KIND[$path]=number
}

# Read a string and leave it in JSON_STR, with every escape resolved.
json_read_string() {
	local out= c

	JSON_STR=
	JSON_POS=$((JSON_POS + 1))

	while :; do
		if [ "$JSON_POS" -ge "$JSON_LEN" ]; then
			JSON_ERROR="offset $JSON_POS: the text ends inside a string"
			return 1
		fi
		c=${JSON_TEXT:JSON_POS:1}
		JSON_POS=$((JSON_POS + 1))

		case $c in
		'"')
			JSON_STR=$out
			return 0
			;;
		\\)
			if ! json_read_escape; then
				return 1
			fi
			out=$out$JSON_STR
			;;
		*)
			out=$out$c
			;;
		esac
	done
}

# Read the character that follows a backslash inside a string, and leave the
# text it stands for in JSON_STR.
json_read_escape() {
	local c high low

	if [ "$JSON_POS" -ge "$JSON_LEN" ]; then
		JSON_ERROR="offset $JSON_POS: the text ends inside an escape"
		return 1
	fi
	c=${JSON_TEXT:JSON_POS:1}
	JSON_POS=$((JSON_POS + 1))

	case $c in
	'"') JSON_STR='"' ;;
	\\) JSON_STR=\\ ;;
	/) JSON_STR=/ ;;
	b) JSON_STR=$'\b' ;;
	f) JSON_STR=$'\f' ;;
	n) JSON_STR=$'\n' ;;
	r) JSON_STR=$'\r' ;;
	t) JSON_STR=$'\t' ;;
	u)
		if ! json_read_hex4; then
			return 1
		fi
		high=$JSON_CODE
		if [ "$high" -ge "$JSON_HIGH_FIRST" ] && [ "$high" -le "$JSON_HIGH_LAST" ]; then
			if [ "${JSON_TEXT:JSON_POS:2}" != '\u' ]; then
				JSON_ERROR="offset $JSON_POS: a high surrogate is not followed by a low one"
				return 1
			fi
			JSON_POS=$((JSON_POS + 2))
			if ! json_read_hex4; then
				return 1
			fi
			low=$JSON_CODE
			if [ "$low" -lt "$JSON_LOW_FIRST" ] || [ "$low" -gt "$JSON_LOW_LAST" ]; then
				JSON_ERROR="offset $((JSON_POS - 4)): a high surrogate is followed by a value that is not a low surrogate"
				return 1
			fi
			high=$((65536 + (high - JSON_HIGH_FIRST) * 1024 + (low - JSON_LOW_FIRST)))
		elif [ "$high" -ge "$JSON_LOW_FIRST" ] && [ "$high" -le "$JSON_LOW_LAST" ]; then
			# A low surrogate means nothing on its own. Encoding it as a code
			# point of its own produces CESU-8, which is not UTF-8, and this
			# reader would then hand a caller bytes it cannot write to a file.
			JSON_ERROR="offset $((JSON_POS - 6)): a low surrogate stands on its own, with no high surrogate before it"
			return 1
		fi
		if [ "$high" -eq 0 ]; then
			JSON_ERROR="offset $((JSON_POS - 6)): the string holds '\\u0000', and bash cannot hold a NUL byte"
			return 1
		fi
		json_utf8 "$high"
		;;
	*)
		JSON_ERROR="offset $((JSON_POS - 2)): '\\$c' is not a JSON escape"
		return 1
		;;
	esac
}

# Write one code point into JSON_STR as its UTF-8 bytes.
#
#   json_utf8 CODE
#
# The bytes are built here rather than by the '\u' conversion of printf,
# because that conversion answers with the escape unchanged in a locale that
# has no multibyte character. This reader runs in the C locale, and a document
# that holds the same character as raw UTF-8 must read back as the same bytes.
json_utf8() {
	local code=$1 bytes

	if [ "$code" -lt 128 ]; then
		printf -v bytes '\\x%02x' "$code"
	elif [ "$code" -lt 2048 ]; then
		printf -v bytes '\\x%02x\\x%02x' \
			"$((192 | (code >> 6)))" "$((128 | (code & 63)))"
	elif [ "$code" -lt 65536 ]; then
		printf -v bytes '\\x%02x\\x%02x\\x%02x' \
			"$((224 | (code >> 12)))" "$((128 | ((code >> 6) & 63)))" \
			"$((128 | (code & 63)))"
	else
		printf -v bytes '\\x%02x\\x%02x\\x%02x\\x%02x' \
			"$((240 | (code >> 18)))" "$((128 | ((code >> 12) & 63)))" \
			"$((128 | ((code >> 6) & 63)))" "$((128 | (code & 63)))"
	fi

	printf -v JSON_STR '%b' "$bytes"
}

# Read the four hexadecimal digits of a '\u' escape into JSON_CODE.
json_read_hex4() {
	local hex=${JSON_TEXT:JSON_POS:4}

	if [[ ! $hex =~ ^[0-9a-fA-F]{4}$ ]]; then
		JSON_ERROR="offset $JSON_POS: '$hex' is not the four hexadecimal digits of a '\\u' escape"
		return 1
	fi

	JSON_POS=$((JSON_POS + 4))
	JSON_CODE=$((16#$hex))
}

# Forget every path one member recorded.
#
#   json_forget PATH
#
# The path itself goes, and so does every path below it, because the member
# being forgotten may have been an object or an array with members of its own.
# This is what makes a member name given twice keep the last value and nothing
# of the one before it.
json_forget() {
	local path=$1
	local prefix=$path. key

	unset 'JSON_VALUE[$path]' 'JSON_SIZE[$path]' 'JSON_KIND[$path]'

	for key in "${!JSON_KIND[@]}"; do
		if [ "${key#"$prefix"}" != "$key" ]; then
			unset 'JSON_VALUE[$key]' 'JSON_SIZE[$key]' 'JSON_KIND[$key]'
		fi
	done
}

# Read an object and record the number of its members under its own path.
#
#   json_read_object PATH DEPTH
#
# The number recorded is the number of member names, so a name given twice
# counts once and matches what JSON_VALUE holds afterwards.
json_read_object() {
	local path=$1 depth=$2
	local count=0 key child c name_at
	local -A seen=()

	JSON_KIND[$path]=object
	JSON_POS=$((JSON_POS + 1))
	json_skip_space

	if [ "${JSON_TEXT:JSON_POS:1}" = '}' ]; then
		JSON_POS=$((JSON_POS + 1))
		JSON_SIZE[$path]=0
		return 0
	fi

	while :; do
		json_skip_space
		name_at=$JSON_POS
		if [ "${JSON_TEXT:JSON_POS:1}" != '"' ]; then
			JSON_ERROR="offset $JSON_POS: a member name was expected"
			return 1
		fi
		if ! json_read_string; then
			return 1
		fi
		key=$JSON_STR

		# Every value is named by a path, and bash has no empty array
		# subscript, so a name that holds nothing is refused here rather than
		# turned into a path the shell cannot hold.
		if [ -z "$key" ]; then
			JSON_ERROR="offset $name_at: a member name is empty, and every value has to have a path"
			return 1
		fi

		json_skip_space
		if [ "${JSON_TEXT:JSON_POS:1}" != ':' ]; then
			JSON_ERROR="offset $JSON_POS: a colon was expected after the member name '$key'"
			return 1
		fi
		JSON_POS=$((JSON_POS + 1))
		json_skip_space

		if [ "$path" = "$JSON_ROOT" ]; then
			child=$key
		else
			child=$path.$key
		fi

		if [ -n "${seen[$key]+set}" ]; then
			json_forget "$child"
		else
			seen[$key]=1
			count=$((count + 1))
		fi

		if ! json_read_value "$child" "$((depth + 1))"; then
			return 1
		fi

		json_skip_space
		c=${JSON_TEXT:JSON_POS:1}
		case $c in
		',')
			JSON_POS=$((JSON_POS + 1))
			;;
		'}')
			JSON_POS=$((JSON_POS + 1))
			break
			;;
		*)
			JSON_ERROR="offset $JSON_POS: a comma or a closing brace was expected inside an object"
			return 1
			;;
		esac
	done

	JSON_SIZE[$path]=$count
}

# Read an array and record the number of its members under its own path.
#
#   json_read_array PATH DEPTH
json_read_array() {
	local path=$1 depth=$2
	local count=0 child c

	JSON_KIND[$path]=array
	JSON_POS=$((JSON_POS + 1))
	json_skip_space

	if [ "${JSON_TEXT:JSON_POS:1}" = ']' ]; then
		JSON_POS=$((JSON_POS + 1))
		JSON_SIZE[$path]=0
		return 0
	fi

	while :; do
		json_skip_space
		if [ "$path" = "$JSON_ROOT" ]; then
			child=$count
		else
			child=$path.$count
		fi
		if ! json_read_value "$child" "$((depth + 1))"; then
			return 1
		fi
		count=$((count + 1))

		json_skip_space
		c=${JSON_TEXT:JSON_POS:1}
		case $c in
		',')
			JSON_POS=$((JSON_POS + 1))
			;;
		']')
			JSON_POS=$((JSON_POS + 1))
			break
			;;
		*)
			JSON_ERROR="offset $JSON_POS: a comma or a closing bracket was expected inside an array"
			return 1
			;;
		esac
	done

	JSON_SIZE[$path]=$count
}
