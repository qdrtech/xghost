# The SwayNC bundle

SwayNC is the notification centre of xghost. It draws every notification the
session raises, and the control centre behind the bell of the bar.

It is the one bundle whose application reads no include of any kind in its
configuration file, and the one whose style sheet reaches nothing and reports
nothing when the generated output is missing.

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
reports nothing. ADR 0002 records both facts, and it draws one conclusion from
them: that the whole file has to be generated output.

This bundle prescribes the file instead. The reason is that the conclusion
answers a question this bundle never asks.

> **No key of `config.json` follows a theme, a knob or a machine fact.** Every
> generated value of the notification centre is a colour or a font family, and
> both of those reach SwayNC through the style sheet, which is GTK4 CSS and does
> have `@import`.

A rendered `config.json` would therefore be a template with no substitution in
it: the same text for every theme, at every knob set, on every machine. It would
also need a way to reach the daemon, and there is exactly one. SwayNC looks for
the file at `$XDG_CONFIG_HOME/swaync/config.json` and then in the system config
directories, so a file under the state directory is found only by
`swaync -c <path>`. That path would be written into
`config/hypr/conf/autostart.conf`, and Hyprland expands `$XDG_STATE_HOME` there
to nothing when the variable is unset, which is the state of most machines. The
line would point at the root of the file system, SwayNC would fall back to the
packaged configuration, and nothing would say so.

So the prescribed file is not a way around the missing include. It is what the
missing include costs, and it costs nothing here:
`xghost config link` symlinks the directory, the file arrives at the path SwayNC
already looks in, and the project owns every line of it. That is
[ADR 0001](../adr/0001-prescribed-config-architecture.md) unchanged.

### What would flip this decision

One thing, and it is the whole of it:

> **A setting of `config.json` that has to follow a theme, a knob or a machine
> fact.** `positionX` and `positionY` are the candidates, because a notification
> in the same corner as the bar is a notification under the bar, and the bar
> moves with `KNOB_BAR_POSITION` today.

On the day such a setting arrives, this file becomes a template, and the render
gains a consumer that cannot read it. Delivering it then means either the
`swaync -c` path above, with the Hyprland expansion measured rather than
assumed, or a linker that places a link inside the config directory of a bundle
rather than over it. Neither is built here, because neither is needed here, and
a mechanism built before its first user is a mechanism that fits no user.

`tests/swaync.bats` holds that decision in place from the other side: it asserts
that the prescribed configuration names no palette value, no knob and no machine
fact. The day one of them appears, the test fails and sends the reader to this
section.

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

### GTK4 is silent where GTK3 is fatal

This is the one place where copying the Waybar bundle line for line would be
wrong, and the difference runs the other way from the one people expect.

| Style sheet     | GTK  | An `@import` that reaches nothing              |
| --------------- | ---- | ---------------------------------------------- |
| Waybar          | GTK3 | **fatal**: Waybar exits 1, and there is no bar |
| SwayNC          | GTK4 | **silent**: the daemon starts and draws unstyled |

Measured here, on GTK 4.22.4: `Gtk.CssProvider.load_from_path` returns normally
when an `@import` reaches nothing. The failure is delivered on the
`parsing-error` signal, which a caller has to connect before it sees anything at
all.

The consequence is the whole reason this page is careful about ordering. A
Waybar that starts too early is a missing bar, which nobody can overlook. A
SwayNC that starts too early is a notification centre in the packaged colours,
with nothing in any log, and the difference from a themed one is a shade of
grey.

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

## The colours the dotfiles never defined

The style sheet of the dotfiles named `@surface-alt`, `@text-muted` and
`@accent-alt`, with hyphens. The generated palette of this project defines
`surface_alt`, `text_muted` and `accent_alt`, with underscores. GTK allows both
characters in the identifier of an `@define-color`, so the three names of the
dotfiles were three names nothing defined.

Nothing downstream catches that. A `Gtk.CssProvider` that loads a sheet naming an
undefined colour reports no error at all — measured on GTK 4.22.4, and it is the
one case in this bundle that is silent even to a caller that connects the
`parsing-error` signal. The declaration is dropped and the widget draws in
whatever the packaged sheet left it.

Each one is now the underscored name the palette defines. `tests/swaync.bats`
reads every `@name` out of the style sheet and asserts that the generated palette
defines it, with a pattern that carries the hyphen, so a name that stopped at the
hyphen cannot pass by matching a shorter one.

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
reach nothing, and the style sheet still loads without a word.

## What changed from the dotfiles

Everything that is not a colour or a font family is carried over unchanged. The
rest is here.

| Change                                                    | Why                                                                    |
| --------------------------------------------------------- | ---------------------------------------------------------------------- |
| The three colour names carry underscores                  | See "The colours the dotfiles never defined" above. Three names of the style sheet resolved to nothing at every login. |
| `@import url("theme-colors.css")` is the bridge path       | `theme-colors.css` was written beside the style sheet by `scripts/theme-switch.sh`. This project writes the generated output under the state directory, and the bridge is how a prescribed file reaches it. |
| `font-family` is gone from the style sheet                 | It is `KNOB_FONT`, and a family here would overrule the generated one. `"SF Pro Text"` and `"SF Pro Display"` went with it: both are macOS families that no Arch machine carries. |
| `pactl` is `wpctl` in the two audio buttons                | This desktop runs wireplumber, which `install/packages/base.txt` declares, and `config/hypr/conf/keybinding.conf` already mutes with `wpctl`. `pactl` is in `libpulse`, which nothing here declares. One tool for one job. |
| `kitty nmtui` is `ghostty -e nmtui`                        | The terminal of this desktop, which `config/hypr/hyprland.conf` names as `$terminal`. This desktop ships no kitty at all, so the click would have opened nothing. It is the same correction [the Waybar bundle](waybar.md) made for the same button. |
| Three buttons that ran `kitty bash -i -c '…'` are dropped  | They ran `Docs`, `Settings` and `tasks`, which are shell functions of the person the dotfiles belong to. `config/zsh/.zshrc` defines none of them, so each button opened a terminal that printed `command not found` and closed. |
| The `gnome-network-displays` button is dropped             | No manifest of this project declares that package, and a button that runs a program the installation never installs is a button that reports nothing. |
| The `label` widget configuration is dropped                | `label` is in no `widgets` list, so it drew nothing. This bundle prescribes what ran. |
| `refresh.sh` is dropped                                    | It ran `pkill swaync; swaync`. Reloading every running component from one place is [issue #24](https://github.com/qdrtech/xghost/issues/24), and a reload built per bundle is one convention per bundle. |

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
  alone, the imports reach nothing and the sheet still loads.
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
  glyphs are carried over from a centre that ran in the dotfiles. Five of the
  twelve buttons are changed or dropped here, and none of the eight that remain
  has been clicked.
- **No exit code has been read, and no log line.** That an unknown key of
  `config.json` is dropped in silence is taken from ADR 0002 rather than from a
  run here.
- **The daemon has never been watched finding its files.** That SwayNC reads
  `$XDG_CONFIG_HOME/swaync/config.json` and `$XDG_CONFIG_HOME/swaync/style.css`
  is taken from `swaync(1)`, from the path fragments `swaync/config.json` and
  `swaync/style.css` in the binary, and from the GLib functions that join them.
  The GTK4 half of the same journey was measured directly.
- **A running centre is never restyled.** A theme switch and a knob change write
  the new files and stop. `swaync-client -rs` reloads the style sheet, and
  calling it belongs to [issue #24](https://github.com/qdrtech/xghost/issues/24),
  which owns one reload for every styling component.

A first session with this bundle is therefore the first test of it. Three
failures are the ones to look for:

- **Notifications in grey, with square icons.** An `@import` reached nothing.
  This is the failure that reports nothing anywhere, so it is the one to check
  first. `xghost theme set` and a fresh `swaync` tell it apart.
- **A notification in the old colours after a theme switch.** Expected today:
  the daemon holds the style sheet it started with, and issue #24 owns the
  reload.
- **A button that does nothing.** The program it names is missing from the
  machine, or it is a program this project never declared.
