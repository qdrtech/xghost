# The SwayNC bundle

SwayNC is the notification centre of xghost. It draws every notification the
session raises, and the control centre behind the bell of the bar.

It is the one bundle whose application reads no include of any kind in its
configuration file. Its style sheet does reach the generated output, and when it
cannot, GTK4 reports that once, at startup, on the standard error of the
daemon.

The bundle is two prescribed files and two generated ones:

| File                          | Category   | What it holds                                        |
| ----------------------------- | ---------- | ---------------------------------------------------- |
| `config/swaync/config.json`   | Prescribed | The daemon, the widgets and the buttons.             |
| `config/swaync/style.css`     | Prescribed | The styling, except the colours and the font family. |
| `templates/swaync/colors.css` | Template   | The palette of the theme, as GTK colours.            |
| `templates/swaync/knobs.css`  | Template   | The font family, from `KNOB_FONT`.                   |

The file categories are those of
[ADR 0001](../adr/0001-prescribed-config-architecture.md). The bridge to the
generated output is [ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md),
and the knobs are documented in [Knobs](../knobs.md).

Both prescribed files are carried over from `qdrtech/dotfiles`, path
`swaync/.config/swaync/`. What changed, and why, is recorded below.

## How the files meet

```
xghost config link     $XDG_CONFIG_HOME/swaync            -> <install location>/config/swaync
                       $XDG_CONFIG_HOME/xghost-generated  -> $XDG_STATE_HOME/xghost/generated
xghost theme set NAME  $XDG_STATE_HOME/xghost/generated/swaync/colors.css
                       $XDG_STATE_HOME/xghost/generated/swaync/knobs.css
```

`xghost settings set` writes the same two files, because a knob change renders
the same tree.

The second link is the **bridge**, the same one every other bundle uses. SwayNC
reaches the generated output through it once, from the style sheet, and it
reaches it by no other route: the configuration file has none to offer.

## The configuration file is prescribed, and that needs saying

SwayNC reads one `config.json` and offers **no include of any kind**. An unknown
key in it is dropped in silence, so a mistake in a key name costs a setting and
reports nothing at run time. ADR 0002 records both facts. It once drew a third
thing from them — that the whole file had to be generated output — and this
bundle is why that consequence was rewritten.

The silence is answered here rather than lived with. The file names the schema
the `swaync` package installs, and `tests/swaync.bats` reads the file against
it, so a key the daemon would drop fails a test on a machine that has swaync
instead of costing a setting on a machine that runs it.

This bundle prescribes the file instead, and the claim behind that is narrower
than the one ADR 0002 drew.

> **No key of `config.json` follows a theme.** Every colour of the notification
> centre, and its font family, reach SwayNC through the style sheet, which is
> GTK4 CSS and does have `@import`.

A knob and a machine fact are a different matter, and this file has one of each.
Both are named in "The two settings that do follow an input" below, and both are
pinned rather than generated. The reason is the same for both: a generated
`config.json` needs a way to reach the daemon, and there is exactly one. SwayNC looks for
the file at `$XDG_CONFIG_HOME/swaync/config.json` and then in the system config
directories, so a file under the state directory is found only by
`swaync -c <path>`. That path would be written into
`config/hypr/conf/autostart.conf`, and Hyprland expands `$XDG_STATE_HOME` there
to nothing when the variable is unset, which is the state of most machines. The
line would point at the root of the file system, SwayNC would fall back to the
packaged configuration, and nothing would say so.

So the prescribed file is not a way around the missing include. It is what the
missing include costs, and here it costs two settings rather than nothing.
`xghost config link` symlinks the directory, the file arrives at the path SwayNC
already looks in, and the project owns every line of it. That is
[ADR 0001](../adr/0001-prescribed-config-architecture.md) unchanged, with the
price written down below rather than left out.

### The two settings that do follow an input

The condition that would flip this decision is not hypothetical, and it is not
in the future. Two settings of `config.json` already follow an input this
project has, and no include can carry either of them.

**The corner follows `KNOB_BAR_POSITION`.** `positionY` is `bottom` and
`positionX` is `left`. `schema/knobs.conf` declares `KNOB_BAR_POSITION` with the
values `top` and `bottom`, and it defaults to `top`, so a machine that changes
nothing has the bar at one edge and the notifications at the other. Set the knob
to `bottom` and the two meet. `config/waybar/config` puts the bar on the `top`
layer, `layer` here is `overlay`, and `overlay` draws above `top`, so a
notification covers the bar. `control-center-margin-left` and
`control-center-margin-right` are the same dependency in x. The knob names no
side edge today, so neither margin has a value to follow yet.

**The backlight device is a machine fact.** The `backlight` widget takes a
`device` key that names an entry of `/sys/class/backlight`, and the packaged
schema defaults it to `intel_backlight`. On the machine this bundle was written
on, `/sys/class/backlight` is empty, so the widget would draw a brightness
slider for a device that is not there.

What this bundle does about each, and what each choice costs:

| Setting                  | What it does here                | What it costs                                               |
| ------------------------ | -------------------------------- | ----------------------------------------------------------- |
| `positionX`, `positionY` | Pinned to the bottom left corner | At `KNOB_BAR_POSITION=bottom` a notification covers the bar. |
| The `backlight` widget   | Not shipped                      | A laptop gets no brightness slider in the control centre.    |

Neither is repaired here, for one reason that covers both. Delivering either
means a generated `config.json`, and that means one of two mechanisms: the
`swaync -c` path above, with the Hyprland expansion measured rather than
assumed, or a linker that places a link inside the config directory of a bundle
rather than over it. The second changes the linker for every bundle. Both are
larger than this bundle, and both are worth building once, for both settings, in
one place.

**Neither has an issue yet, and both need one.** Until then this section is the
record, and the first is held by a test.

`tests/swaync.bats` reads `positionY` out of the prescribed file and the default
of `KNOB_BAR_POSITION` out of the schema, and it fails when the two name the
same edge. So a change to the default of the knob fails the suite rather than
shipping a desktop whose notifications sit on the bar.

### What the placeholder test can and cannot catch

`tests/swaync.bats` also asserts that the prescribed configuration writes no
palette value, no `KNOB_` name and no `MACHINE_` name. That test greps for the
text of a placeholder, so what it catches is a template marker pasted into a
prescribed file.

**It cannot catch a semantic dependency**, and that is how both settings above
passed it. `positionY: "bottom"` follows a knob without spelling one, and
`intel_backlight` is a machine fact without spelling one. A dependency of that
kind needs a test written for it by name, the way the corner now has one.

### The file the renderer must never read

Two buttons of the control centre carry the name wireplumber gives the default
audio device:

```json
"command": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
```

`@DEFAULT_AUDIO_SINK@` is also, exactly, the spelling the renderer substitutes:
an upper case name between two `@`. A template holding that line would fail the
render, because no palette, no fact and no knob declares `DEFAULT_AUDIO_SINK`.
`tests/swaync.bats` asserts that the text is in the prescribed file and in no
template, so the two can never be confused.

## The style sheet has one form available, and this is it

```css
@import "../xghost-generated/swaync/colors.css";
@import "../xghost-generated/swaync/knobs.css";
```

GTK expands neither an environment variable nor `~` in an `@import`, in GTK4 as
in GTK3, so a path that named either would be read as literal text and would
reach nothing. The relative path is the only form available. GTK resolves it
against the directory of the file that imports it, and SwayNC opens the style
sheet at `$XDG_CONFIG_HOME/swaync/style.css`, which is the link
`xghost config link` made. `..` is therefore the config directory of the user,
where the bridge is.

That resolution is **lexical**. `xghost config link` makes
`$XDG_CONFIG_HOME/swaync` a symbolic link into the checkout, so a `..` applied
physically would land in `<install location>/config`, which is the directory
ADR 0002 forbids the checkout to hold generated output in. It was measured
rather than assumed: a `Gtk.CssProvider` loading the linked style sheet reports
the palette of the active theme, and `to_string()` shows the imported
`@define-color` lines inside it. `tests/swaync.bats` runs that measurement.

Neither end of the path is written out in full: the directory it starts from
moves with `XDG_CONFIG_HOME`, and the bridge moves with `XDG_STATE_HOME`.

### GTK4 reports once where GTK3 stops the bar

This is the one place where copying the Waybar bundle line for line would be
wrong, though the difference is smaller than it first looks.

| Style sheet | GTK  | An `@import` that reaches nothing                               |
| ----------- | ---- | ---------------------------------------------------------------- |
| Waybar      | GTK3 | **fatal**: Waybar exits 1, and there is no bar                   |
| SwayNC      | GTK4 | **one warning**: the daemon starts, draws unstyled, and runs on  |

Measured here on GTK 4.22.4, with **no handler connected**, which is the case
the daemon takes:

```
Gtk-WARNING **: Theme parser error: style.css:1:1-49: Failed to import: Error
opening file …/xghost-generated/swaync/colors.css: No such file or directory
```

`Gtk.CssProvider.load_from_path` returns normally, and the failure is delivered
on the `parsing-error` signal. GTK attaches a **default** handler to that
signal, and the default handler is what prints the line above, with the file,
the line and the column range in it. Connecting a handler of your own
**suppresses** the default one, so a probe that connects a handler measures the
one case SwayNC never takes.

SwayNC 0.12.6 connects none. `strings -a /usr/bin/swaync` holds no
`parsing-error` at all, while `nm -D --undefined-only /usr/bin/swaync` names
five CSS symbols: it uses the CSS provider and it leaves the signal alone.

So the failure is reported, and it is reported well enough to fix from. What it
does not do is stop anything. It is one line on the standard error of the
daemon, written once when the sheet is parsed at startup, and the notification
centre then runs for the whole session in the packaged colours. A daemon that
SwayNC's own systemd user unit started writes that line to the journal under
`swaync.service`. A daemon that `exec-once` started writes it wherever the
compositor sends the standard error of its children.

The consequence for ordering is unchanged, and only its reason moves. A Waybar
that starts too early is a missing bar, which nobody can overlook. A SwayNC that
starts too early is a notification centre in the packaged colours with one
warning line in a log nobody reads during a login, and the difference from a
themed one is a shade of grey.

### What GTK version the style sheet needs

GTK reports an unknown property and an unknown selector exactly the way it
reports a failed import, so what a sheet says about itself depends on the GTK
reading it. This one is written to the oldest GTK that can theme the
notification centre at all.

The sheet uses one construct an older GTK4 rejects: `:root`, which arrived in
GTK 4.16. That boundary is not this bundle's to avoid. The packaged style sheet
of swaync 0.12.6 is itself built on `:root` and reads `var(--…)` 77 times, so a
GTK too old to parse `:root` leaves the notification centre unthemed before this
project touches it.

Everything else in the sheet is older than that. `backdrop-filter` was the
exception, and it is gone. It needs GTK 4.20, and it bought nothing here: this
desktop blurs nothing at all. `config/hypr/conf/decoration.conf` sets
`blur { enabled = false }` and `config/hypr/conf/layerrule.conf` carries no rule
for this surface, both with the reason written out, so a blur in this file would
have contradicted a decision the project had already made twice.

The runner of `.github/workflows/ci.yml` is Ubuntu, and its GTK4 is older than
4.16. That is a second reading rather than a problem. It is a GTK that rejects
anything newer than itself, so reading its diagnostics catches a construct this
machine would have accepted without a word. `tests/swaync.bats` accounts for the
`:root` block by name and fails on a diagnostic about anything else, which is
what catches `backdrop-filter` if it ever comes back.

## The rule of this bundle: the importing file wins

A rule of the importing file wins over a rule of the same weight in the file it
imported, and the imports are at the top. So a property the generated files set
must be absent from `style.css`, or the generated value would be overruled and
the theme, or the knob, would change nothing.

`style.css` therefore names no colour of its own beyond the black of a shadow,
and no font family at all. `tests/swaync.bats` reads every prescribed file and
every template of the whole project and asserts that `font-family` is written in
one file, so the setting cannot be added to a third one, and it proves that
guard by evading it in a copy of the checkout.

## The colour names carry underscores here

The style sheet of the dotfiles named `@surface-alt` and `@text-muted`, with
hyphens, and `scripts/theme-switch.sh` wrote a `theme-colors.css` beside it that
defined `surface-alt` and `text-muted` with hyphens to match. The two agreed.
The generated palette of this project defines `surface_alt` and `text_muted`,
with underscores, because that is the spelling `themes/<name>/palette.conf` uses
and every other bundle takes it unchanged.

So this is a naming convention that changed, and not a fault that was found.
GTK allows both characters in the identifier of an `@define-color`, so neither
spelling is wrong on its own. What would be wrong is a sheet on one convention
reading a palette on the other, and that is the mistake this project is one
paste away from making.

It reports nothing at all. A `Gtk.CssProvider` that loads a sheet naming an
undefined colour reports no error — measured on GTK 4.22.4 with a handler
connected and again with none, and it is the one failure of this bundle that
neither route reports. The declaration is dropped and the widget draws in
whatever the packaged sheet left it. An `@import` that reaches nothing is
reported; a colour name that reaches nothing is not.

`tests/swaync.bats` reads every `@name` out of the style sheet and asserts that
the generated palette defines it, with a pattern that carries the hyphen, so a
name written the old way cannot pass by matching a shorter one that exists.

## The font of the centre is the font of the desktop

`KNOB_FONT` reaches `generated/swaync/knobs.css`, which sets one family on `*`.
The dotfiles set `"SF Pro Text"` there and `"SF Pro Display"` on the summary of a
notification, and both are macOS families that no Arch machine carries, so both
fell back to a font nobody chose.

The family is a knob rather than a prescribed line for the reason the bar has it:
one desktop draws in one family, and a machine that changes the family expects
the notification to follow. [Knobs](../knobs.md) records where each knob lands.

## The notifications are styled from the first login

The installer runs `xghost config link`, then `xghost machine detect`, then
`xghost theme set`, and every one of them runs before the first session starts.
[Installing](../installing.md) records that order. By the time the autostart of
the compositor runs `swaync`, the bridge is in place and both generated files
are written, so the notification centre comes up themed with no step of its own.

The daemon is started twice over, and both routes end after the render:

- `config/hypr/conf/autostart.conf` holds `exec-once = swaync`, which runs when
  the session starts.
- SwayNC is D-Bus activatable. `org.erikreider.swaync.service` claims
  `org.freedesktop.Notifications`, so a program that raises the first
  notification starts the daemon on its own, and
  `org.erikreider.swaync.cc.service` does the same for the bell of the bar.

The explicit line is what this project relies on. The activation is what makes
the ordering safe rather than lucky: neither route can run before the session,
and the session cannot start before the installer has finished.

`tests/swaync.bats` proves the order from both ends. After link, detect and
render, every path the daemon reads is a file. After link alone, both imports
reach nothing, GTK writes one warning about it, and the style sheet loads
anyway.

## What changed from the dotfiles

Everything that is not a colour or a font family is carried over unchanged. The
rest is here.

| Change                                                    | Why                                                                    |
| --------------------------------------------------------- | ---------------------------------------------------------------------- |
| The two colour names carry underscores                     | See "The colour names carry underscores here" above. The dotfiles were self-consistent on hyphens; the palette of this project is on underscores, and the style sheet follows the palette. |
| `@import url("theme-colors.css")` is the bridge path       | `theme-colors.css` was written beside the style sheet by `scripts/theme-switch.sh`. This project writes the generated output under the state directory, and the bridge is how a prescribed file reaches it. |
| `font-family` is gone from the style sheet                 | It is `KNOB_FONT`, and a family here would overrule the generated one. `"SF Pro Text"` and `"SF Pro Display"` went with it: both are macOS families that no Arch machine carries. |
| `pactl` is `wpctl` in the two audio buttons                | This desktop runs wireplumber, which `install/packages/base.txt` declares, and `config/hypr/conf/keybinding.conf` already mutes with `wpctl`. `pactl` is in `libpulse`, which nothing here declares. One tool for one job. |
| `kitty nmtui` is `ghostty -e nmtui`                        | The terminal of this desktop, which `config/hypr/hyprland.conf` names as `$terminal`. This desktop ships no kitty at all, so the click would have opened nothing. It is the same correction [the Waybar bundle](waybar.md) made for the same button. |
| Three buttons that ran `kitty bash -i -c '…'` are dropped  | They ran `Docs`, `Settings` and `tasks`, which are shell functions of the person the dotfiles belong to. `config/zsh/.zshrc` defines none of them, so each button opened a terminal that printed `command not found` and closed. |
| The `gnome-network-displays` button is dropped             | No manifest of this project declares that package, and a button that runs a program the installation never installs is a button that reports nothing. |
| The `label` widget configuration is dropped                | `label` is in no `widgets` list, so it drew nothing. This bundle prescribes what ran. |
| `image-visibility` is `when-available`                     | The dotfiles wrote `when available`, with a space. The schema this file names enumerates `always`, `when-available` and `never`, so the value matched none of them, the setting was discarded, and the default applied. Nothing said so. |
| `timeout-critical` is `0`                                  | The dotfiles wrote `1`, which gave the most urgent notification one second on screen against 6 for low and 12 for normal. `swaync(5)` documents the default as `0` and reads `0` as "disable", so a critical notification now stays until it is dismissed. |
| `notification-body-image-width` is `200`                   | The dotfiles wrote `180`. The schema sets a minimum of `200` on that key, so the value was out of range. |
| The `mpris` widget configuration is dropped                | It set `image-radius`, which is not a property of that widget and which `additionalProperties: false` rejects, and `image-size`, which the schema marks deprecated in favour of the CSS root variable `--mpris-album-art-icon-size`. `style.css` sets that variable now, so the size survives and the two dropped keys do not. |
| The `backlight` widget is dropped                          | Its `device` key names an entry of `/sys/class/backlight`, which is a machine fact, and a file with no include cannot follow one. See "The two settings that do follow an input" above. |
| `backdrop-filter` is dropped from both rules                | The dotfiles blurred behind the notification and the control centre. This desktop blurs nothing: `config/hypr/conf/decoration.conf` switches the compositor blur off and `config/hypr/conf/layerrule.conf` carries no rule for this surface, both on purpose. The property also needs GTK 4.20, which is newer than anything else this sheet asks for. The translucency stays; only the blur goes. |
| `refresh.sh` is dropped                                    | It ran `pkill swaync; swaync`, which is a restart rather than a reload. Reloading every running component from one place is [Reloading](../reloading.md), and it sends `swaync-client -rs` to a daemon it has already asked to be sure is running. A reload built per bundle is one convention per bundle. |

## The packages this bundle needs

| Package  | Repository | What needs it                                                          |
| -------- | ---------- | ---------------------------------------------------------------------- |
| `swaync` | `extra`    | The daemon, the control centre, and the `swaync-client` the bell of the bar runs. |

Every package above is declared in `install/packages/base.txt`, and
`tests/install.bats` fails when a package this table lists is in no manifest.
[Installing](../installing.md) records the manifest.

The table has one row, and the rest of the row is the point of it. Every program
the buttons of the control centre run is declared already, by the bundle that
needed it first: `wireplumber` for `wpctl`, `ghostty` for the terminal,
`networkmanager` for the `nmtui` inside it, `blueman` for `blueman-manager`, and
`hyprlock`. Nothing is declared twice.

`gtk4` and `libpulse` are not here either. Both are hard dependencies of the
`swaync` package, so declaring either would say that this project chose it.

## What the tests prove

- `tests/swaync.bats` proves the bundle. It reads the prescribed configuration
  as JSON, follows the CSS import through the bridge the way GTK follows it, and
  does that with both `XDG_CONFIG_HOME` and `XDG_STATE_HOME` moved away from
  their defaults, which is the case ADR 0002 asks every bundle after Ghostty for
  by name. It loads the linked style sheet into a `Gtk.CssProvider` and reads the
  palette of the active theme back out of it, so the import is proved to have
  resolved rather than to have raised no error. It proves that every colour the
  style sheet names is defined by the generated palette, that the style sheet
  defines no colour and names no font family, that the knob reaches the output at
  every value the schema names, that the prescribed configuration names no
  palette value and no knob, and that `@DEFAULT_AUDIO_SINK@` is in the prescribed
  file and in no template. Two tests are the order of an installation: after
  link, detect and render, every path the daemon reads is a file; after link
  alone, the imports reach nothing, GTK reports it once, and the sheet loads
  anyway.
- Three of those tests are measurements rather than readings, and each carries a
  positive control. The GTK4 tests load a sheet whose imports resolve first, and
  assert on a marker that only a parsed file can produce, so an empty warning
  stream cannot pass for a clean parse. They **fail** rather than skip when
  `XGHOST_REQUIRE_GTK4` is set, which the CI workflow sets, so the machine that
  gates a merge can never report the measurement as a skip.
- `tests/swaync.bats` validates the prescribed configuration against
  `/etc/xdg/swaync/configSchema.json`, the schema the file names, whenever the
  `swaync` package has installed it. That is what catches a key the daemon would
  drop, a value outside an enumeration, and a number outside a range. It skips
  on a machine with no `swaync` installed, and it says so.
- `tests/swaync.bats` reads `positionY` out of the prescribed file and the
  default of `KNOB_BAR_POSITION` out of the schema, and fails when the two name
  the same edge. It is the one semantic dependency of this file that has a test
  of its own.
- The tests that measure the bridge count the diagnostics that say
  `Failed to import` and read no other. A diagnostic about a property or a
  selector is a different claim and moves with the GTK version, so counting
  every warning would fail those tests on a runner for something they never set
  out to measure. The **count** is what is read, not the presence of a warning:
  two imports reach nothing, so two failures are required, and a GTK that
  reported one of the two fails as loudly as one that reported neither. The
  handler test reads the same count on both sides, so it measures a report that
  moved rather than one that merely appeared somewhere.
- Everything those counters drop is watched by a test of its own. With both
  imports resolved, every diagnostic GTK produces about the sheet has to fall
  inside the `:root` block, which holds one declaration and is asserted to hold
  one, and anything else anywhere fails. That test carries a control for its own
  detector: it feeds the same probe a property no GTK knows and requires it to
  be reported, so an empty list can never pass for a clean parse.
- `tests/golden.bats` compares the rendered colours and font family of every
  theme with the committed output under
  `tests/golden/<knob set>/<theme>/swaync/`, and `tests/swaync.bats` reads those
  same committed files, so the palette of each theme and both values of
  `KNOB_FONT` are pinned to text rather than to a render.
- `tests/install.bats` reads the package table above and fails when a package it
  lists is declared by no manifest.

## What this bundle has never been observed doing

**SwayNC has never run against it.** No daemon was started, because the machine
it was written on runs a live session with a notification daemon of its own, and
starting a second one would take the D-Bus name from it. Every claim above is
proved by rendering, by reading the two prescribed files as the data they are, by
resolving each path the way GTK 4 resolves it, and by loading the style sheet
into a `Gtk.CssProvider`, which parses one without a window and without a
compositor.

What that leaves unobserved:

- **No notification has ever been seen on a screen.** Nothing on this page was
  read off a display. The acceptance criterion "notifications appear styled
  immediately after installation" is proved as an ordering — every file the
  daemon reads is in place before the session that starts the daemon — and not as
  an observation. Raising a notification needs a running daemon, and the running
  one belongs to the maintainer.
- **The control centre has never drawn.** The widgets, the buttons and their
  glyphs are carried over from a centre that ran in the dotfiles. Seven of the
  twelve buttons are changed or dropped here — four dropped and three changed —
  and none of the eight that remain has been clicked.
- **Most of the control centre still draws in SwayNC's own white.** The
  packaged 0.12.6 style sheet themes through `:root` custom properties.
  `--text-color` is `rgb(255, 255, 255)` and is read 14 times, and `--cc-bg`,
  `--noti-bg`, `--noti-bg-hover` and `--noti-close-bg` carry the greys beside
  it. Its `@define-color` block is labelled "Fallback for older CSS themes".
  This bundle sets none of those variables and names ten classes of its own, so
  every widget outside those ten keeps the packaged value. That is survivable
  while both themes of this project are dark. On a light theme it is white text
  on a light background, and no light theme exists yet.
- **No exit code has been read, and no log line of a running daemon.** The
  `Gtk-WARNING` above was measured from a `Gtk.CssProvider` in this suite, not
  read out of a log that `swaync` wrote. Which log it lands in on the
  `exec-once` route follows from how a compositor passes standard error to a
  child, and was not observed. That an unknown key of `config.json` is dropped
  in silence is taken from ADR 0002 rather than from a run here.
- **The daemon has never been watched finding its files.** That SwayNC reads
  `$XDG_CONFIG_HOME/swaync/config.json` and `$XDG_CONFIG_HOME/swaync/style.css`
  is taken from `swaync(1)`, from the path fragments `swaync/config.json` and
  `swaync/style.css` in the binary, and from the GLib functions that join them.
  The GTK4 half of the same journey was measured directly.
- **A running centre has never been watched being restyled.** A theme switch and
  a knob change now send `swaync-client -rs`, which reloads the style sheet, and
  [Reloading](../reloading.md) owns the call. It sends `-rs` and not `-R`,
  because `config.json` is prescribed here and no key of it follows a palette, a
  knob or a machine fact. That page also records why the daemon is asked whether
  it is running first: the `swaync` package ships an activatable D-Bus name, so a
  client call with no daemon running would start one.

A first session with this bundle is therefore the first test of it. Three
failures are the ones to look for:

- **Notifications in grey, with square icons.** An `@import` reached nothing.
  There is one `Gtk-WARNING` about it, written when the daemon started, so the
  log of the session names the file and the line. `xghost theme set` and a fresh
  `swaync` fix it.
- **A notification in the old colours after a theme switch.** The reload was
  sent and the daemon did not take it, or the daemon was not running when the
  switch happened. `xghost system reload` sends it again and names what each
  component answered.
- **A button that does nothing.** The program it names is missing from the
  machine, or it is a program this project never declared.
