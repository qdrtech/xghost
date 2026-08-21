#!/usr/bin/env bats
#
# Tests for the generated background: the image the renderer draws from the
# palette of a theme, and the hyprpaper file that names it.
#
# Every test runs the real command and asserts what lands on disk. Nothing here
# starts hyprpaper, and nothing here reads the displays of the computer that
# runs the suite: every test that needs a resolution writes the machine facts
# it wants.
#
# The design is recorded in docs/backgrounds.md.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	PRESCRIBED_DIR="$ROOT_DIR/config/hypr"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# Every path the commands read comes from this setup, so no override that
	# the person who runs the suite happens to export reaches a command.
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

	use_fixed_machine_facts
	use_own_knobs

	GENERATED="$XDG_STATE_HOME/xghost/generated"
	IMAGE="$GENERATED/hypr/background.png"
	WALLPAPER="$GENERATED/hypr/wallpaper.conf"
	FACTS="$BATS_TEST_TMPDIR/machine.conf"

	# The largest monitor of tests/fixtures/machine/golden.conf, which is the
	# file use_fixed_machine_facts points every command at.
	FIXED_WIDTH=3840
	FIXED_HEIGHT=2160
}

# Write a machine facts file describing a monitor set, and point the commands
# at it.
#
#   make_facts MODE ...
#
# One mode per monitor, in the form detection writes: 'WIDTHxHEIGHT@REFRESH',
# or the word 'unknown' for a monitor detection could not read. Every other
# fact of a monitor is written from a fixed set, because the shipped templates
# render a whole monitor line and this file asserts on the image alone.
#
# The facts are written by the test, so no assertion here depends on the
# displays of the computer that runs the suite.
make_facts() {
	local index=1 mode

	{
		printf 'MACHINE_FACTS_VERSION=1\n'
		printf 'MACHINE_COMPOSITOR=hyprland\n'
		printf 'MACHINE_MONITOR_COUNT=%s\n' "$#"
		printf 'MACHINE_PRIMARY_MONITOR=DP-%s\n' 1
		for mode in "$@"; do
			printf 'MACHINE_MONITOR_%s_NAME=DP-%s\n' "$index" "$index"
			printf 'MACHINE_MONITOR_%s_MODE=%s\n' "$index" "$mode"
			printf 'MACHINE_MONITOR_%s_POSITION=0x0\n' "$index"
			printf 'MACHINE_MONITOR_%s_SCALE=1\n' "$index"
			printf 'MACHINE_MONITOR_%s_TRANSFORM=0\n' "$index"
			index=$((index + 1))
		done
	} >"$FACTS"
	export XGHOST_MACHINE_FACTS="$FACTS"
}

# A machine whose monitors nobody has read: the state a first installation is
# in, because 'hyprctl' answers only inside a running session.
make_unread_facts() {
	{
		printf 'MACHINE_FACTS_VERSION=1\n'
		printf 'MACHINE_COMPOSITOR=unknown\n'
		printf 'MACHINE_MONITOR_COUNT=unknown\n'
	} >"$FACTS"
	export XGHOST_MACHINE_FACTS="$FACTS"
}

# Point the commands at a theme and a template of this test.
#
# The theme is named 'own' and declares the two colours the image is drawn
# from. The one template names neither a machine fact nor a knob, so a render
# of it turns on the background alone.
use_own_inputs() {
	export XGHOST_THEMES_DIR="$BATS_TEST_TMPDIR/themes"
	export XGHOST_TEMPLATE_DIR="$BATS_TEST_TMPDIR/templates"
	mkdir -p "$XGHOST_THEMES_DIR/own" "$XGHOST_TEMPLATE_DIR"
	printf 'BG=#1a2b3c\nACCENT=#0A84FF\n' >"$XGHOST_THEMES_DIR/own/palette.conf"
	printf 'bg=@BG@\n' >"$XGHOST_TEMPLATE_DIR/plain.conf"
}

# Print 'WIDTH HEIGHT' from the IHDR chunk of one PNG.
#
# The header of a PNG is fixed: an eight byte signature, then the length and the
# tag of IHDR, then the width and the height as four bytes each, most
# significant byte first. They are read here with 'od' rather than with an image
# library, so this assertion depends on no program the project does not already
# need.
png_size() {
	local file=$1
	local -a byte
	local index width=0 height=0

	read -r -a byte < <(od -An -tu1 -j16 -N8 -v "$file")
	for index in 0 1 2 3; do
		width=$((width * 256 + byte[index]))
		height=$((height * 256 + byte[index + 4]))
	done
	printf '%s %s\n' "$width" "$height"
}

# Print the colour of one pixel, as six hexadecimal digits.
#
#   pixel FILE X Y
#
# The image is read here rather than compared as bytes, so these tests assert
# the picture the theme asks for and not the bytes one compressor happened to
# produce. The reader checks the signature, the checksum of every chunk and the
# format of the header on its way, so a file that is not a sound PNG fails here.
#
# The body is indented with spaces. The '<<-' heredoc strips leading tabs, and
# the indentation of the program has to survive that.
pixel() {
	python3 - "$@" <<-'EOF'
		import struct, sys, zlib

		path, x, y = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
		data = open(path, "rb").read()
		assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"

		position, header, stream = 8, None, b""
		while position < len(data):
		    length = struct.unpack(">I", data[position:position + 4])[0]
		    tag = data[position + 4:position + 8]
		    body = data[position + 8:position + 8 + length]
		    checksum = struct.unpack(">I", data[position + 8 + length:position + 12 + length])[0]
		    assert checksum == zlib.crc32(tag + body) & 0xFFFFFFFF, "broken checksum"
		    if tag == b"IHDR":
		        header = struct.unpack(">IIBBBBB", body)
		    elif tag == b"IDAT":
		        stream += body
		    position += 12 + length

		assert header is not None, "no IHDR chunk"
		width, depth, colour = header[0], header[2], header[3]
		assert (depth, colour) == (8, 2), "not eight bit truecolour"

		raw = zlib.decompress(stream)
		stride = width * 3 + 1
		line = bytearray()
		for row in range(y + 1):
		    line = bytearray(raw[row * stride + 1:(row + 1) * stride])
		    kind = raw[row * stride]
		    assert kind in (0, 1), "filter %d is not one this reader handles" % kind
		    if kind == 1:
		        for index in range(3, len(line)):
		            line[index] = (line[index] + line[index - 3]) & 0xFF

		print("%02X%02X%02X" % tuple(line[x * 3:x * 3 + 3]))
	EOF
}

# --- one image per theme -----------------------------------------------------

# Criterion 2 of issue #20. Every theme the project ships renders an image, and
# no theme ships one.
@test "every shipped theme renders a background of its own" {
	local theme count=0
	local -a sums=()
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		[ -f "$IMAGE" ]
		sums+=("$(sha256sum <"$IMAGE")")
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 1 ]

	# Two themes are two palettes, so they are two images. One image for both
	# would mean the palette never reached the drawing.
	[ "${sums[0]}" != "${sums[1]}" ]
}

# Criterion 1 of issue #20: the image is drawn from the palette of the theme.
# The top of the gradient is the background colour of the theme itself.
@test "the image is drawn from the colours of the palette" {
	local top

	"$XGHOST" theme set tokyonight >/dev/null
	top=$(pixel "$IMAGE" 0 0)
	[ "$top" = "1A1B26" ]

	# The foot of the gradient carries the accent of the theme, so the image is
	# of that theme and not of any other. '#1A1B26' one quarter of the way to
	# '#7AA2F7' is '#323D5A'.
	[ "$(pixel "$IMAGE" 0 $((FIXED_HEIGHT - 1)))" = "323D5A" ]

	"$XGHOST" theme set macos-dark >/dev/null
	[ "$(pixel "$IMAGE" 0 0)" = "0F1115" ]
	[ "$(pixel "$IMAGE" 0 $((FIXED_HEIGHT - 1)))" = "0E2E50" ]
}

@test "the image is an eight bit truecolour PNG" {
	"$XGHOST" theme set tokyonight >/dev/null
	# The reader in 'pixel' asserts the signature, the checksum of every chunk,
	# the bit depth and the colour type, so it running at all is the assertion.
	[ -n "$(pixel "$IMAGE" 1 1)" ]
	[ "$(stat -c %a "$IMAGE")" = 644 ]
}

# --- the resolution comes from the machine facts -----------------------------

# Criterion 4 of issue #20.
@test "the image is the size of the display the machine facts report" {
	make_facts 1920x1200@60.00
	"$XGHOST" theme set tokyonight >/dev/null
	[ "$(png_size "$IMAGE")" = "1920 1200" ]
}

# One image serves every display, because one wallpaper is written for all of
# them. It is therefore the size of the largest, and no display stretches it.
@test "the image covers the largest width and height of every monitor" {
	make_facts 1920x1200@60.00 3440x1440@175.00 2560x1600@120.00
	"$XGHOST" theme set tokyonight >/dev/null
	[ "$(png_size "$IMAGE")" = "3440 1600" ]
}

@test "the fixed facts of the suite render an image of that size" {
	"$XGHOST" theme set tokyonight >/dev/null
	[ "$(png_size "$IMAGE")" = "$FIXED_WIDTH $FIXED_HEIGHT" ]
}

# A monitor detection could not read carries the word 'unknown' rather than a
# resolution, and no size is invented from it. The monitors beside it are still
# read, so one display nobody could measure costs no wallpaper.
#
# The theme and the template are of this test, because a shipped template that
# writes a whole monitor line fails the render on that same 'unknown' before
# the image is ever drawn. That refusal is the renderer's, tests/facts.bats
# proves it, and this test is about the size of the image.
@test "a monitor whose mode is unknown contributes no size" {
	use_own_inputs
	make_facts unknown 1600x900@60.00
	"$XGHOST" theme set own >/dev/null
	[ "$(png_size "$IMAGE")" = "1600 900" ]
}

# A mode of twenty digits matches the shape of a resolution and is a number no
# shell test can hold. It used to reach '[ ... -gt ... ]' and print a diagnostic
# of bash itself, under a note that sent the user to detection for facts that
# were not missing at all.
@test "a mode too large to hold reports the mode, and nothing of the shell" {
	local line
	make_facts 99999999999999999999x1080@60.00

	run --separate-stderr "$XGHOST" theme set tokyonight
	[ "$status" -eq 0 ]
	[ ! -e "$IMAGE" ]

	# Every line of the report is a line the command wrote. A raw diagnostic of
	# the shell fails here.
	[ -n "$stderr" ]
	while IFS= read -r line; do
		[[ $line == "xghost: "* ]]
	done <<<"$stderr"
	[[ $stderr != *"integer expected"* ]]

	# The facts carry a resolution here. It is out of range, which is not the
	# same as absent, and the note says which one it is.
	[[ $stderr == *"99999999999999999999x1080@60.00"* ]]
	[[ $stderr != *"machine detect"* ]]
	[[ $stderr != *"carry no display resolution"* ]]
}

# A width the drawing program refuses is a note, not a problem: the switch
# happens and the wallpaper does not. Failing it would leave a machine unable to
# change theme at all until its facts were edited by hand, and the 'xghost
# machine refresh' of the prescribed autostart would fail at every login.
@test "a resolution too large to draw switches theme and draws no image" {
	make_facts 65536x1080@60.00

	run "$XGHOST" theme set macos-dark
	[ "$status" -eq 0 ]
	[[ $output == *"no background image was drawn"* ]]
	[[ $output == *"65536x1080@60.00"* ]]
	[[ $output == *"65535 pixels"* ]]

	[ ! -e "$IMAGE" ]
	[ -f "$GENERATED/hypr/colors.conf" ]

	run "$XGHOST" theme current
	[ "$output" = macos-dark ]

	# And the file that names the image carries the same sentence, so the file
	# a user opens answers the question the desktop asked them.
	run grep -F '65536x1080@60.00' "$WALLPAPER"
	[ "$status" -eq 0 ]
	run grep -cF 'wallpaper {' "$WALLPAPER"
	[ "$output" = 0 ]
}

# Both sides are inside the limit here and the image they make together is not:
# one monitor carries the width and the other the height.
@test "an image larger than the limit in all is a note, not a failure" {
	make_facts 65535x1080@60.00 1920x65535@60.00

	run "$XGHOST" theme set tokyonight
	[ "$status" -eq 0 ]
	[[ $output == *"65535x65535 pixels"* ]]
	[[ $output == *"64000000 pixels"* ]]
	[ ! -e "$IMAGE" ]

	run "$XGHOST" theme current
	[ "$output" = tokyonight ]
}

# A monitor this project cannot draw for carries no size, in the same way a
# monitor whose mode is 'unknown' carries none. The monitors beside it are still
# read, so one impossible mode costs no wallpaper.
@test "a monitor too large to draw for contributes no size" {
	use_own_inputs
	make_facts 70000x1080@60.00 1600x900@60.00

	run "$XGHOST" theme set own
	[ "$status" -eq 0 ]
	[ "$(png_size "$IMAGE")" = "1600 900" ]
	[[ $output != *"no background image was drawn"* ]]
}

# The module refuses a size before the writer sees it, so a size the writer
# would refuse never fails a theme switch. That holds only while the two files
# agree on the limits, which is what this asserts.
@test "the module and the writer hold the same limits" {
	local side_sh side_py pixels_sh pixels_py digits

	side_sh=$(sed -n 's/^readonly BACKGROUND_MAX_SIDE=\([0-9]*\)$/\1/p' \
		"$ROOT_DIR/lib/background.sh")
	pixels_sh=$(sed -n 's/^readonly BACKGROUND_MAX_PIXELS=\([0-9]*\)$/\1/p' \
		"$ROOT_DIR/lib/background.sh")
	digits=$(sed -n 's/^readonly BACKGROUND_MAX_SIDE_DIGITS=\([0-9]*\)$/\1/p' \
		"$ROOT_DIR/lib/background.sh")
	side_py=$(sed -n 's/^MAX_DIMENSION = \([0-9]*\)$/\1/p' "$ROOT_DIR/lib/background.py")
	pixels_py=$(sed -n 's/^MAX_PIXELS = \([0-9]*\)$/\1/p' "$ROOT_DIR/lib/background.py")

	[ -n "$side_sh" ]
	[ -n "$pixels_sh" ]
	[ "$side_sh" = "$side_py" ]
	[ "$pixels_sh" = "$pixels_py" ]

	# The digit count is what keeps a number of any length away from a numeric
	# test of the shell, so it is the length of the limit itself.
	[ "$digits" = "${#side_sh}" ]
}

# The case a first installation is in: 'hyprctl' answers only inside a session,
# so the detection an installation runs reads no monitor at all. The switch
# still happens, because a machine with no wallpaper is better than a machine
# with no colours, and the report says what is missing.
@test "a machine with no known resolution switches theme and draws no image" {
	make_unread_facts
	run "$XGHOST" theme set tokyonight
	[ "$status" -eq 0 ]
	[[ $output == *"no background image was drawn"* ]]
	[[ $output == *"the machine facts carry no display resolution"* ]]
	[[ $output == *"xghost machine detect"* ]]

	[ ! -e "$IMAGE" ]
	[ -f "$GENERATED/hypr/colors.conf" ]

	run "$XGHOST" theme current
	[ "$status" -eq 0 ]
	[ "$output" = tokyonight ]
}

# The file that names the image is written whether or not there is one, so the
# 'source' line of the prescribed configuration always resolves.
@test "a build with no image still writes the file that would name it" {
	make_unread_facts
	"$XGHOST" theme set tokyonight 2>/dev/null
	[ -f "$WALLPAPER" ]
	run grep -c 'wallpaper {' "$WALLPAPER"
	[ "$output" = 0 ]
	run grep -F 'This build holds no image' "$WALLPAPER"
	[ "$status" -eq 0 ]
	run grep -F 'no display resolution' "$WALLPAPER"
	[ "$status" -eq 0 ]
}

# --- determinism -------------------------------------------------------------

# Criterion 6 of issue #20. The same palette and the same resolution produce the
# same file, byte for byte.
@test "the same theme and the same facts produce the same image twice" {
	local first="$BATS_TEST_TMPDIR/first.png"

	"$XGHOST" theme set tokyonight >/dev/null
	cp "$IMAGE" "$first"
	"$XGHOST" theme set tokyonight >/dev/null
	cmp "$first" "$IMAGE"

	# And a switch away and back reproduces it, so nothing of the build the
	# image was written into reaches the bytes of the image.
	"$XGHOST" theme set macos-dark >/dev/null
	run cmp -s "$first" "$IMAGE"
	[ "$status" -ne 0 ]
	"$XGHOST" theme set tokyonight >/dev/null
	cmp "$first" "$IMAGE"
}

@test "one palette at two resolutions produces two images of those sizes" {
	local small="$BATS_TEST_TMPDIR/small.png"

	make_facts 1280x720@60.00
	"$XGHOST" theme set tokyonight >/dev/null
	cp "$IMAGE" "$small"
	[ "$(png_size "$small")" = "1280 720" ]

	make_facts 2560x1440@239.97
	"$XGHOST" theme set tokyonight >/dev/null
	[ "$(png_size "$IMAGE")" = "2560 1440" ]
	run cmp -s "$small" "$IMAGE"
	[ "$status" -ne 0 ]
}

# --- the file hyprpaper reads ------------------------------------------------

@test "the generated wallpaper file names the image in full, for every monitor" {
	"$XGHOST" theme set tokyonight >/dev/null

	run grep -cF 'wallpaper {' "$WALLPAPER"
	[ "$output" = 1 ]
	run grep -Fx '    monitor =' "$WALLPAPER"
	[ "$status" -eq 0 ]
	run grep -Fx "    path = $GENERATED/hypr/background.png" "$WALLPAPER"
	[ "$status" -eq 0 ]

	# The path it names is the stable path, so it survives the next switch, and
	# it resolves to the image of the theme that is active.
	[ -f "$GENERATED/hypr/background.png" ]
	[ "$(stat -c %a "$WALLPAPER")" = 644 ]
}

# Criterion 2 of the Hyprland bundle, which this file has to keep true: no
# monitor output name is written into any file the project produces.
@test "the generated wallpaper file names no monitor output" {
	local connectors='(^|[^A-Za-z0-9-])(eDP|DP|HDMI-A|HDMI-B|DVI-D|DVI-I|DVI-A|VGA|LVDS|DSI|Virtual|Unknown|HEADLESS|WL)-[0-9]+'

	# The scan is proved able to report before it is trusted to report nothing.
	# It reads the line a careless writer would produce, which is the monitor of
	# the facts written into the block.
	printf '    monitor = DP-2\n' | grep -qE "$connectors"

	# The facts of this render name their monitors, so there is a name in the
	# inputs for the file to carry.
	make_facts 1920x1200@60.00 3440x1440@175.00
	"$XGHOST" theme set tokyonight >/dev/null
	run grep -F 'DP-' "$FACTS"
	[ "$status" -eq 0 ]

	run grep -nE "$connectors" "$WALLPAPER"
	[ "$status" -ne 0 ]

	# And the build that holds no image writes no name either: that file carries
	# the note, which is written from what the module read.
	make_unread_facts
	"$XGHOST" theme set tokyonight 2>/dev/null
	run grep -nE "$connectors" "$WALLPAPER"
	[ "$status" -ne 0 ]
}

@test "the prescribed hyprpaper configuration reaches the file through the bridge" {
	run grep -Fx 'source = ../xghost-generated/hypr/wallpaper.conf' \
		"$PRESCRIBED_DIR/hyprpaper.conf"
	[ "$status" -eq 0 ]

	# The prescribed file names no image of its own, and no path in full.
	run grep -nE '^[[:space:]]*(preload|path)[[:space:]]*=' "$PRESCRIBED_DIR/hyprpaper.conf"
	[ "$status" -ne 0 ]
	run grep -nE '^[[:space:]]*source[[:space:]]*=.*(~|\$HOME|\.local/state)' \
		"$PRESCRIBED_DIR/hyprpaper.conf"
	[ "$status" -ne 0 ]
}

# hyprpaper 0.8.4 has no 'preload' keyword at all: the string does not appear
# anywhere in the program. docs/backgrounds.md records the evidence. A file that
# carried the line would be a config error at every start of the daemon.
@test "no file of the project writes a preload line" {
	run grep -rnE '^[[:space:]]*preload[[:space:]]*=' \
		"$ROOT_DIR/config" "$ROOT_DIR/templates" "$ROOT_DIR/lib"
	[ "$status" -ne 0 ]
}

# --- the program that writes the image ---------------------------------------

# The writer documents exit 2 for an argument that is not the documented one,
# and one line on standard error for every failure. A digit of another script is
# an argument nobody wrote: 'isdigit' is true of it, and int() reads some of
# them as numbers and raises on the rest.
@test "the writer refuses a digit that is not a decimal one" {
	local writer="$ROOT_DIR/lib/background.py"
	local out="$BATS_TEST_TMPDIR/out.png"
	local text

	for text in '²' '١٠' '12x' ''; do
		run python3 "$writer" "$text" 1080 1a1b26 323d5a "$out"
		[ "$status" -eq 2 ]
		[ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
		[[ $output == "background.py: "* ]]
		[ ! -e "$out" ]
	done

	# And an image larger than the writer holds in memory is refused the same
	# way, by the count of its pixels rather than by either side alone.
	run python3 "$writer" 65535 65535 1a1b26 323d5a "$out"
	[ "$status" -eq 2 ]
	[ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
	[[ $output == *"pixels"* ]]
	[ ! -e "$out" ]
}

# A failure to write names the reason. The reason of an OSError is its message,
# and 'strerror' alone is None for an error that carries no errno.
@test "the writer names the reason it could not write the file" {
	local writer="$ROOT_DIR/lib/background.py"
	local out="$BATS_TEST_TMPDIR/taken.png"

	printf 'this file is here already\n' >"$out"
	run python3 "$writer" 8 8 1a1b26 323d5a "$out"
	[ "$status" -eq 1 ]
	[ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
	[[ $output == *"$out"* ]]
	[[ $output != *"None"* ]]
	[ "$(cat "$out")" = 'this file is here already' ]
}

# --- what the repository holds -----------------------------------------------

# Criteria 5 and 7 of issue #20: no artwork is shipped, and no generated image
# is committed. A background is drawn on the machine that uses it.
@test "the checkout holds no image file" {
	run find "$ROOT_DIR" -path '*/.git' -prune -o -type f \
		\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
		-o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) -print
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# The drawing needs one program the desktop does not otherwise need, and the
# manifest is the single source of truth for what an installation gets. The
# line in base.txt is a proposal until the maintainer accepts it, and this test
# is what makes the two move together: a machine that installs no Python draws
# no background at all.
@test "the base manifest declares the program that draws the background" {
	run grep -Ex 'python' "$ROOT_DIR/install/packages/base.txt"
	[ "$status" -eq 0 ]
	run grep -Fq 'python3' "$ROOT_DIR/lib/background.sh"
	[ "$status" -eq 0 ]

	# And the program it names imports no third-party module.
	run grep -nE '^[[:space:]]*(import|from)[[:space:]]' "$ROOT_DIR/lib/background.py"
	[ "$status" -eq 0 ]
	[[ $output == *"import os"* ]]
	[[ $output == *"import struct"* ]]
	[[ $output == *"import sys"* ]]
	[[ $output == *"import zlib"* ]]
	[ "$(printf '%s\n' "$output" | wc -l)" -eq 4 ]
}

@test "a render writes no image into the checkout" {
	local before after
	before=$(find "$ROOT_DIR/themes" "$ROOT_DIR/templates" "$ROOT_DIR/config" | LC_ALL=C sort)
	"$XGHOST" theme set tokyonight >/dev/null
	after=$(find "$ROOT_DIR/themes" "$ROOT_DIR/templates" "$ROOT_DIR/config" | LC_ALL=C sort)
	[ "$before" = "$after" ]
}

# A directory at the path of the image is not an image the theme ships. Nothing
# of it is copied into the output, so treating it as one would leave the
# wallpaper file naming a path that holds nothing, and hyprpaper reading it.
@test "a directory at the image path of a theme is not the image" {
	use_own_inputs
	make_facts 1280x720@60.00
	mkdir -p "$XGHOST_THEMES_DIR/own/files/hypr/background.png"

	run "$XGHOST" theme set own
	[ "$status" -eq 0 ]

	# The image is drawn, and it is the file the wallpaper names.
	[ -f "$IMAGE" ]
	[ "$(png_size "$IMAGE")" = "1280 720" ]
	run grep -Fx "    path = $GENERATED/hypr/background.png" "$WALLPAPER"
	[ "$status" -eq 0 ]
}

# Issue #42 at the third of the three sites that ask what the theme ships.
#
# A symbolic link to a directory is what '-f' does not catch and '-L' does, so
# the renderer read it as an image the theme ships and drew nothing over it.
# Nothing of that directory is an image, so the wallpaper file named a path
# that held no image and the render reported success. It is refused by name now.
#
# The theme is set once before the link is put there, so the assertion that the
# previous output survived reads a real drawn image rather than an absence.
# Against the unfixed renderer the second render succeeds and the image path
# holds a directory, so png_size reads no PNG header and the last assertion
# fails.
@test "a link to a directory at the image path of a theme fails the render" {
	use_own_inputs
	make_facts 1280x720@60.00
	"$XGHOST" theme set own >/dev/null
	[ "$(png_size "$IMAGE")" = "1280 720" ]

	mkdir -p "$XGHOST_THEMES_DIR/own/files/hypr" "$BATS_TEST_TMPDIR/upstream"
	printf 'a stray file\n' >"$BATS_TEST_TMPDIR/upstream/stray.txt"
	ln -s "$BATS_TEST_TMPDIR/upstream" "$XGHOST_THEMES_DIR/own/files/hypr/background.png"

	run "$XGHOST" theme set own
	[ "$status" -eq 1 ]
	[[ $output == *"hypr/background.png: the theme ships a symbolic link here and it points at a directory"* ]]
	[[ $output == *"The active theme is unchanged."* ]]

	# The image of the render that succeeded is still the one on disk.
	[ "$(png_size "$IMAGE")" = "1280 720" ]
}

# A theme may ship the image by hand, which is the one rule of precedence in
# docs/theming.md: a hand-written file of the theme wins over what the project
# generates at the same path.
@test "a theme that ships the image by hand keeps it" {
	use_own_inputs
	mkdir -p "$XGHOST_THEMES_DIR/own/files/hypr"
	printf 'the theme ships this one\n' >"$XGHOST_THEMES_DIR/own/files/hypr/background.png"

	"$XGHOST" theme set own >/dev/null
	[ "$(cat "$IMAGE")" = 'the theme ships this one' ]
	run grep -Fx "    path = $GENERATED/hypr/background.png" "$WALLPAPER"
	[ "$status" -eq 0 ]
}
