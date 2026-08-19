# The Waybar bundle

Waybar is the status bar of xghost. It is the first bundle whose generated
configuration can be overruled by the file that includes it, and the first one
whose style sheet stops the application from starting when a file is missing.

The bundle is two prescribed files and three generated ones:

| File                            | Category   | What it holds                                        |
| ------------------------------- | ---------- | ---------------------------------------------------- |
| `config/waybar/config`          | Prescribed | The bar and every module, except the position.       |
| `config/waybar/style.css`       | Prescribed | The styling, except the colours and the font family. |
| `templates/waybar/colors.css`   | Template   | The palette of the theme, as GTK colours.            |
| `templates/waybar/knobs.css`    | Template   | The font family, from `KNOB_FONT`.                   |
| `templates/waybar/position.json`| Template   | The position of the bar, from `KNOB_BAR_POSITION`.   |

The file categories are those of
[ADR 0001](../adr/0001-prescribed-config-architecture.md). The bridge to the
generated output is [ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md),
and the knobs are documented in [Knobs](../knobs.md).

Both prescribed files are carried over from `qdrtech/dotfiles`, path
`waybar/.config/waybar/`. What changed, and why, is recorded below.

## How the files meet

```
xghost config link     $XDG_CONFIG_HOME/waybar           -> <install location>/config/waybar
                       $XDG_CONFIG_HOME/xghost-generated -> $XDG_STATE_HOME/xghost/generated
xghost theme set NAME  $XDG_STATE_HOME/xghost/generated/waybar/colors.css
                       $XDG_STATE_HOME/xghost/generated/waybar/knobs.css
                       $XDG_STATE_HOME/xghost/generated/waybar/position.json
```

`xghost settings set` writes the same three files, because a knob change renders
the same tree.

The second link is the **bridge**, the same one
[the Ghostty bundle](ghostty.md) and [the Hyprland bundle](hyprland.md) use.
Waybar reaches the generated output through it twice, and by two different
routes, because the two halves of Waybar read two different kinds of file.

## The rule of this bundle: the including file wins

Hyprland applies an included file **after** the file that sourced it, so a
generated file wins over everything above it. Waybar does the opposite. It
merges an included file into the file that includes it and **keeps the value the
including file already holds**.

The consequence is one rule, and getting it backwards is a theme that is
silently inert:

> **A key the generated configuration sets must be absent from the prescribed
> file.** The prescribed file therefore holds every setting of this bar except
> `position`, and `position` appears in exactly one file of the project:
> `templates/waybar/position.json`.

The style sheet lives by the same rule for a second reason. An `@import` has to
come before the rules that use the colours it defines, and a rule of the
importing file wins over a rule of the same weight above it. So the imports are
at the top of `style.css`, and every property the generated files set is absent
from `style.css`: it names no colour of its own beyond the greys of a shadow,
and no font family at all.

Both halves are therefore the same sentence: **the generated file supplies what
the prescribed file leaves out, and never what it sets.**

`tests/waybar.bats` reads every prescribed file and every template and asserts
that `"position"` is written in one file and `font-family` in one file. A guard
that named the two paths by hand would pass with the setting added to a third
file.

## The two routes to the generated output

| Half of Waybar          | Directive       | Expands `$VAR`?          | Expands `~`? | A target that is missing |
| ----------------------- | --------------- | ------------------------ | ------------ | ------------------------ |
| The configuration file  | `include` array | yes, through `wordexp(3)`| yes          | loud: `spdlog::warn`, and it prints |
| The style sheet, GTK3   | CSS `@import`   | **no**                   | **no**       | **fatal: Waybar exits 1** |

### The style sheet has one form available, and this is it

```css
@import "../xghost-generated/waybar/colors.css";
@import "../xghost-generated/waybar/knobs.css";
```

GTK expands neither an environment variable nor `~` in an `@import`, so a path
that named either would be read as literal text and would reach nothing. The
relative path is the only form available. GTK resolves it against the directory
of the file that imports it, and Waybar opens the style sheet at
`$XDG_CONFIG_HOME/waybar/style.css`, which is the link `xghost config link`
made. `..` is therefore the config directory of the user, where the bridge is.

Neither end of that path is written out in full: the directory it starts from
moves with `XDG_CONFIG_HOME`, and the bridge moves with `XDG_STATE_HOME`.

### The configuration file names the bridge through the variable

```json
"include": ["\"${XDG_CONFIG_HOME:-$HOME/.config}/xghost-generated/waybar/position.json\""]
```

This is the one place where the bundle writes a form that ADR 0002 does not, and
the reason is the resolution rule of this directive rather than a preference.

Waybar hands an include path to `wordexp(3)` and then tests the result with
`access(2)`. It does not resolve the path against the directory of the
configuration file, the way GTK, Ghostty and Hyprland each resolve theirs. A
relative include would therefore be read against the working directory of the
bar, which is the working directory the compositor happened to pass it, and the
path would be right or wrong by accident.

So the include names the bridge rather than reaching it relatively. The
construction of ADR 0002 is unchanged in every other respect: the state
directory is never written out, both ends of the path follow the environment,
and the path travels through the one link `xghost config link` creates.

`wordexp` is full shell word expansion, which is why `${XDG_CONFIG_HOME:-…}`
works here and works in no other bundle. ADR 0002 records the shell as the only
entry of its table that can express the XDG default inline; the Waybar include
array is the second, and for the same reason.

Three details of that line, and each one is a failure it prevents:

- **The path carries its own quotation marks.** `wordexp` splits its result into
  fields and expands a glob. A home directory that holds a space would reach
  Waybar as its first field alone, and one that holds a bracket would be read as
  a pattern. The quotation marks are inside the JSON string, escaped as `\"`,
  and they leave `wordexp` with exactly one word.
- **`XDG_CONFIG_HOME` is unset on most machines,** and `$XDG_CONFIG_HOME/…`
  alone would then expand to a path that starts at the root of the file system.
  The default of the XDG base directory specification is written into the
  expansion for that case.
- **The path is a constant of the project, and it has to stay one.** `wordexp`
  is called with flags `0`, so `WRDE_NOCMD` is unset and a command substitution
  inside an include path runs. No value from a theme, from the knobs, or from
  any other source a user writes may reach that line. ADR 0002 records it.

## The bar is styled from the first login

The installer runs `xghost config link`, then `xghost machine detect`, then
`xghost theme set`, and every one of them runs before the first session starts.
[Installing](../installing.md) records that order. By the time the autostart of
the compositor runs `waybar`, the bridge is in place and all three generated
files are written, so the bar comes up themed with no step of its own.

That ordering is a **requirement** here rather than a nicety, and Waybar is
louder about it than any other application this project prescribes:

> A GTK `@import` that reaches nothing is fatal. A bar started between the link
> step and the render step does not come up unthemed; it does not come up at
> all, and it exits 1.

The bundle keeps that behaviour rather than working around it, for the reason
[the Hyprland bundle](hyprland.md) keeps its own loud include: there is no
useful half-styled bar here. The colours, the font and the position are all
generated, so a bar that started without them would carry the GTK default
styling, which is a grey strip that looks like a fault. There is no optional
import to soften it, the way `config-file = ?…` softens the Ghostty include, and
GTK offers none.

## The bar position is a scalar knob

`KNOB_BAR_POSITION` takes `top` and `bottom`, and the default is `top`, which is
the position the bar had in the dotfiles. The user-facing name is the name of
the knob:

```
xghost settings set KNOB_BAR_POSITION bottom
```

[Issue #12](https://github.com/qdrtech/xghost/issues/12) names the command as
`xghost settings set bar-position top`. `xghost settings set` takes the name the
schema declares, and every knob of that schema is `KNOB_<NAME>`, so the knob is
`KNOB_BAR_POSITION` and the command above is the one that runs. One name for one
knob is the rule; a second, shorter spelling would be a second name to keep
right in the schema, in the completion and in every page that names it.

The knob is a **scalar**, and the alternative was a structural choice. Both
mechanisms exist and [Knobs](../knobs.md) documents them. The decision:

| Mechanism             | What it would produce here                                                    |
| --------------------- | ----------------------------------------------------------------------------- |
| **Scalar. Chosen.**   | One template, `position.json`, holding `"position": "@KNOB_BAR_POSITION@"`.   |
| Structural choice     | `position.json.choice.KNOB_BAR_POSITION/` holding `top` and `bottom`, two files that differ in one word. |

A structural choice earns its keep when a value selects a block rather than a
word. `KNOB_ANIMATIONS` is the case it was built for: switching the animations
off is switching off a dozen lines. The bar position is one word of one key, so
two fragments would be two nearly identical files, and adding a third position
would mean a third one.

The argument on the other side was the styling: a bar that moves may need the
matching CSS, and rounded corners or margins that follow the edge of the screen
would be a block rather than a word. **The style sheet of this bundle has no
such property.** Every module box carries `margin: 10px` and
`border-radius: 8px` on all four sides, and the shadow is `0px 0px 6px`, with no
offset. Each one is symmetric, so each one is already right at both edges of the
screen. A structural choice would therefore ship two CSS fragments that are the
same text, which is a stub with a mechanism around it.

What would flip this decision, and it is one file either way:

- A value of `left` or `right`. Waybar draws those, and the bar is then a
  column: the module boxes stretch the wrong way, and the drawer of
  `group/expand` opens across the screen rather than along the bar. That is a
  block of styling per value, which is what a structural choice is for. The
  schema names two values today for exactly that reason, and it says so.
- Any styling that follows the edge, such as a directional shadow or a bar that
  sits flush against it.

`tests/waybar.bats` renders the knob at every value the schema names and reads
the position back out of the generated JSON, so a value that reached no file
would fail there. `tests/golden.bats` compares the committed output of every
theme at both positions, which is every theme at every bar position.

## The terminal of the bar is the terminal of the desktop

Two modules open a terminal: the network module runs `nmtui`, and the package
module runs the upgrade. Both name `ghostty`, which is what
`config/hypr/hyprland.conf` names as `$terminal`. The dotfiles named `kitty` in
both, and this desktop ships no kitty at all, so both clicks would have failed
with no window and no message.

The terminal is **prescribed**, and it is not read from the machine facts.
`MACHINE_TERMINAL` is a fact of the machine rather than a choice of this
project, and detection writes `unknown` for it on a machine that declares no
default terminal, which is the state of a fresh Arch installation. The renderer
refuses to write that word, so a template that named the fact would fail the
render on exactly the machine an installation starts from. The fact answers
"what does this machine open" and this bundle needs the answer to "what does
this desktop ship", which is the terminal of
[the Ghostty bundle](ghostty.md).

`tests/waybar.bats` reads `$terminal` out of the Hyprland entry point and
asserts that both commands start with it, so the two files cannot drift apart.

## What changed from the dotfiles

Everything that is not a colour, a position or a font family is carried over
unchanged. The rest is here.

| Change                                                        | Why                                                                    |
| ------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `position` is gone from the configuration file                | It is the knob, and a `position` here would overrule the generated one. |
| The four colours the style sheet named are the palette         | See "The colours the dotfiles never defined" below.                    |
| `font-family` is gone from the style sheet                     | It is `KNOB_FONT`, and a family here would overrule the generated one. `"SF Pro Display"` went with it: it is a macOS font that no Arch machine carries. |
| The white of the drawer arrow under the pointer is `@text`      | `rgba(255, 255, 255, 0.2)` is a colour of the style sheet rather than of the theme, which the rule at the top of that file forbids. It matches the rule directly above it, which already wrote `alpha(@text, 0.2)`. Both shipped themes are dark, so the two look alike today and would part company on a light one. |
| `kitty` is `ghostty` in two modules                            | The terminal of this desktop. See above.                               |
| `yay -Syu` is `sudo pacman -Syu`                               | xghost installs no AUR helper, and it says so in `install/packages/aur.txt`. A button that runs a program the installation never installs is a button that reports `command not found` into a terminal that then closes. `checkupdates` counts official packages in any case. |
| `"interval": 30` on `custom/pacman` is `"interval": 3600`      | The interval is counted in seconds, and `checkupdates` runs `fakeroot -- pacman -Sy` against a private database, which is a synchronisation over the network. At 30 seconds the bar reaches the Arch mirrors 2880 times a day per session, holds the radio of a portable machine awake, and overlaps its own runs over that one database whenever a run outlives the interval. One hour is the interval the examples of Waybar use. `"signal": 8` is kept, so the count is still immediate after an upgrade. |
| The colour picker module is dropped                            | It ran `~/.config/waybar/scripts/colorpicker.sh`, which is a script file this project does not ship, and the script read the colour cache of pywal, which this project does not use. It also needed two packages of its own. |
| The battery module is dropped                                  | It was defined and named in no module list, so it drew nothing. This bundle prescribes what ran. Putting it back is one entry in `group/expand` and the block from the history of the dotfiles. |
| `persistent-workspaces` is dropped                             | See "The workspaces the bar shows" below.                              |
| The calendar drops `<span color='#fAfBfC'>`                    | A colour written into the configuration file follows no theme, and the tooltip is Pango markup, which no style sheet can reach. The bold that marked today is kept. |
| `tooltip-format-disconnected` is `Disconnected` rather than `Error` | A network that is switched off is not an error, and the tooltip is what the user reads. |
| Two keys that do nothing are dropped                           | `escape` on a module with no `exec`, and `exec-if: exit 0`, which always succeeds. |
| `reload_style_on_change` is dropped                            | It cannot reach the generated imports of this bundle. See "What this bundle has never been observed doing" below, which records the two paths that were measured. |
| The three scripts of the dotfiles are dropped                  | `launch.sh` killed the bar and started it again, and chose the configuration by user name; `refresh.sh` was a toggle nothing ran; `colorpicker.sh` is the module above. The compositor starts the bar with `exec-once = waybar`, and the keybinding that restarts it is in `conf/keybinding.conf`. |

### The colours the dotfiles never defined

The style sheet of the dotfiles named `@color7`, `@color8`, `@color9` and
`@foreground`. The generated `theme-colors.css` beside it defined none of those
four: it defined `bg`, `surface`, `text`, `accent` and the rest of the palette.
Four names of the style sheet therefore resolved to nothing at every login.

Each one is now the palette name that carries the same meaning:

| The dotfiles wrote | This bundle writes | Where it draws                                              |
| ------------------ | ------------------ | ----------------------------------------------------------- |
| `@color7`          | `@text`            | The clock, the modules, the active workspace.               |
| `@color8`          | `@text_muted`      | The workspace dots that are not active.                     |
| `@color9`          | `@accent`          | Every module under the pointer.                             |
| `@foreground`      | `@text`            | The arrow that opens the drawer.                            |

`tests/waybar.bats` reads every `@name` out of the style sheet and asserts that
the generated palette defines it. That is the guard against this class of fault,
and it holds for a name added later as well as for these four.

### The workspaces the bar shows

The dotfiles listed workspaces 1 to 5 as persistent, for every monitor at once.
Waybar takes that list per monitor name or for every monitor, and this desktop
shares its ten workspaces out over the monitors of the machine: with two
monitors the first carries 1 to 5 and the second carries 6 to 10.
[The Hyprland bundle](hyprland.md) records that assignment.

One list for every monitor is therefore right on a machine with one monitor and
wrong on every other one, and a list per monitor would put an output name into a
file of the project. No file of this project may hold one, and
`tests/hyprland.bats` reads every prescribed file and every template to prove
it.

So no workspace is listed as persistent. The cost is stated plainly: the bar
shows the workspaces that exist rather than a fixed row of dots, so a fresh
session shows one dot per monitor and gains one as each workspace is opened. The
`empty` icon and the styling for it are kept, because a workspace that the
compositor keeps alive with no window in it is still shown.

Putting the row of dots back needs the list to be generated from
`MACHINE_MONITOR_COUNT`, which is the mechanism the monitor layout already uses.
It is not done here because the bar does not know which monitor it is on, and
the fragment would need the output names to say so.

## The packages this bundle needs

| Package                   | Repository | What needs it                                                     |
| ------------------------- | ---------- | ------------------------------------------------------------------ |
| `waybar`                  | `extra`    | The bar itself.                                                    |
| `pacman-contrib`          | `extra`    | `checkupdates`, in the module that counts the updates.             |
| `networkmanager`          | `extra`    | `nmtui`, which the network module opens a terminal for.            |
| `ghostty`                 | `extra`    | The terminal those two modules open. [The Ghostty bundle](ghostty.md) names it as well. |
| `blueman`                 | `extra`    | `blueman-manager`, on the right click of the bluetooth module. The Hyprland bundle names it as well. |
| `ttf-jetbrains-mono-nerd` | `extra`    | Every icon of every module, and the default of `KNOB_FONT`.        |
| `ttf-cascadia-code-nerd`  | `extra`    | The second value of `KNOB_FONT`. See [Knobs](../knobs.md).         |

Every package above is declared in `install/packages/base.txt`, and
`tests/install.bats` fails when a package this table lists is in no manifest.
[Installing](../installing.md) records the manifest.

The icons are the reason the two font packages are in this table. Every module
of this bar draws a glyph of the Nerd Font private use area, so a machine
without one of those families shows a row of empty boxes rather than a bar.

One more program is named by this bundle and belongs to another one:
`swaync-client` is the click of the bell, and the notification centre comes with
[issue #14](https://github.com/qdrtech/xghost/issues/14). Until it lands the
bell draws and the click reaches no program.

`sudo` is not in the table. The packaging step of the installer already needs
it, and `install/steps/preflight/20-privileges.sh` refuses an installation
without it.

## What the tests prove

- `tests/waybar.bats` proves the bundle. It reads the prescribed configuration
  as JSON, proves that `position` is in no file but the template, expands the
  include exactly as `wordexp` expands it and follows it to the file the
  renderer wrote, and does that again with `XDG_CONFIG_HOME` and
  `XDG_STATE_HOME` moved, with `XDG_CONFIG_HOME` unset, and with a home
  directory that holds a space. It follows the CSS import through the bridge the
  way GTK follows it. It proves that every colour the style sheet names is
  defined by the generated palette, that the style sheet defines no colour and
  names no font family, that the knob reaches the output at every value the
  schema names, that the two modules that open a terminal open the terminal of
  this desktop, and that no template of the bundle names a machine fact. It
  proves that every palette value the bar imports is a six-digit hex, because an
  eight-digit one is an error GTK raises and an import that errors is fatal. It
  proves the guard on the font family by evading it: a one-line rule is written
  into a copy of the checkout, and the guard names that copy. Two tests are the
  order of an installation: after link, detect and render, every path the bar
  reads is a file; after link alone, the imports reach nothing.
- `tests/golden.bats` compares the rendered colours, font family and bar
  position of every theme with the committed output under
  `tests/golden/<knob set>/<theme>/waybar/`. The two knob sets are `top` and
  `bottom`, so the committed output is every theme at every bar position.
- `tests/install.bats` reads the package table above and fails when a package it
  lists is declared by no manifest.

## What this bundle has never been observed doing

**Waybar has never run against it.** No bar was started against this bundle,
because the machine it was written on runs a live session and a bar started
there would appear on it. Every claim above is proved by rendering, by reading
the two prescribed files as the data they are, by resolving each path the way
the source of Waybar 0.15.0 and of GTK 3 resolve it, and by loading a style
sheet into a `Gtk.CssProvider`, which parses one without a window and without a
compositor. What that leaves unobserved:

- **The bar has never drawn.** No module has been seen on a screen. The glyphs,
  the drawer of `group/expand`, and the styling of every module are carried over
  from a bar that ran in the dotfiles, and the colours and the font are new.
- **No exit code has been read.** That a missing `@import` is fatal, and that a
  missing include is loud, are both taken from ADR 0002 rather than from a run
  here. GTK 3 was read directly for the first of the two: a `Gtk.CssProvider`
  that loads a style sheet whose `@import` reaches nothing raises `GLib.Error`,
  and ADR 0002 records that Waybar exits 1 on it. The bundle depends on neither:
  the render precedes the first session, so both files are there whichever way
  Waybar reports their absence.
- **The merge has never been watched.** That the including file wins is taken
  from the source of `Config::mergeConfig`, and it is what the whole shape of
  this bundle rests on. `tests/waybar.bats` proves the rule this project can
  prove — that no key is written twice — and not the behaviour of Waybar itself.
- **A running bar is never restyled.** This one is measured rather than open.
  `reload_style_on_change` was in the dotfiles and this bundle drops it. Waybar
  builds the watch list of that setting from the imports of the style sheet, and
  it tests each import with `access(2)`, which resolves `..` physically, after
  following the symbolic link at `$XDG_CONFIG_HOME/waybar`. GTK resolves the
  same `..` lexically. The two disagree, on this machine, for the path this
  bundle ships:

  ```
  $XDG_CONFIG_HOME/xghost-generated/waybar/colors.css            exists: YES  (GTK's target)
  $XDG_CONFIG_HOME/waybar/../xghost-generated/waybar/colors.css  exists: NO   (Waybar's probe)
  ```

  So the generated imports are dropped from the watch list and only `style.css`
  is watched, which is a prescribed file that no theme and no knob writes. The
  setting would watch the one file that never changes and miss the two that do.
  A theme switch and a knob change therefore write the new files and stop, and
  reloading every running component from one place is
  [issue #24](https://github.com/qdrtech/xghost/issues/24). What was not
  observed is Waybar itself doing this; the two paths above were.

A first session with this bar is therefore the first test of it. Three failures
are the ones to look for, and the first two are what this page is about:

- **No bar at all.** An `@import` reached nothing.
- **A bar with the wrong position or the wrong colours.** A key is written in
  two files, so the prescribed one overruled the generated one.
- **A bar at the top that was never told to be there.** This one shows nothing
  at all, and it is the reason to check the include rather than the bar. A
  missing include leaves `position` at the default of Waybar, which is `top`,
  and `top` is the default of `KNOB_BAR_POSITION` as well. The two agree, so a
  bridge that reaches nothing looks exactly like a bridge that works to anyone
  who never moves the bar. `xghost settings set KNOB_BAR_POSITION bottom` is the
  one command that tells them apart.
