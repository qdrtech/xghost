# The supporting bundles

Three programs sit behind the desktop rather than on it: GTK, hyprshade and an
AUR helper. None of them is an application the user opens. Each one is
configuration that changes how something else behaves, so the three are one
page.

This is also the bundle that finishes the removal of pywal. The dotfiles this
project comes from generated their colours with pywal and cached them under
`~/.cache/wal`. xghost renders its colours instead, and "pywal, and what is
left of it" below records what was dropped and what was deliberately kept.

The bundle is four prescribed files and one template:

| File                            | Category   | What it holds                                      |
| ------------------------------- | ---------- | -------------------------------------------------- |
| `config/gtk-3.0/settings.ini`   | Prescribed | The widget theme, the icon theme, the cursor and the font rendering. |
| `config/gtk-3.0/gtk.css`        | Prescribed | The map from the palette of the active theme onto the colours GTK names. |
| `config/hyprshade/config.toml`  | Prescribed | The schedule of the blue light filter.             |
| `config/yay/config.json`        | Prescribed | The one setting of the AUR helper.                 |
| `templates/gtk/colors.css`      | Template   | The palette of the active theme.                   |

The file categories are those of
[ADR 0001](../adr/0001-prescribed-config-architecture.md). The bridge to the
generated output is
[ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md).

The template is older than this bundle. It was written with the renderer in
[issue #26](https://github.com/qdrtech/xghost/issues/26) and nothing read it
until now. This bundle gives it its consumer.

The prescribed files are carried over from `qdrtech/dotfiles`, paths
`gtk-3.0/.config/gtk-3.0/settings.ini`, `hyprshade/.config/hyprshade/config.toml`
and `yay/.config/yay/config.json`. What changed, and why, is recorded below.

## How the files meet

```
xghost config link     $XDG_CONFIG_HOME/gtk-3.0           -> <install location>/config/gtk-3.0
                       $XDG_CONFIG_HOME/hyprshade         -> <install location>/config/hyprshade
                       $XDG_CONFIG_HOME/yay               -> <install location>/config/yay
                       $XDG_CONFIG_HOME/xghost-generated  -> $XDG_STATE_HOME/xghost/generated
xghost theme set NAME  $XDG_STATE_HOME/xghost/generated/gtk/colors.css
```

## GTK

### The two files, and why the colours are in only one of them

`settings.ini` names the theme. `gtk.css` carries the colours. The split is
forced by GTK rather than chosen:

> **`settings.ini` has no include of any kind.** GTK reads it with
> `g_key_file_load_from_file`, which opens one path and stops. There is no
> directive in that file format that could name the generated output, so
> nothing a theme switch writes can reach it.

The CSS route has an include, so the colours go there. What is left in
`settings.ini` is the same for every theme this project ships, and both of them
are dark.

This has one consequence, and it is written down rather than hidden:

> **A light theme added later needs `settings.ini` to change, and no theme
> switch can change it.** `gtk-application-prefer-dark-theme=1` and a dark
> widget theme are prescribed. A light palette would draw light colours into
> dark widgets. Making that file generated needs a second bridge, because GTK
> opens it through the kernel and a relative symbolic link inside the linked
> directory resolves into the checkout rather than into the state directory.

### The import was measured, not assumed

`gtk.css` reaches the generated palette with the relative form every bundle but
Rofi writes:

```
@import url("../xghost-generated/gtk/colors.css");
```

`$XDG_CONFIG_HOME/gtk-3.0` is the symbolic link `xghost config link` makes, so
that path has two possible bases, exactly as it has for Ghostty and for Rofi.
Measured with GTK 3, the real linker layout, and a decoy file planted at the
other base:

| The base                                            | Read? |
| --------------------------------------------------- | ----- |
| The path as opened, `$XDG_CONFIG_HOME/xghost-generated/gtk/colors.css` | **yes** |
| The real path, `<install location>/config/xghost-generated/gtk/colors.css` | no |

GTK resolves the relative path against the path it was given and never
canonicalises it, so the bridge wins and the decoy is not opened. The decoy
held a value GTK cannot parse and GTK never complained, which is the proof that
it was never read. That keeps the rule of
[ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md) intact: the
checkout must never hold `config/xghost-generated`, and this bundle adds no
reason to.

### What a missing generated file does

This was measured twice, and the two measurements disagree. The first one was
taken through the Python binding, and it is the wrong one.

| The route                                    | The import | The call    | Definitions kept |
| -------------------------------------------- | ---------- | ----------- | ---------------- |
| `Gtk.CssProvider.load_from_path`, the binding | fails      | raises      | 0                |
| `gtk_css_provider_load_from_path`, error NULL | fails      | returns TRUE | **46**          |

The binding passes a real `GError**`, so GTK fills it, the binding raises, and
the provider is left empty. GTK does not read the style sheet of the user that
way. It passes NULL, and with NULL the parser writes the failure to standard
error and goes on, so the import is lost and every definition after it is kept:

```
Gtk-WARNING **: Theme parsing error: gtk.css:41:50: Failed to import:
Error opening file /home/ada/.config/xghost-generated/gtk/colors.css:
No such file or directory
```

So the state of a machine between `xghost config link` and the first
`xghost theme set` is 46 colour names that reach nothing, and not a style sheet
that was discarded. The difference reaches the screen. A theme rule that reads
one of those names has no value to draw with, so the declaration is dropped and
the property falls back to what CSS starts it at. That last step is read from
the cascade rules and was not measured: computing a style needs a display
connection, and the session of this machine was not to be disturbed. What was
measured is the provider, and the provider holds 46 names that reach nothing.
Either way it is not "a change of colour", which is what the first version of
this page claimed.

The installer never leaves that state: `install/steps/config/10-link.sh` links
the directories and `install/steps/config/30-theme.sh` renders a theme in the
same run. `xghost config link` on its own does leave it, until the next
`xghost theme set`.

The report goes to the standard error of each GTK application. In a session
that is the log of the compositor rather than a terminal, so it is written
somewhere the person at the keyboard is not looking. This belongs on the list
for `xghost doctor`
([issue #19](https://github.com/qdrtech/xghost/issues/19)) with the rest.

### How a palette colour becomes a widget colour

GTK 3 looks a named colour up across every style provider and takes the
definition from the highest priority one. The style sheet of the user outranks
the theme, so a name this file defines wins.

Which names those have to be is the question this bundle got wrong the first
time, and the answer was measured:

> **The names a theme exports are not the names it draws with.** The legacy
> `theme_bg_color` set is exported for applications to read. Parsed with GTK 3
> and read back, stock Adwaita carries **0** rule-level references to
> `@theme_bg_color`, and `Tokyonight-Dark` carries 0 as well: the rules of both
> hold literal colours. Redefining an exported name changes what an application
> reads and changes nothing the theme puts on a window.

`adw-gtk3`, which `settings.ini` names, is the libadwaita look ported to GTK 3,
and it draws with the libadwaita names. libadwaita itself shows the direction:
its own style sheet ends with `@define-color theme_bg_color @window_bg_color;`,
which exports the legacy name **out of** the name it draws with.

So the file defines both sets, and each one is there for a different reader:

| The block   | Who reads it                                                    |
| ----------- | --------------------------------------------------------------- |
| libadwaita  | `adw-gtk3`, which is the widget theme of this desktop. This is the block that changes the screen. |
| legacy      | An application that reads the exported names for its own drawing. No theme this project installs draws with them. |

`gtk.css` redefines 46 of them, and every value on the right reaches a name the
generated palette defines:

| The GTK names                                                          | The value   |
| ---------------------------------------------------------------------- | ----------- |
| `window_bg_color`, `theme_bg_color`, `theme_unfocused_bg_color`         | `@bg`       |
| `window_fg_color`, `headerbar_fg_color`, `sidebar_fg_color`, `card_fg_color`, `popover_fg_color`, `dialog_fg_color`, `view_fg_color`, `theme_fg_color`, `theme_text_color`, `theme_unfocused_fg_color`, `theme_unfocused_text_color` | `@text` |
| `view_bg_color`, `headerbar_bg_color`, `sidebar_bg_color`, `card_bg_color`, `popover_bg_color`, `dialog_bg_color`, `content_view_bg`, `text_view_bg`, `theme_base_color`, `insensitive_base_color`, `theme_unfocused_base_color` | `@surface` |
| `accent_bg_color`, `accent_color`, `theme_selected_bg_color`, `theme_unfocused_selected_bg_color` | `@accent` |
| `accent_fg_color`, `warning_fg_color`, `error_fg_color`, `success_fg_color`, `theme_selected_fg_color`, `theme_unfocused_selected_fg_color` | `@bg` |
| `insensitive_fg_color`, `unfocused_insensitive_color`                   | `@text_muted` |
| `warning_bg_color`, `warning_color`                                     | `@warn`     |
| `error_bg_color`, `error_color`                                         | `@error`    |
| `success_bg_color`, `success_color`                                     | `@success`  |
| `borders`, `unfocused_borders`                                          | `alpha(@text, 0.15)` |
| `insensitive_bg_color`                                                  | `mix(@surface, @text, 0.08)` |

This table is the record of the map, and the style sheet is the map. A test
compares the two name by name and value by value, and a second test follows
every pair of **this table** into GTK and out the other side to a colour of the
active theme. The expectation therefore comes from the page and the result from
GTK, so a row changed in the file alone fails both. A table derived from the
file could not do that: it would expect whatever the file said.

The palette holds two dark surfaces. The window takes the darker one and every
raised surface — the header bar, the sidebar, a card, a popover, a dialogue —
takes the lighter one, which is also what a list and a text entry take.

The selected foreground is `bg` rather than `text`, because the text colour of
both themes is light and light on the accent is not readable. The same holds
for the three status colours, which are all light.

The unfocused names hold the same values as the focused ones. This desktop
draws no distinction between a focused window and an unfocused one, and leaving
them out would have left every unfocused window in the colours of the stock
theme, which is a split nobody chose.

#### The two values that are not a bare reference

`borders` and `insensitive_bg_color` are a CSS function over a palette name.
Both were arithmetic mistakes in the first version of this bundle, and both are
arithmetic here as well: no GTK application has drawn either of them.

| The name                        | Was          | Contrast, both themes | Is now                       | Contrast, both themes |
| ------------------------------- | ------------ | --------------------- | ---------------------------- | --------------------- |
| `borders`, `unfocused_borders`  | `@surface`   | **1.00** on a list, 1.10 and 1.15 on a window | `alpha(@text, 0.15)` | 1.42 and 1.52 |
| `insensitive_bg_color`          | `@surface`   | **1.00** on the surface behind it | `mix(@surface, @text, 0.08)` | 1.20 and 1.23 |

A border that holds the colour of the surface it is drawn on is not a border:
every line on a list, an entry, a frame and a separator was exactly invisible,
and a disabled entry was the enabled entry.

`alpha(@text, 0.15)` is the GTK 3 form of what libadwaita itself writes:
`@define-color borders color-mix(in srgb, currentColor 15%, transparent);`,
read out of the style sheet inside `libadwaita-1.so.0`. GTK 3 has neither
`color-mix` nor `currentColor` in a colour definition, and `alpha()` of the
text colour is the same fifteen percent. libadwaita gives `unfocused_borders`
the same value, which this file does as well. The form needs no third surface,
which this palette does not have.

A test computes both ratios for every theme and holds them above a floor. The
floor is not a readability standard: a line that carries meaning needs 3.00,
and a subtle border does not meet that by design.

#### The palette colours no GTK window reads

The template `templates/gtk/colors.css` is older than this bundle and emits 13
names. `gtk.css` reaches 8 of them. The other five reach no GTK window, and
that is a decision rather than an oversight:

| The name              | Why nothing reads it                                              |
| --------------------- | ------------------------------------------------------------------ |
| `surface_alt`         | Both themes declare it equal to `bg`, so it would name a third surface this palette does not have. |
| `accent_alt`          | GTK 3 has no second accent. libadwaita takes one accent and derives the rest. |
| `bg_translucent`      | A translucent GTK window needs an RGBA visual the application asks for, and no style sheet can ask. |
| `surface_translucent` | The same.                                                          |
| `accent_translucent`  | The same.                                                          |

All three translucent names were written with the template in
[issue #26](https://github.com/qdrtech/xghost/issues/26), before the template
had a consumer. The bar has a palette of its own, `templates/waybar/colors.css`,
and that one carries no translucent name either, so these three are read by
nothing in this project today.

A test reads this table. A name added to the template that no style sheet uses
and this table does not hold fails the suite, and so does a name recorded here
that `gtk.css` starts using.

### The theme this bundle installs, and the one it does not

The dotfiles named `Tokyonight-Dark` and `Tokyonight-Moon`. Both come from one
package, `tokyonight-gtk-theme-git`, and `pacman -Si` finds it in no official
repository. That package is therefore only reachable through `aur.txt`, and a
package in `aur.txt` is **not installed on a machine with no AUR helper**: the
step names it, the installation finishes, and GTK falls back to the built-in
Adwaita without a word. A settings file that names a theme nobody installs is
exactly that failure.

So the request changed to a pair that `base.txt` installs with `pacman`:

| The setting              | The dotfiles       | xghost           | The package          | Under `/usr/share` |
| ------------------------ | ------------------ | ---------------- | -------------------- | ------------------ |
| `gtk-theme-name`         | `Tokyonight-Dark`  | `adw-gtk3-dark`  | `adw-gtk-theme`      | `themes`           |
| `gtk-icon-theme-name`    | `Tokyonight-Moon`  | `Papirus-Dark`   | `papirus-icon-theme` | `icons`            |
| `gtk-cursor-theme-name`  | `default`          | `default`        | `default-cursors`    | `icons`            |

Two tests read this table. The first takes the settings keys out of
`settings.ini`, requires a row here for each one, and requires a manifest to
declare the package of that row. The second asks `pacman -Fl` whether the
package really ships `usr/share/<directory>/<value>`, which is the half no
reading of this repository can answer. The last column is what the second test
looks under, so both keys and directories come out of files rather than out of
a list inside a test.

`adw-gtk3-dark` is the libadwaita look ported to GTK 3, so a GTK 3 application
and a GTK 4 application on this desktop are drawn alike. It is also why
`gtk.css` defines the libadwaita colour names: those are the names its rules
read.

`default-cursors` is declared although `wayland` already depends on it. The rule
that keeps an already-present package out of the manifest is about a package
nobody names; this project names this one in `settings.ini`, so this project
chose it.

**What `default-cursors` ships, exactly.** One file:
`usr/share/icons/default/index.theme`, which holds `Inherits=Adwaita` and no
cursor at all. It supplies the *name* `default` and redirects it. The cursor
images come from `adwaita-cursors`, which no manifest of this project declares
and which arrives anyway, as a dependency of `adwaita-icon-theme`, which is a
dependency of `gtk3`. The chain works and was read with `pacman -Ql` and
`pactree`. The test that reads this row proves that the package ships the
directory the setting names, and not that a cursor is in it.

### What changed from the dotfiles, and why

| Change                                                     | Why                                                                    |
| ---------------------------------------------------------- | ----------------------------------------------------------------------- |
| The theme, the icon theme and the cursor theme are declared packages | See the table above. The three the dotfiles named were installed by hand. |
| `gtk.css` is new                                            | The dotfiles had no user style sheet. Their colours came from the theme package alone, so a theme switch changed nothing in a GTK window. |
| The two commented-out font lines are gone                   | They named `SF Pro Text` and `SF Mono`, which are macOS fonts no Arch machine carries, and they were commented out, so they did nothing. `KNOB_FONT` names the font of the compositor, the terminal and the bar, and GTK is not on that list; putting GTK there is a change to the knob rather than to this bundle. |
| `gtk-toolbar-style`, `gtk-toolbar-icon-size`, `gtk-button-images` and `gtk-menu-images` are gone | All four were deprecated in GTK 3.10 and are read by nothing in GTK 3 today. |
| `gtk-enable-event-sounds` and `gtk-enable-input-feedback-sounds` are gone | Both need a sound event module and a sound theme, and this project installs neither, so both lines reached nothing. |
| The four `gtk-xft-` lines are kept unchanged                | Antialiasing, hinting and subpixel order are read by GTK and take effect. They are the settings the maintainer has been looking at. |

### What this bundle does not do

- **GTK 4.** No `config/gtk-4.0` is shipped. `gtk-theme-name` is read by GTK 4
  only when the application does not use libadwaita, and libadwaita ignores it
  entirely, so the file that serves GTK 4 is a style sheet rather than a
  settings file. The notifications
  ([issue #14](https://github.com/qdrtech/xghost/issues/14)) are the first GTK 4
  component of this desktop, and that bundle owns the decision.
- **Reloading a running application.** A theme switch writes `gtk/colors.css`
  and a GTK application reads its style sheet at start up, so it shows the new
  colours when it next starts. GTK offers no signal for it, and a
  per-application route would be a per-application design.
  [Reloading](../reloading.md) records this as one of the three cases with no
  mechanism, and names the two GTK surfaces that are exempt because they carry a
  reload of their own: the bar and the notification centre.

## hyprshade

`hyprshade` applies a screen shader. The prescribed schedule turns the blue
light filter on at 20:30 and off at 06:00, which is the schedule the dotfiles
carried.

The shader is the one the package itself ships, at
`/usr/share/hyprshade/shaders/blue-light-filter.glsl`. This project prescribes
no shader file, so there is no name in the schedule that only this checkout
could satisfy.

hyprshade reads three paths in order, and this file is the third:

| Order | The path                                  | This project        |
| ----- | ----------------------------------------- | ------------------- |
| 1     | `$HYPRSHADE_CONFIG`                       | never set           |
| 2     | `$XDG_CONFIG_HOME/hypr/hyprshade.toml`    | inside `config/hypr`, and this project puts no file there |
| 3     | `$XDG_CONFIG_HOME/hyprshade/config.toml`  | **this file**       |

The second path is inside a directory this project already links, so a file
dropped there would take priority over this one in silence. There is none, and
a test proves it.

### The schedule is prescribed and not started

> **`xghost` installs no systemd unit, so the schedule is read by nothing until
> the user starts it.** hyprshade applies a shader from a systemd user timer,
> and creating that timer is `hyprshade install`, which writes into
> `$XDG_CONFIG_HOME/systemd/user`.

The two commands that close the gap:

```sh
hyprshade install
systemctl --user enable --now hyprshade.timer
```

They are not in the installer. `hyprshade install` reads the schedule and writes
a unit derived from it, so the unit and this file can drift apart, and the
installer has no step that would notice. Doing it properly means owning the
unit as prescribed configuration, and that is a decision this bundle does not
carry. Until then the filter is applied by running `hyprshade auto` by hand.

This is a gap and not a silent failure: a schedule nothing reads changes
nothing, and a filter that never comes on is visible to the person looking at
the screen.

## yay

`config/yay/config.json` sets one thing, `cleanAfter`, which removes the build
directory of a package once it is installed. Without it, every AUR build of
every update stays under `~/.cache/yay` forever.

The file is prescribed although **xghost installs no AUR helper**. That is the
point of it: `aur.txt` names `hyprshade`, which no official repository carries,
so a user who wants the screen shader installs a helper by hand and runs
`./install.sh` again. This file is what makes the helper behave the same on
every xghost machine from the first run, instead of after somebody notices the
cache.

Two properties of this file, both unlike every other prescribed file of this
project:

- **It carries no header comment.** JSON has no comment syntax, so the file is
  three lines of data and this page is where its reasons are.
- **It is a partial configuration.** yay starts from its own defaults and reads
  this file over them, so the one key here changes one setting and leaves the
  rest of yay alone.

`yay --save` writes `config.json`, and against a linked checkout that would
dirty the checkout, exactly as an edit to any other prescribed file does. An
ordinary `yay -S` does not: the live machine this bundle was written on has
built AUR packages through a symbolic link to a one-key `config.json`, and the
file is still one key.

## pywal, and what is left of it

The dotfiles generated their colours with pywal, cached them under
`~/.cache/wal`, and read that cache from the shell, from a Waybar module, and
from a vendored copy of the `wal` script. xghost renders its colours instead:
one palette per theme, one renderer, one generated tree.

Nothing of pywal is carried into this project. There is no template, no
colourscheme, no cached sequence file and no vendored script, the shell reads
no cache, and no manifest names the package.

Five files carry the name, and **every one of them is deliberate**:

| Where                       | What it says                                                               |
| --------------------------- | ---------------------------------------------------------------------------- |
| `docs/bundles/shell.md`     | A row of the table of dotfile lines that were not carried over: the pywal sequence block, and why. |
| `docs/bundles/waybar.md`    | A row of the same kind of table: the colour picker module read the pywal cache, and why it went. |
| `docs/bundles/supporting.md` | This section.                                                              |
| `tests/supporting.bats`     | The test that holds the rule, which has to spell the name to forbid it.     |
| `tests/negative-control`    | The mutation that puts the block back, which proves that test can fail.     |

A dangling reference is one a reader or a program can follow to nothing: an
include path, a package name, a command, a variable. None of these is one. The
three pages are past tense, in tables whose whole purpose is to record what was
dropped, and deleting them would delete the reason this desktop has no pywal.
The next person would then read a colour picker that reads a cache, see no
reason it is gone, and put it back. The two test files have to write the name
to forbid it.

The judgement is enforced rather than left as an opinion.
`tests/supporting.bats` requires that the name appears in those five files and
nowhere else, and that each of the five still carries it, so a pywal path that
reappears in a config file, a template, a script or a manifest fails the suite
on the day it lands, and an allowance that nobody needs any more fails it too.

## The packages this bundle needs

| Package                | Repository | What needs it                                                    |
| ---------------------- | ---------- | ---------------------------------------------------------------- |
| `adw-gtk-theme`        | `extra`    | `adw-gtk3-dark`, the widget theme `config/gtk-3.0/settings.ini` names. |
| `papirus-icon-theme`   | `extra`    | `Papirus-Dark`, the icon theme the same file names.              |
| `default-cursors`      | `extra`    | The name `default`, redirected to Adwaita. The cursors themselves come from `adwaita-cursors`, under `gtk3`. |
| `hyprshade`            | `aur`      | The screen shader. No official repository carries it.            |

Every package above is declared in `install/packages/base.txt`, except
`hyprshade`, which is declared in `install/packages/aur.txt` beside it.
[Installing](../installing.md) records both manifests and why they are two
files.

`yay` is in neither. xghost installs no AUR helper by itself, and prescribing
the configuration of a program is not the same as installing it.

## How this bundle is tested

- `tests/supporting.bats` reads the three prescribed files, links them, renders
  a theme, loads the style sheet with GTK, and reads the rules of the installed
  widget theme. It opens no window, runs no package operation, and never runs
  `hyprshade` or `yay`.
- `tests/install.bats` reads the package table of **every** bundle page and
  fails when a package one of them lists is declared by no manifest. That is the
  cross-check for the table above, and it is derived: a package added to the
  table is read by it without the test changing.
- `tests/negative-control` is the other direction. It copies the checkout,
  breaks one source on purpose, and requires the test aimed at that break to
  fail and to be named in the report. It is run by hand; continuous integration
  runs `bats tests`.

The controls this bundle adds are of a kind the shell bundle had none of, and
the difference is the point:

> A **deleted guard** catches a test that never ran. A **perturbed input**
> catches a test that ran and whose assertion was too loose to notice.

Nothing this bundle mutates is deleted. A key of `templates/gtk/colors.css` is
renamed, a row of the map in `gtk.css` is swapped, a selection and its
unfocused twin are swapped together, an unfocused twin is pointed at another
colour, a border goes back to the colour of the surface it is drawn on,
`settings.ini` is given the theme name the dotfiles used, the cursor size of
GTK parts company with the compositor, a schedule loses its start time, a
second schedule is planted where hyprshade reads first, `yay` gains a second
setting, a manifest declares ImageMagick, and the pywal block comes back into
the zshrc. Every one of those leaves a file that parses, a render that succeeds
and an installation that finishes.

Three of them are there because the first version of this bundle passed them.
The map perturbation that keeps a name and its twin **consistent**, the
perturbation that repoints a name the read-back test never listed, and the one
that flattens a border were all invisible to the first suite, and each one
changes what a window looks like.

### The tests that can skip, and why

A skipped test proves nothing. Two of the eight below have no file-reading
equivalent at all: only the package database can say that a package really
ships the theme, and only the installed theme can say which colour names its
rules read. So the list is a budget rather than a note. A test that gains a
skip and is not on this list fails the suite.

| The test                                                                  | What it needs             |
| ------------------------------------------------------------------------- | ------------------------- |
| `every package the bundle page names ships the theme the settings file asks for` | `pacman` and a filled file database |
| `GTK resolves the import and holds the palette of the active theme`       | GTK 3 for Python          |
| `GTK reads the bridge and not a file at the real path`                    | GTK 3 for Python          |
| `a palette that is not there leaves every definition kept and reaching nothing` | GTK 3 for Python     |
| `the theme the settings file names draws with names the style sheet redefines` | GTK 3, and the widget theme installed |
| `the widget colours GTK holds are the colours of the active theme`        | GTK 3 for Python          |
| `the shader the schedule names is one hyprshade itself ships`             | `hyprshade`               |
| `hyprshade is declared by the AUR manifest and by no other`               | `pacman`                  |

That is 8 of the 34 tests. Continuous integration installs GTK 3, so five of
the eight run there; `pacman` and `hyprshade` are not on an Ubuntu runner, and
neither is `adw-gtk3`, so three still skip. Nothing in a TAP report says so:
TAP marks a skip on the line of the test and prints no count at the end, which
is why the budget is a test rather than a habit.

One control is weaker than the rest, and the script lists those apart. "GTK
reads the bridge and not a file at the real path" and the two halves of the
missing-palette measurement record what GTK does, so no change to this project
can break them, and their controls mutate the assertion instead. That proves
the assertion runs and is compared. It does not prove the test is sensitive to
this project, because it is not.

## What this bundle has never been observed doing

Every measurement above was taken headlessly, through a GTK style provider, on
a machine whose session was live and was not to be disturbed. Five things
follow that this page states rather than claims:

- **No GTK application was seen drawing these colours.** A provider parses a
  sheet and holds what it parsed. Computing the style of a widget needs a
  display connection, which this machine could not give without reaching the
  live session, so what a dropped declaration falls back to is read from the
  cascade rules and not measured.
- **The contrast numbers are arithmetic.** The border and the disabled surface
  were computed from the palettes, composited where the colour is translucent.
  Nobody has looked at either one on a screen.
- **`adw-gtk3` is not installed on the machine this was written on.** The
  measurement that the legacy names are exported and not drawn was taken on
  stock Adwaita and on `Tokyonight-Dark`, which are installed, and both carry
  zero rule-level references. That `adw-gtk3` reads the libadwaita names is
  read from libadwaita, which exports the legacy set out of them, and from the
  sources of `adw-gtk3`. The test that reads the rules of the installed theme
  is what will confirm it on a machine that has the package, and it skips
  everywhere else.
- **`hyprshade` was never run.** The copy on the machine this bundle was written
  on is built against a Python that has since been replaced, so
  `hyprshade --help` ends in `ModuleNotFoundError`. The schedule was checked
  against the parser and the validator in the installed source, not by applying
  a shader.
- **`yay` was never run.** The one observation about `config.json` is of a file
  on disk after somebody else ran it.
