#!/usr/bin/env python3
"""Write one PNG holding a vertical gradient between two colours.

    background.py WIDTH HEIGHT TOP BOTTOM OUTPUT

TOP and BOTTOM are six hexadecimal digits, 'rrggbb', without a leading hash.
The image is WIDTH by HEIGHT pixels, and row 0 is TOP.

This is the one program of xghost that is not shell. It exists because
hyprpaper needs a raster image and nothing in the package manifest can write
one. It uses the Python standard library alone: 'zlib' for the compressed
stream a PNG carries, and 'struct' for the byte order of its chunk headers.
No third-party module is imported and none is needed.
docs/backgrounds.md records the decision and the dependency it proposes.

The program is deterministic. The same arguments produce the same bytes: every
value is computed with integer arithmetic, the pixels are the only input to the
compressor, and the file carries no timestamp and no text chunk.

The one thing it does not promise is the same bytes on two machines whose zlib
differs. The compressed stream is what zlib produces, and another version of
zlib may pack the same pixels differently. The image is the same image;
the file may differ by a few bytes. docs/backgrounds.md states that limit.

It prints nothing on success. Every failure is one line on standard error.

Exit codes:
    0  the file was written
    2  the arguments are not the ones documented above
    1  the file could not be written
"""

import os
import struct
import sys
import zlib

PROGRAM = "background.py"

# The compression level of the pixel stream. It is written out rather than left
# to the default, because the default is a property of the Python that runs
# this and the output has to depend on the arguments alone.
COMPRESSION_LEVEL = 9

# A row of a truecolour PNG carries one filter byte and then three bytes per
# pixel. Filter 1 is 'Sub': every byte is the difference from the byte three
# places before it. A row of one colour is therefore its first pixel followed
# by zeros, which is both the smallest file and the fastest row to build.
FILTER_SUB = 1

# The header of a PNG, and the two fields of IHDR this program never varies:
# eight bits per channel, and colour type 2, which is red, green and blue with
# no alpha channel and no palette.
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
BIT_DEPTH = 8
COLOUR_TYPE_RGB = 2

# The largest image this program will write. A wallpaper is the size of a
# display, and a value far above that is a mistake in the machine facts rather
# than a wall of pixels somebody wants: 65535 is wider and taller than any
# display, and the whole image still fits in memory.
MAX_DIMENSION = 65535


def fail(code, message):
    """Report one problem and stop."""
    print("%s: %s" % (PROGRAM, message), file=sys.stderr)
    raise SystemExit(code)


def parse_dimension(text, name):
    """Read one side of the image, in pixels."""
    if not text.isdigit():
        fail(2, "%s is '%s', and it has to be a whole number of pixels"
             % (name, text))
    value = int(text, 10)
    if value < 1:
        fail(2, "%s is %d, and an image has at least one pixel on each side"
             % (name, value))
    if value > MAX_DIMENSION:
        fail(2, "%s is %d, and this program writes no side longer than %d pixels"
             % (name, value, MAX_DIMENSION))
    return value


def parse_colour(text, name):
    """Read one colour, written as six hexadecimal digits."""
    digits = "0123456789abcdefABCDEF"
    if len(text) != 6 or any(character not in digits for character in text):
        fail(2, "%s is '%s', and a colour is six hexadecimal digits such as"
             " '1a2b3c'" % (name, text))
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))


def blend(start, end, position, span):
    """One channel of the gradient, at one row.

    The arithmetic is integer arithmetic from end to end, so the result never
    depends on how a machine rounds a floating point number. The half span
    added before the division is what rounds the result to the nearest whole
    value rather than always down.
    """
    return (start * (span - position) + end * position + span // 2) // span


def chunk(tag, data):
    """One PNG chunk: its length, its tag, its data and its checksum."""
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def image(width, height, top, bottom):
    """The whole PNG, as bytes."""
    header = struct.pack(">IIBBBBB", width, height, BIT_DEPTH, COLOUR_TYPE_RGB, 0, 0, 0)

    # Every row is one colour, so the bytes after the first pixel are the same
    # for every row. They are built once.
    remainder = bytes(3 * (width - 1))
    span = height - 1

    rows = bytearray()
    for row in range(height):
        if span == 0:
            colour = top
        else:
            colour = tuple(blend(top[channel], bottom[channel], row, span)
                           for channel in range(3))
        rows.append(FILTER_SUB)
        rows.extend(colour)
        rows.extend(remainder)

    return (PNG_SIGNATURE
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(rows), COMPRESSION_LEVEL))
            + chunk(b"IEND", b""))


def main(argv):
    if len(argv) != 6:
        fail(2, "usage: %s WIDTH HEIGHT TOP BOTTOM OUTPUT" % PROGRAM)

    width = parse_dimension(argv[1], "the width")
    height = parse_dimension(argv[2], "the height")
    top = parse_colour(argv[3], "the top colour")
    bottom = parse_colour(argv[4], "the bottom colour")
    output = argv[5]

    try:
        descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(image(width, height, top, bottom))
    except OSError as problem:
        fail(1, "cannot write '%s': %s" % (output, problem.strerror))

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
