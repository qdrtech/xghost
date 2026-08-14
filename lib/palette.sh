#!/usr/bin/env bash
#
# The palette reader of the xghost renderer.
#
# A palette is a data file, not a script. This module reads it line by line and
# never sources it, so a palette can never run code.
#
# The module prints nothing. It collects every problem in PALETTE_ERRORS and
# leaves the reporting to the caller. The palette format is documented in
# docs/theming.md.

# Set by palette_load.
declare -A PALETTE_SCALARS=()
PALETTE_ERRORS=()

# A palette key is upper case, because the derived forms append an upper case
# suffix to it.
readonly PALETTE_KEY_PATTERN='^[A-Z][A-Z0-9_]*$'

# A value that matches this pattern is a colour, so it carries the two derived
# forms below.
readonly PALETTE_COLOUR_PATTERN='^#([0-9a-fA-F]{6})$'

# The suffixes the renderer appends to build a derived form. A palette may not
# declare a key that ends in one of them, because the two would collide.
readonly PALETTE_HEX_SUFFIX=_HEX
readonly PALETTE_RGB_SUFFIX=_RGB

# Read one palette file.
#
# Fills PALETTE_SCALARS with every declared value and with the derived form of
# every colour. Returns 1 when the file has at least one problem, and every
# problem lands in PALETTE_ERRORS. A problem is never dropped, so a palette with
# three mistakes reports three lines.
palette_load() {
	local file=$1

	PALETTE_SCALARS=()
	PALETTE_ERRORS=()

	if [ ! -f "$file" ]; then
		PALETTE_ERRORS+=("the palette file does not exist: $file")
		return 1
	fi
	if [ ! -r "$file" ]; then
		PALETTE_ERRORS+=("the palette file cannot be read; check its permissions: $file")
		return 1
	fi

	local -A declared=()
	local line key value hex lineno=0

	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))

		# Drop the white space at both ends of the line.
		line=${line#"${line%%[![:space:]]*}"}
		line=${line%"${line##*[![:space:]]}"}

		if [ -z "$line" ] || [[ $line == '#'* ]]; then
			continue
		fi

		if [[ ! $line =~ ^([^=]+)=(.*)$ ]]; then
			PALETTE_ERRORS+=("line $lineno: expected 'KEY=value', found '$line'")
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

		if [[ ! $key =~ $PALETTE_KEY_PATTERN ]]; then
			PALETTE_ERRORS+=("line $lineno: '$key' is not a palette key; a key holds upper case letters, digits and underscores, and starts with a letter")
			continue
		fi
		if [ -z "$value" ]; then
			PALETTE_ERRORS+=("line $lineno: '$key' has no value")
			continue
		fi
		if [[ $key == *"$PALETTE_HEX_SUFFIX" ]] || [[ $key == *"$PALETTE_RGB_SUFFIX" ]]; then
			PALETTE_ERRORS+=("line $lineno: '$key' ends in '$PALETTE_HEX_SUFFIX' or '$PALETTE_RGB_SUFFIX', which the renderer reserves for a derived form")
			continue
		fi
		if [ -n "${declared[$key]+set}" ]; then
			PALETTE_ERRORS+=("line $lineno: '$key' is given more than once")
			continue
		fi

		declared[$key]=$value
		PALETTE_SCALARS[$key]=$value

		# The plain form is the value exactly as the theme author wrote it. The
		# renderer never changes its case, so the author controls that.
		if [[ $value =~ $PALETTE_COLOUR_PATTERN ]]; then
			hex=${BASH_REMATCH[1]}
			PALETTE_SCALARS[$key$PALETTE_HEX_SUFFIX]=$hex
			PALETTE_SCALARS[$key$PALETTE_RGB_SUFFIX]=$(
				printf '%d, %d, %d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
			)
		fi
	done <"$file"

	if [ "${#declared[@]}" -eq 0 ] && [ "${#PALETTE_ERRORS[@]}" -eq 0 ]; then
		PALETTE_ERRORS+=("the palette declares no value")
	fi

	[ "${#PALETTE_ERRORS[@]}" -eq 0 ]
}
