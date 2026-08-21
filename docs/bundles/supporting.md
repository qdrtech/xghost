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

Measured on the same route: **an `@import` that reaches nothing discards the
whole style sheet**, and GTK reports it by name.

```
gtk-css-provider-error-quark: gtk.css:1:50 Failed to import:
Error opening file /home/ada/.config/xghost-generated/gtk/colors.css:
No such file or directory
```

Nothing after the failed import survives, so every colour below it is dropped
as well. The desktop then draws in plain `adw-gtk3-dark`, which is a complete
theme, so the failure is a change of colour and never an application that will
not start. That is the state of a machine between `xghost config link` and the
first `xghost theme set`.

The report goes to the standard error of each GTK application. In a session
that is the log of the compositor rather than a terminal, so it is written
somewhere the person at the keyboard is not looking. This belongs on the list
for `xghost doctor`
([issue #19](https://github.com/qdrtech/xghost/issues/19)) with the rest.

### How a palette colour becomes a widget colour

GTK 3 looks a named colour up across every style provider and takes the
definition from the highest priority one. The user style sheet outranks the
theme, so redefining a name the theme draws with changes what the theme draws.
`gtk.css` redefines twenty of them, and every value on the right is a name the
generated palette defines:

| The GTK names                                                          | The palette |
| ---------------------------------------------------------------------- | ----------- |
| `theme_bg_color`, `theme_unfocused_bg_color`                            | `bg`        |
| `theme_base_color`, `theme_unfocused_base_color`, `insensitive_bg_color`, `insensitive_base_color`, `borders`, `unfocused_borders` | `surface` |
| `theme_fg_color`, `theme_text_color`, `theme_unfocused_fg_color`, `theme_unfocused_text_color` | `text` |
| `insensitive_fg_color`, `unfocused_insensitive_color`                   | `text_muted` |
| `theme_selected_bg_color`, `theme_unfocused_selected_bg_color`          | `accent`    |
| `theme_selected_fg_color`, `theme_unfocused_selected_fg_color`          | `bg`        |
| `warning_color`                                                         | `warn`      |
| `error_color`                                                           | `error`     |
| `success_color`                                                         | `success`   |

The selected foreground is `bg` rather than `text`, because the text colour of
both themes is light and light on the accent is not readable.

The unfocused names hold the same values as the focused ones. This desktop
draws no distinction between a focused window and an unfocused one, and leaving
them out would have left every unfocused window in the colours of the stock
theme, which is a split nobody chose.

`gtk.css` defines no colour of its own, so a name it draws with and the palette
does not define is a declaration GTK drops in silence. A test reads every `@name`
out of the file and requires the generated palette to define it, which is the
guard the Waybar bundle already carries for the same reason.

### The theme this bundle installs, and the one it does not

The dotfiles named `Tokyonight-Dark` and `Tokyonight-Moon`. Both come from one
package, `tokyonight-gtk-theme-git`, and `pacman -Si` finds it in no official
repository. That package is therefore only reachable through `aur.txt`, and a
package in `aur.txt` is **not installed on a machine with no AUR helper**: the
step names it, the installation finishes, and GTK falls back to the built-in
Adwaita without a word. A settings file that names a theme nobody installs is
exactly that failure.

So the request changed to a pair that `base.txt` installs with `pacman`:

| The setting              | The dotfiles       | xghost           | The package          |
| ------------------------ | ------------------ | ---------------- | -------------------- |
| `gtk-theme-name`         | `Tokyonight-Dark`  | `adw-gtk3-dark`  | `adw-gtk-theme`      |
| `gtk-icon-theme-name`    | `Tokyonight-Moon`  | `Papirus-Dark`   | `papirus-icon-theme` |
| `gtk-cursor-theme-name`  | `default`          | `default`        | `default-cursors`    |

`adw-gtk3-dark` is the libadwaita look ported to GTK 3, so a GTK 3 application
and a GTK 4 application on this desktop are drawn alike. The colours of the
active theme reach it through `gtk.css` in either case, so the choice of
package decides the shape of a widget rather than its colour.

`default-cursors` is declared although `wayland` already depends on it. The rule
that keeps an already-present package out of the manifest is about a package
nobody names; this project names this one in `settings.ini`, so this project
chose it.

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
  and stops. A GTK application reads its style sheet at start up, so it shows
  the new colours when it next starts. That is the general gap
  [issue #24](https://github.com/qdrtech/xghost/issues/24) owns.

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

Two mentions of the name remain, and **both are deliberate**:

| Where                     | What it says                                                                 |
| ------------------------- | ----------------------------------------------------------------------------- |
| `docs/bundles/shell.md`   | A row of the table of dotfile lines that were not carried over: the pywal sequence block, and why. |
| `docs/bundles/waybar.md`  | A row of the same kind of table: the colour picker module read the pywal cache, and why it went. |

A dangling reference is one a reader or a program can follow to nothing: an
include path, a package name, a command, a variable. Neither of these is one.
Both are past tense, in a table whose whole purpose is to record what was
dropped, and deleting them would delete the reason this desktop has no pywal.
The next person would then read a colour picker that reads a cache, see no
reason it is gone, and put it back.

The judgement is enforced rather than left as an opinion.
`tests/supporting.bats` requires that the name appears in those two files and
nowhere else, so a pywal path that reappears in a config file, a template, a
script or a manifest fails the suite on the day it lands.

## The packages this bundle needs

| Package                | Repository | What needs it                                                    |
| ---------------------- | ---------- | ---------------------------------------------------------------- |
| `adw-gtk-theme`        | `extra`    | `adw-gtk3-dark`, the widget theme `config/gtk-3.0/settings.ini` names. |
| `papirus-icon-theme`   | `extra`    | `Papirus-Dark`, the icon theme the same file names.              |
| `default-cursors`      | `extra`    | The `default` cursor theme the same file names.                  |
| `hyprshade`            | `aur`      | The screen shader. No official repository carries it.            |

Every package above is declared in `install/packages/base.txt`, except
`hyprshade`, which is declared in `install/packages/aur.txt` beside it.
[Installing](../installing.md) records both manifests and why they are two
files.

`yay` is in neither. xghost installs no AUR helper by itself, and prescribing
the configuration of a program is not the same as installing it.

## How this bundle is tested

- `tests/supporting.bats` reads the three prescribed files, links them, renders
  a theme, and loads the style sheet with GTK. It opens no window, runs no
  package operation, and never runs `hyprshade` or `yay`.
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
renamed, two rows of the map in `gtk.css` are swapped, an unfocused twin is
pointed at another colour, `settings.ini` is given the theme name the dotfiles
used, the package that ships the theme leaves the manifest, `hyprshade` moves to
the manifest `pacman` reads, and the pywal block comes back into the zshrc.
Every one of those leaves a file that parses, a render that succeeds and an
installation that finishes. A test that read the shape of a file rather than the
value in it passes through all seven.

One control is weaker than the rest, and it is listed apart in the script for
that reason. "GTK reads the bridge and not a file at the real path" records what
GTK does, so no change to this project can break it, and its control mutates the
assertion instead. That proves the assertion runs and is compared. It does not
prove the test is sensitive to this project, because it is not.

## What this bundle has never been observed doing

Every measurement above was taken headlessly, through `Gtk.CssProvider`, on a
machine whose session was live and was not to be disturbed. Three things follow
that this page states rather than claims:

- **No GTK application was seen drawing these colours.** The map from the
  palette onto the GTK names is read from what GTK 3 documents and is checked by
  a test that loads the sheet and reads back what GTK parsed. Whether the result
  looks right is a judgement nobody has made yet.
- **`hyprshade` was never run.** The copy on the machine this bundle was written
  on is built against a Python that has since been replaced, so
  `hyprshade --help` ends in `ModuleNotFoundError`. The schedule was checked
  against the parser and the validator in the installed source, not by applying
  a shader.
- **`yay` was never run.** The one observation about `config.json` is of a file
  on disk after somebody else ran it.
