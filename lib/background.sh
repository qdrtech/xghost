#!/usr/bin/env bash
#
# The background of the xghost desktop: one image per theme, drawn from the
# colours of that theme.
#
# No artwork is shipped. The image is a vertical gradient between two colours
# the palette already declares, at the resolution the machine facts report, so
# a theme carries its own wallpaper and this repository stays small.
# docs/backgrounds.md records the design, the dependency it needs, and the
# limits of the determinism it promises.
#
# Two files of the generated output belong to this module:
#
#   hypr/background.png   the image, written by the renderer with the rest of
#                         the output tree, so it lands inside the atomic switch
#                         rather than beside it.
#   hypr/wallpaper.conf   the hyprpaper file that names the image. It is
#                         written by lib/theme.sh, because the path it holds
#                         is the stable path of the generated output and only
#                         that module knows it. "The path is written out in
#                         full" below records why it cannot be relative.
#
# The module prints nothing. It reports a problem in BACKGROUND_PROBLEM and a
# reason for an absent image in BACKGROUND_NOTE, and it leaves every report to
# its caller.
#
# The two are told apart on purpose, and it is the same distinction lib/facts.sh
# draws between a value that is wrong and a value that was never read:
#
#   A problem  the image should have been drawn and could not be. The render
#              fails and the active theme is unchanged.
#   A note     the image could not be drawn, and nothing is wrong. The machine
#              facts hold no resolution, or the palette holds no colour to draw
#              with. The render succeeds, the switch happens, and the desktop
#              keeps the wallpaper Hyprland draws itself.
#
# The note is the case a first installation is in: 'hyprctl' answers only inside
# a running session, so the detection an installation runs records no monitor
# and this module has no resolution to draw at. Failing the render there would
# leave a machine with no colours at all rather than with no wallpaper, and the
# 'xghost machine refresh' of the prescribed autostart draws the image at the
# first login. Nothing is invented in the meantime: a resolution nobody read is
# not a resolution to guess at.
#
# ## The path is written out in full
#
# hyprpaper 0.8.4 resolves the path of a wallpaper against the working
# directory of the daemon, not against the configuration file that named it.
# The evidence is in the program: the path resolver takes a base directory, and
# the caller that reads a wallpaper path passes an empty one, which is the
# documented way of asking for the working directory. A relative path would
# therefore be resolved against whatever directory the session happened to
# start the daemon in.
#
# So the one file that names the image writes the path out in full. That is the
# opposite of every 'source' line of the bundle, and the reason is the opposite
# too: a 'source' is resolved against the file that holds it, and a wallpaper
# path is not. lib/theme.sh writes that file for the same reason: the full path
# is the stable path of the generated output, and the renderer is a pure
# function that does not know where its output will be moved to.

# The include sentinel. A library may be sourced more than once, because two
# modules may each need it. The second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_BACKGROUND_SOURCED:-}" ]; then
	return 0
fi
XGHOST_BACKGROUND_SOURCED=1

XGHOST_BACKGROUND_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The two files, at the relative path each one takes in the generated output.
readonly BACKGROUND_IMAGE_RELATIVE=hypr/background.png
readonly BACKGROUND_WALLPAPER_RELATIVE=hypr/wallpaper.conf

# The program that writes the PNG, beside this file. It is the one program of
# this repository that is not shell, and docs/backgrounds.md records why.
readonly BACKGROUND_WRITER=$XGHOST_BACKGROUND_DIR/background.py
readonly BACKGROUND_INTERPRETER=python3
readonly BACKGROUND_PACKAGE=python

# The two colours of the palette the image is drawn from. The derived '_HEX'
# form is what is read, so a value that is not a colour at all is absent from
# the table rather than passed to the writer as text. lib/palette.sh derives it.
readonly BACKGROUND_TOP_KEY=BG
readonly BACKGROUND_TINT_KEY=ACCENT
readonly BACKGROUND_HEX_SUFFIX=_HEX

# The gradient runs from the background colour of the theme to that same colour
# carried one quarter of the way to the accent. One quarter is enough for the
# eye to read the accent of the theme and little enough that the wallpaper
# stays a background: a window sits on it all day.
readonly BACKGROUND_TINT_NUMERATOR=1
readonly BACKGROUND_TINT_DENOMINATOR=4

# The mode of one monitor, as lib/detect.sh writes it: 'WIDTHxHEIGHT@REFRESH'.
# A mode this does not match is not a resolution, and 'unknown' is the value
# detection writes for a monitor it could not read at all.
readonly BACKGROUND_MODE_KEY_PREFIX=MACHINE_MONITOR_
readonly BACKGROUND_MODE_KEY_SUFFIX=_MODE
readonly BACKGROUND_MODE_PATTERN='^([1-9][0-9]*)x([1-9][0-9]*)@'

# The mode of the image. It is set here rather than left to the umask of
# whoever ran the command, for the reason lib/renderer.sh records.
readonly BACKGROUND_FILE_MODE=0644

# Set by background_render and by the functions below it.
BACKGROUND_PROBLEM=
BACKGROUND_NOTE=
BACKGROUND_WIDTH=
BACKGROUND_HEIGHT=
BACKGROUND_TOP=
BACKGROUND_BOTTOM=

# The size of the image, from the machine facts.
#
#   background_size SCALARS_ARRAY_NAME
#
# The image covers every display, because one wallpaper is written for all of
# them and no output name is ever put in a file. Its size is therefore the
# largest width and the largest height of any monitor the facts describe, so no
# display has to stretch it.
#
# The monitors are read by number, from 1 upwards, for as long as the facts
# describe one. The count is not read: a file that describes three monitors
# describes them as 1, 2 and 3, and reading the numbering itself needs no rule
# about what a count that disagrees with it would mean.
#
# Sets BACKGROUND_WIDTH and BACKGROUND_HEIGHT. Returns 1 and sets
# BACKGROUND_NOTE when no monitor of the facts carries a resolution.
background_size() {
	local -n scalars_ref=$1
	local index=1 key mode
	local width=0 height=0

	BACKGROUND_WIDTH=
	BACKGROUND_HEIGHT=

	while :; do
		key=$BACKGROUND_MODE_KEY_PREFIX$index$BACKGROUND_MODE_KEY_SUFFIX
		[ -n "${scalars_ref[$key]+set}" ] || break
		mode=${scalars_ref[$key]}
		index=$((index + 1))

		# A mode of 'unknown' fails this test, as every other value that is not
		# a resolution does. Detection writes that word for a monitor it could
		# not read, and this module invents no size for it.
		[[ $mode =~ $BACKGROUND_MODE_PATTERN ]] || continue

		if [ "${BASH_REMATCH[1]}" -gt "$width" ]; then
			width=${BASH_REMATCH[1]}
		fi
		if [ "${BASH_REMATCH[2]}" -gt "$height" ]; then
			height=${BASH_REMATCH[2]}
		fi
	done

	if [ "$width" -eq 0 ] || [ "$height" -eq 0 ]; then
		BACKGROUND_NOTE="no background image was drawn: the machine facts carry no display resolution. Run 'xghost machine detect' inside a Hyprland session, then set the theme again."
		return 1
	fi

	BACKGROUND_WIDTH=$width
	BACKGROUND_HEIGHT=$height
}

# The two colours of the gradient, from the theme palette.
#
#   background_colours SCALARS_ARRAY_NAME
#
# Sets BACKGROUND_TOP and BACKGROUND_BOTTOM, each one six hexadecimal digits.
# Returns 1 and sets BACKGROUND_NOTE when the palette declares neither colour
# as a colour.
#
# Which names a palette declares is decided by the templates rather than by any
# module of the project, so a palette without these two is not a failure here.
# It is a theme that draws no wallpaper, and the note says so by name.
background_colours() {
	local -n scalars_ref=$1
	local top tint key channel start end value
	local bottom=

	BACKGROUND_TOP=
	BACKGROUND_BOTTOM=

	for key in "$BACKGROUND_TOP_KEY" "$BACKGROUND_TINT_KEY"; do
		if [ -z "${scalars_ref[$key$BACKGROUND_HEX_SUFFIX]+set}" ]; then
			BACKGROUND_NOTE="no background image was drawn: the theme palette declares no colour named '$key', and the image is drawn from '$BACKGROUND_TOP_KEY' and '$BACKGROUND_TINT_KEY'."
			return 1
		fi
	done

	top=${scalars_ref[$BACKGROUND_TOP_KEY$BACKGROUND_HEX_SUFFIX]}
	tint=${scalars_ref[$BACKGROUND_TINT_KEY$BACKGROUND_HEX_SUFFIX]}

	# The foot of the gradient, one quarter of the way from the background
	# colour to the accent. The arithmetic is integer arithmetic, and half the
	# denominator is added before the division so the result rounds to the
	# nearest whole value rather than always down.
	for channel in 0 2 4; do
		start=$((16#${top:$channel:2}))
		end=$((16#${tint:$channel:2}))
		value=$((
			(start * (BACKGROUND_TINT_DENOMINATOR - BACKGROUND_TINT_NUMERATOR) +
				end * BACKGROUND_TINT_NUMERATOR +
				BACKGROUND_TINT_DENOMINATOR / 2) / BACKGROUND_TINT_DENOMINATOR
		))
		bottom=$bottom$(printf '%02x' "$value")
	done

	BACKGROUND_TOP=$top
	BACKGROUND_BOTTOM=$bottom
}

# Draw the background of one render into one output directory.
#
#   background_render OUT_DIR SCALARS_ARRAY_NAME
#
# SCALARS_ARRAY_NAME is the table the renderer built from the theme palette, the
# machine facts and the knobs. The image is drawn from the palette and sized
# from the facts, so a knob never reaches it.
#
# Returns:
#   0  the image is at OUT_DIR/hypr/background.png
#   1  no image was drawn, and BACKGROUND_NOTE says why
#   2  the image could not be drawn, and BACKGROUND_PROBLEM says why
background_render() {
	local out_dir=$1 scalars_name=$2
	local destination=$out_dir/$BACKGROUND_IMAGE_RELATIVE
	local problem

	BACKGROUND_PROBLEM=
	BACKGROUND_NOTE=

	background_size "$scalars_name" || return 1
	background_colours "$scalars_name" || return 1

	if ! command -v "$BACKGROUND_INTERPRETER" >/dev/null 2>&1; then
		BACKGROUND_PROBLEM="the '$BACKGROUND_INTERPRETER' program is not installed, and the background of a theme is drawn with it. It ships in the '$BACKGROUND_PACKAGE' package."
		return 2
	fi
	if [ ! -f "$BACKGROUND_WRITER" ]; then
		BACKGROUND_PROBLEM="the program that draws the background is missing from the installation: $BACKGROUND_WRITER"
		return 2
	fi

	if ! mkdir -p "${destination%/*}" 2>/dev/null; then
		BACKGROUND_PROBLEM="cannot create the directory that holds the background: ${destination%/*}"
		return 2
	fi

	# The report of the writer is read rather than dropped, so a failure of it
	# reaches the user as the sentence the writer wrote.
	if ! problem=$("$BACKGROUND_INTERPRETER" "$BACKGROUND_WRITER" \
		"$BACKGROUND_WIDTH" "$BACKGROUND_HEIGHT" \
		"$BACKGROUND_TOP" "$BACKGROUND_BOTTOM" "$destination" 2>&1 >/dev/null); then
		rm -f "$destination" 2>/dev/null
		BACKGROUND_PROBLEM="cannot draw the background at ${BACKGROUND_WIDTH}x${BACKGROUND_HEIGHT}: ${problem:-the writer failed and said nothing}"
		return 2
	fi

	if ! chmod "$BACKGROUND_FILE_MODE" "$destination" 2>/dev/null; then
		BACKGROUND_PROBLEM="cannot set the mode of the background: $destination"
		return 2
	fi
}

# Print the hyprpaper file that names the background of one build.
#
#   background_wallpaper_conf IMAGE_PATH [NOTE]
#
# IMAGE_PATH is the path of the image, written out in full, or empty when the
# build holds no image. NOTE is then the reason, and it is written into the
# file, so the file itself answers the question a user asks when the desktop
# comes up without a wallpaper.
#
# The monitor of the wallpaper is empty, which is every display. That is what
# keeps the promise of the Hyprland bundle that no output name is written into
# any file this project produces, and it is why one image serves a machine with
# three monitors.
background_wallpaper_conf() {
	local image=$1 note=${2:-}

	printf '# The wallpaper of the active theme.\n'
	printf '#\n'
	printf "# Generated by 'xghost theme set'. Nobody edits this file: the next theme\n"
	printf '# switch writes it again. config/hypr/hyprpaper.conf reaches it through the\n'
	printf '# bridge, and docs/backgrounds.md records the whole of it.\n'
	printf '#\n'

	if [ -z "$image" ]; then
		printf '# This build holds no image:\n'
		printf '#\n'
		printf '#   %s\n' "$note"
		printf '#\n'
		printf '# hyprpaper therefore holds no wallpaper, and Hyprland draws its own, which\n'
		printf '# conf/misc.conf keeps switched on for exactly this case.\n'
		return 0
	fi

	printf '# The path is written out in full because hyprpaper resolves a relative one\n'
	printf '# against the working directory of the daemon rather than against this file.\n'
	printf '\n'
	printf 'wallpaper {\n'
	printf '    monitor =\n'
	printf '    path = %s\n' "$image"
	printf '    fit_mode = cover\n'
	printf '}\n'
}
