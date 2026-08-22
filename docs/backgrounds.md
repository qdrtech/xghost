# Backgrounds

The wallpaper of an xghost desktop is drawn from the theme, not shipped with
it. Every theme carries the colours of the desktop already, so the background is
made from those colours at the resolution of the display, on the machine that
uses it.

Nothing is downloaded and no artwork is committed. The repository therefore
stays the size of its text, which is what keeps a `curl` install a quick clone.

```
xghost theme set tokyonight     # writes the image and the file that names it
```

A background is generated output, which is the fourth file category of
[ADR 0001](adr/0001-prescribed-config-architecture.md). Nobody edits it, it is
tracked by nobody, and the next theme switch writes it again.

## The two files

| File                                     | Written by       | What it holds                              |
| ---------------------------------------- | ---------------- | ------------------------------------------ |
| `<generated>/hypr/background.png`        | `lib/renderer.sh` | The image of the active theme.             |
| `<generated>/hypr/wallpaper.conf`        | `lib/theme.sh`   | The hyprpaper block that names the image.  |

`<generated>` is `$XDG_STATE_HOME/xghost/generated`, the stable path
[Theming](theming.md) records. `config/hypr/hyprpaper.conf` reaches the second
file through the bridge, with the one line every other bundle uses:

```
source = ../xghost-generated/hypr/wallpaper.conf
```

The second file is written whether or not there is an image, so that include
always resolves. hyprpaper reports a `source` that matches no file as an error,
and a desktop that cannot draw a wallpaper must not also fail to start its
daemon.

## Where the drawing runs

The image is drawn **inside the render**, by `lib/renderer.sh`, into the output
directory the renderer is building. It is therefore moved into place by the one
rename that makes a theme switch atomic, and a reader of the stable path sees
the image and the configuration of the same theme, never a mixture of two.

The renderer stays a pure function of its three inputs: the same palette, the
same machine facts and the same knobs draw the same image.

Writing the image after the switch was the other option, and it is rejected for
what it would leave on a machine where it failed: a build whose colours are of
one theme and whose wallpaper is of another. The switch is atomic or it is not.

`lib/theme.sh` writes `wallpaper.conf` rather than the renderer, and there is
one reason: the path inside it. "The path is written out in full" below records
that reason.

## The size comes from the machine facts

The image is as wide as the widest monitor of the machine facts, and as tall as
the tallest. One wallpaper covers every display, because it is written with an
empty monitor field, so a size that no display exceeds is the size that no
display has to stretch.

The facts it reads are `MACHINE_MONITOR_N_MODE`, which detection writes as
`WIDTHxHEIGHT@REFRESH`. The monitors are read by number, from 1 upwards, for as
long as the facts describe one. [Machine facts](machine-facts.md) documents the
file.

```
MACHINE_MONITOR_1_MODE=3840x2160@60.00     the image is 3840 by 2160
MACHINE_MONITOR_2_MODE=2560x1440@144.00
```

### When the resolution is not known

Detection writes `unknown` for a monitor it could not read, and it never
invents a plausible one. Neither does this: a monitor whose mode is `unknown`
carries no size, and a machine where no monitor carries one gets **no image**.

The theme switch still happens, and it says so on standard error:

```
xghost: tokyonight: no background image was drawn: the machine facts carry no
display resolution. Run 'xghost machine detect' inside a Hyprland session, then
set the theme again.
```

The generated `wallpaper.conf` carries the same sentence, so the file a user
opens answers the question the desktop asked them.

Failing the whole switch was weighed and rejected. `hyprctl` answers only
inside a running Hyprland session, so the detection an installation runs
records no monitor at all, and a first installation would fail at the step that
renders the theme. That would leave the machine with no colours rather than
with no wallpaper. The prescribed autostart carries
`exec-once = xghost machine refresh`, which detects and renders again inside
the session, so the image arrives at the first login and every login after it.
It is the same ordering cost the monitor layout already has, and
[the Hyprland bundle](bundles/hyprland.md) records that.

### When the resolution is too large to draw

A background is at most **65535 pixels on a side** and at most **64 million
pixels in all**. `lib/background.sh` and `lib/background.py` hold both numbers,
and a test asserts they agree.

A monitor whose mode is above either limit carries no size, in the same way a
monitor whose mode is `unknown` carries none, and the monitors beside it are
still read. A machine where no monitor is left gets no image, and the note says
which of the two cases it is:

```
xghost: tokyonight: no background image was drawn: the machine facts report the
display mode '65536x1080@60.00', and no background is drawn with a side longer
than 65535 pixels. Correct the monitor mode in the machine facts, then set the
theme again.
```

It does not send the user to `xghost machine detect`, because detection would
write the same value again. The facts carry a resolution here; it is out of
range, which is a different thing from carrying none.

**This is a note, not a problem, and that is a decision.** A mode the drawing
program refuses is a value of the inputs, and the two sides of the line are
where the fault is: a value of the inputs is a note, and a broken installation
is a problem. Failing the switch would leave a user unable to change theme at
all until they edited the machine facts by hand, and the
`exec-once = xghost machine refresh` of the prescribed autostart would fail at
every login with it. `lib/background.sh` records the same rule beside the code.

The two files hold the same limits so the module never passes a size the writer
would refuse: a size refused inside the writer is a problem, and it would fail
the switch that this keeps working.

A palette that declares no `BG` or no `ACCENT` is the third case of the same
kind: no image, one sentence, and a switch that still happens. Which names a
palette declares is decided by the templates rather than by any module, and
[Theming](theming.md) states that rule.

## The picture

A vertical gradient, from the background colour of the theme at the top to that
same colour carried one quarter of the way to the accent at the foot.

| Theme        | Top       | Foot      |
| ------------ | --------- | --------- |
| `tokyonight` | `#1A1B26` | `#323D5A` |
| `macos-dark` | `#0F1115` | `#0E2E50` |

One quarter is enough for the eye to read the accent of the theme, and little
enough that the wallpaper stays a background: a window sits on it all day.

Two palette keys are read, `BG` and `ACCENT`, in the derived `_HEX` form
[Theming](theming.md) documents. A value that is not a colour carries no derived
form, so it never reaches the drawing as text.

A theme may ship an image of its own instead, at
`themes/<name>/files/hypr/background.png`. Nothing is drawn over it. That is
the one rule of precedence of the renderer: a hand-written file of the theme
wins over what the project generates at the same path.

## Determinism, and its one limit

The same palette and the same resolution produce the same file, byte for byte.
`tests/background.bats` renders twice and compares the two.

Every value is computed with integer arithmetic, so no rounding of a floating
point number reaches a pixel. The file carries no timestamp and no text chunk,
so nothing of the moment it was written reaches its bytes.

The limit is stated plainly. The pixels of a PNG are carried in a compressed
stream, and that stream is what the zlib of the machine produces. Another
version of zlib may pack the same pixels into a few different bytes. The image
is the same image, and the file may differ. That is why no checksum of an image
is committed to this repository: it would pin the version of a library rather
than the picture the theme asks for. The tests read the pixels instead.

## The path is written out in full

`wallpaper.conf` names the image by its whole path:

```
wallpaper {
    monitor =
    path = /home/ada/.local/state/xghost/generated/hypr/background.png
    fit_mode = cover
}
```

That is the opposite of every `source` line of this project, and the reason is
the opposite too. hyprpaper resolves the path of a wallpaper against the
**working directory of the daemon**, not against the file that named it.

The evidence is in the program of hyprpaper 0.8.4. It resolves a path with
`std::filesystem::canonical`, and that call is what resolves a relative path
against the working directory of the process:

```
$ nm -DC /usr/bin/hyprpaper | grep canonical
 U std::filesystem::canonical(std::filesystem::__cxx11::path const&,
                              std::error_code&)@GLIBCXX_3.4.26
$ objdump -d /usr/bin/hyprpaper | grep -c 'call.*filesystem9canonical'
1
```

The one call takes the path and an `error_code`, and nothing else:

```
2643d:  mov    %r14,%rdi
26440:  call   *...    # std::filesystem::path::has_root_directory()
26446:  movb   $0x0,-0x148(%rbp)      # a one byte flag, from that answer
...
26491:  cmpb   $0x0,-0x148(%rbp)
26498:  jne    267f0                  # the path already has a root
2653a:  call   *...    # std::filesystem::canonical(path const&, error_code&)
```

The resolver takes no base directory to resolve against. What it carries beside
the path is one byte, computed from `has_root_directory()`. A relative path
therefore depends on the directory the session happened to start the daemon in.

The path it holds is the **stable** path, never the path of the build it is
written into. A build directory is replaced by the next switch; the stable path
is the one the desktop is configured against.

Only `lib/theme.sh` knows that path, because the renderer is a pure function of
the theme, the facts and the knobs, and where its output will be moved to is
none of those. So `lib/theme.sh` writes this one file, into the build, before
the switch. The image and the file that names it land together.

The consequence for the tests: `tests/golden.bats` leaves both files out of the
committed golden output, because one is megapixels and the other holds a path
of the machine that rendered it. `tests/background.bats` proves both directly.

## What hyprpaper reads today

The hyprpaper this manifest installs is **0.8.4**, and its configuration is not
the one the older documentation describes.

- There is no `preload` keyword. The string does not appear anywhere in the
  program of 0.8.4. A file that carried the line would report a configuration
  error at every start of the daemon.
- A wallpaper is a block: `monitor`, `path` and `fit_mode` are its keys.
- `monitor =`, left empty, is every display. That is what keeps criterion 2 of
  [the Hyprland bundle](bundles/hyprland.md) true: no monitor output name is
  written into any file this project produces.

[The Hyprland bundle](bundles/hyprland.md) asked issue #20 for one `preload`
line and one `wallpaper` line, which is the shape hyprpaper 0.7 read. That
shape is not carried out, and this is the disagreement written down rather than
made in silence. What the bundle asked for in substance — one image per theme,
one generated file that names it with an empty monitor, one `source` line in
the prescribed file — is exactly what is delivered.

## The dependency this needs

Nothing else in `install/packages/base.txt` can write a raster image, and
hyprpaper needs one: it does not read an SVG. One package therefore had to be
added. The vetting below is what the maintainer read before the line was
accepted, on 2026-08-14, and the slice that wrote this page installed nothing
itself.

### The package: `python`

| Field                | Value                                                        |
| -------------------- | ------------------------------------------------------------ |
| Package              | `python`                                                      |
| Version              | `3.14.7-1`                                                    |
| Repository           | `core`, the official Arch repository                          |
| Upstream             | <https://www.python.org/>                                     |
| Packager             | Jelle van der Waa \<jelle@archlinux.org\>, an Arch developer  |
| Licence              | PSF-2.0                                                       |
| Download size        | 13.53 MiB                                                     |
| Installed size       | 73.62 MiB                                                     |
| Direct dependencies  | 11: `bzip2 expat gdbm libffi libnsl libxcrypt openssl zlib tzdata mpdecimal zstd` |
| Signature            | Signed, and validated by SHA-256 sum. `pacman -Si python`     |
| Known vulnerabilities | **None open.** The Arch security tracker records 4 advisory groups covering 5 CVEs for this package, and every one of them is `Fixed` at this version. |

**What it adds to an xghost installation: nothing.** `python` is already in the
dependency tree of two packages the manifest declares:

```
blueman  -> python-gobject -> python
blueman  -> python-cairo   -> python
nautilus -> ...            -> python
```

The whole dependency closure of `base.txt` is 505 packages and `python` is one
of them today. Declaring it changes what is installed on no machine; it records
that xghost itself needs it, which is what the manifest is for. `xdg-utils` is
in the file for exactly that reason already.

The one dependency of `python` that the closure does not name is `libxcrypt`,
and every Arch installation carries it: `pam`, `systemd`, `shadow` and
`util-linux` all require it.

**How much of it is used.** `lib/background.py` imports `os`, `struct`, `sys`
and `zlib`, and nothing else. All four are the standard library. No third-party
module is installed and none is imported, so `pip` never runs and there is no
second manifest to keep. A test asserts that list of imports, so it cannot grow
without a reviewer seeing it.

**What the project owns for it.** About 90 lines that write a PNG: the
signature, three chunks, and one filtered row per line of the gradient.

### The alternative: `imagemagick`

| Field                | Value                                                        |
| -------------------- | ------------------------------------------------------------ |
| Package              | `imagemagick`                                                 |
| Version              | `7.1.2.29-2`                                                  |
| Repository           | `extra`                                                       |
| Upstream             | <https://www.imagemagick.org/>                                |
| Packager             | Antonio Rojas \<arojas@archlinux.org\>, an Arch developer     |
| Licence              | ImageMagick                                                   |
| Download size        | 8.75 MiB                                                      |
| Installed size       | 21.76 MiB                                                     |
| Direct dependencies  | 19, and 18 more optional ones for the formats it reads        |
| Known vulnerabilities | **None open.** The tracker records 14 advisory groups covering 20 CVEs, all `Fixed` at this version. One of them, ASA-201903-15, was arbitrary code execution rated Critical. |

It would draw the gradient in one command, and the project would own no drawing
code at all. That is its whole case, and it is a real one.

It is not chosen, for three reasons.

1. **It adds packages, and Python adds none.** `imagemagick`, `liblqr`,
   `libraqm` and `libtool`, which carries the `libltdl` it loads its coders
   with, are none of them in the dependency closure of the manifest today.
   Four packages and 24.4 MiB installed arrive for one gradient. Its fifth
   dependency, `tar`, is on every Arch machine already: the `base` group
   requires it.
2. **The surface is far larger.** ImageMagick decodes every image format there
   is, and its advisory history is that of a decoder: 20 CVEs to Python's 5,
   including one arbitrary code execution rated Critical. This project would
   use none of the decoding. The comparison is of what is installed, and what
   is installed is what has to be updated for the rest of the machine's life.
3. **Determinism costs work there too.** ImageMagick writes `date:create` and
   `date:modify` text chunks into a PNG unless they are excluded, so the same
   command run twice produces two different files. The exclusion is one more
   thing to get right, and the version of its own PNG encoder still reaches the
   bytes.

`ffmpeg` and `rsvg-convert` were weighed and dropped in one line each: both are
already in the closure of the manifest, so both are cheap, and both are far
larger decoders than ImageMagick for a job that is one gradient. Neither writes
a deterministic PNG without the same care, and `rsvg-convert` would mean the
project owned SVG text as well as the raster step.

## What is not proved

- **No wallpaper has been observed on screen.** The machine this was written on
  runs a live Hyprland session that must not be reconfigured, so hyprpaper was
  never started against it and `hyprctl hyprpaper` was never run. The image is
  proved by reading its pixels, and the configuration by reading the program of
  the daemon.
- **`monitor =`, left empty, is read here as every display.** That is what the
  empty monitor meant in hyprpaper 0.7 and what the bundle asks for. It is not
  proved against 0.8.4, which has no offline check of its configuration.
- **The `source` line is not proved either.** hyprpaper resolves a `source`
  itself, and whether it resolves a relative one against the file it opened, as
  Hyprland does, was not established from the program. The bundle prescribes
  that form and it is followed.
- **No wallpaper has been seen changing on a running daemon either.** A theme
  switch now ends by sending `hyprctl hyprpaper wallpaper ,<image>` to a daemon
  that is already running. `hyprctl` 0.56.2 offers no hyprpaper `reload`
  request, and this one names an image: every theme writes its image to the same
  stable path, so the request names a path whose contents changed and whose name
  did not. **hyprpaper 0.8.4 reads that path again rather than drawing the image
  it holds**, which [the Hyprland bundle](bundles/hyprland.md) establishes from
  the program and from the library it is built on. That the request reaches the
  program with the right argument is observed against a stub; what the daemon
  then draws is reasoned. [Reloading](reloading.md) records both, and records
  what a build that drew **no** image sends, which is nothing.
