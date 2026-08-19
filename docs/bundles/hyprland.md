# The Hyprland bundle

Hyprland is the compositor of xghost. It is the largest bundle, and it is the
first one whose output depends on the machine it runs on.

The bundle is prescribed configuration plus four generated files:

| File                                                  | Category   | What it holds                                     |
| ----------------------------------------------------- | ---------- | ------------------------------------------------- |
| `config/hypr/hyprland.conf`                            | Prescribed | The entry point. It sources everything else.      |
| `config/hypr/conf/*.conf`                              | Prescribed | The compositor, split by subject.                 |
| `config/hypr/hypridle.conf`                            | Prescribed | The idle daemon.                                  |
| `config/hypr/hyprlock.conf`                            | Prescribed | The lock screen.                                  |
| `config/hypr/hyprpaper.conf`                           | Prescribed | The wallpaper daemon.                             |
| `templates/hypr/colors.conf`                           | Template   | The palette of the theme, as Hyprland variables.  |
| `templates/hypr/theme.conf`                            | Template   | The styling that depends on the palette.          |
| `templates/hypr/knobs.conf`                            | Template   | The settings that carry a knob: the gaps and the font. |
| `templates/hypr/monitors.conf.choice.MACHINE_MONITOR_COUNT/`  | Choice | The monitor layout, one fragment per count.  |
| `templates/hypr/workspaces.conf.choice.MACHINE_MONITOR_COUNT/` | Choice | Which workspace opens on which monitor.     |
| `templates/hypr/animation.conf.choice.KNOB_ANIMATIONS/` | Choice   | The animations, one fragment per value of the knob. |

The file categories are those of
[ADR 0001](../adr/0001-prescribed-config-architecture.md). The structural choice
is documented in [Theming](../theming.md), and the knobs in
[Knobs](../knobs.md).

Everything is carried over from `qdrtech/dotfiles`, path
`hyprland/.config/hypr/`. What changed, and why, is recorded below.

## How the files meet

```
xghost config link     $XDG_CONFIG_HOME/hypr             -> <install location>/config/hypr
                       $XDG_CONFIG_HOME/xghost-generated -> $XDG_STATE_HOME/xghost/generated
xghost theme set NAME  $XDG_STATE_HOME/xghost/generated/hypr/colors.conf
                       $XDG_STATE_HOME/xghost/generated/hypr/monitors.conf
                       $XDG_STATE_HOME/xghost/generated/hypr/workspaces.conf
                       $XDG_STATE_HOME/xghost/generated/hypr/animation.conf
                       $XDG_STATE_HOME/xghost/generated/hypr/knobs.conf
                       $XDG_STATE_HOME/xghost/generated/hypr/theme.conf
```

`xghost settings set` writes the same six files, because a knob change renders
the same tree.

The second link is the **bridge**, the same one
[the Ghostty bundle](ghostty.md) uses. The prescribed entry point reaches each
generated file through it:

```
source = ../xghost-generated/hypr/colors.conf
```

Neither end of that path is written out in full. The directory it starts from
moves with `XDG_CONFIG_HOME` and the bridge moves with `XDG_STATE_HOME`, so the
include is right for every value of both.

### How Hyprland resolves the relative path

Hyprland resolves a relative `source` against the directory of the file that is
being parsed, and that file is the one it opened. It opens
`$XDG_CONFIG_HOME/hypr/hyprland.conf`, which is the link `xghost config link`
made, and it does **not** resolve the link first. `..` is therefore the config
directory of the user, where the bridge is, and never the checkout.

That is the opposite of Ghostty, which tries the real path first and falls back
to the path as opened. Hyprland has no fallback. One rule follows:

> **A prescribed Hyprland file reaches the generated output only through the
> path it was opened from.** A `config/xghost-generated` in the checkout would
> not be read in its place, and the include would still travel through the
> bridge.

Verified against Hyprland 0.56.2 with `Hyprland --verify-config`, which parses
the configuration and starts no compositor. With the bridge in place the whole
configuration reports `config ok`. With the bridge removed, every include
reports `source= globbing error: found no match`. The second half is what proves
the first: the path travels through the bridge and nowhere else.

`Hyprland --verify-config` is safe to run beside a live session. It returns from
the compositor constructor at once, builds the config manager alone, parses,
prints the result, and exits. It opens no Wayland socket, it sets no instance
signature, and it runs no `exec` line.

### The include is not optional

Ghostty has `?`, which makes an include optional. Hyprland has no such thing: a
`source` that matches no file is a named error, and the configuration fails to
load cleanly.

The bundle **keeps** that behaviour rather than working around it, for one
reason. There is no useful half-configured Hyprland here. Every prescribed file
that draws a border names `$text_muted`, and the monitor layout is a generated
file too, so a compositor that started without them would come up with no
colours, no monitor layout and a page of errors of its own. One named error is
better than that page.

The consequence is an ordering requirement, and it belongs to
[issue #7](https://github.com/qdrtech/xghost/issues/7):

> `xghost machine detect` and `xghost theme set` both have to run before the
> first Hyprland session starts.

`xghost theme set` also fails, by name, on a machine that has never run
detection, because the monitor layout is chosen by a machine fact. The report
names `MACHINE_MONITOR_COUNT`, which is the fact that is missing.

## The monitor layout, and how N lines are written without a loop

A Hyprland monitor layout is one line per monitor:

```
monitor = NAME,MODE,POSITION,SCALE,transform,ROTATION
```

The number of monitors is a fact of the machine. The renderer substitutes
scalars and selects between fragments, and ADR 0001 forbids it growing a loop or
a condition, so no single template can write a line count it does not know.

The bundle uses a **structural choice keyed on `MACHINE_MONITOR_COUNT`**. One
prescribed fragment per count, and the renderer writes the one the fact selects:

```
templates/hypr/monitors.conf.choice.MACHINE_MONITOR_COUNT/
  1  one monitor line
  2  two monitor lines
  3  three monitor lines
  default  monitor = ,preferred,auto,auto
```

Each fragment names the facts of exactly its own monitors, so a fragment can
never name a monitor the machine does not report. The one for two monitors names
`MACHINE_MONITOR_1_*` and `MACHINE_MONITOR_2_*`, and nothing else.

Three other designs were considered and rejected:

| Design                                                        | Why not                                                              |
| ------------------------------------------------------------- | -------------------------------------------------------------------- |
| One template with a fixed number of monitor slots             | A slot for a monitor that does not exist names a fact that does not exist, so the render fails on every machine with fewer monitors. Filling the empty slots would mean detection inventing facts, which it must not do. |
| One generated file per monitor, sourced by a glob             | The renderer has no loop, so it cannot write a variable number of files either. The problem only moves. |
| A joined "all monitors" fact, written by detection            | A machine fact is one line of plain text and a monitor layout is many lines. It would also put Hyprland syntax inside detection, which serves every application. |

The chosen design puts the Hyprland syntax in Hyprland's own templates, keeps
detection reporting facts, and keeps the renderer free of control flow.

### What `default` covers, and what it costs

The `default` fragment is chosen for every count no fragment names: zero
monitors, four or more, and the `unknown` that detection writes when it could
not read a compositor. It names no output and lets Hyprland take the preferred
mode of every display it finds and lay them out left to right.

The cost is stated plainly: a machine with four monitors gets an automatic
layout rather than a prescribed one. The fix is one file, `4`, beside the other
three. No code changes.

## The workspaces

The ten workspaces the keybindings name are shared out over the monitors in the
order the compositor reports them, and the first workspace of each monitor is
the one that monitor opens on.

| Monitors | Assignment                              |
| -------- | --------------------------------------- |
| 1        | 1–10 on the one monitor                 |
| 2        | 1–5, then 6–10                          |
| 3        | 1–4, then 5–7, then 8–10                |
| default  | No workspace is pinned to any monitor.  |

The order is the order of the facts, which is the order Hyprland reports its
monitors. `MACHINE_PRIMARY_MONITOR` is not used here: it names a monitor, and
the renderer cannot turn a name back into the index a fragment would need.

## The knobs this bundle carries

Three preferences of this desktop are knobs, and all three land in Hyprland.
[Knobs](../knobs.md) documents the schema, the file a user edits, and the two
commands.

| Knob              | Where it lands                                            |
| ----------------- | ---------------------------------------------------------- |
| `KNOB_ANIMATIONS` | The whole `animations` block, as a structural choice.      |
| `KNOB_GAP_SIZE`   | `general:gaps_in` and `general:gaps_out`.                  |
| `KNOB_FONT`       | `misc:font_family`, and the terminal of [the Ghostty bundle](ghostty.md). Not `hyprlock.conf`: see below. |

The two generated files are sourced after every prescribed file, so a preference
wins over the value the project prescribes for the same setting. Neither setting
is left behind in a prescribed file: `conf/window.conf` holds no gap and
`conf/misc.conf` holds no font. Two writers of one setting would leave the knob
winning by the order of the includes alone, and a reader of the prescribed file
would see a value the compositor never runs. That is the fault this bundle
already found once in the dotfiles it came from, recorded under "What else
changed from the dotfiles".

The animations are a **structural choice** rather than one setting, because
switching them off is switching off a block of a dozen lines. The fragment for
`off` carries `enabled = false` and no curve at all, so nothing is left that
names an animation the compositor never plays. The choice has one fragment per
value of the schema and no `default`: the schema names two values, and a value
outside them never reaches the renderer.

The gaps were 10 and 14 in the dotfiles, and one knob is one value, so both are
the knob and the default is 10. The outer gap is therefore 4 pixels smaller than
it was.

## The colours

`templates/hypr/colors.conf` defines the palette of the theme as Hyprland
variables, and `hyprland.conf` sources it first, so every prescribed file below
may name `$bg`, `$accent` and the rest.

`templates/hypr/theme.conf` holds the styling that depends on those colours, and
it is sourced last, so the theme wins over every prescribed file. Today it is
the two border colours. The dotfiles carried a `conf/theme.conf` that set the
rounding, the gaps, the border width, the blur and the shadow as well, and it
was sourced last there too. Those values are prescribed now, in
`conf/decoration.conf` and `conf/window.conf`, and they are the values that
reached the compositor. "What else changed from the dotfiles" below records
what that cost.

## The dead `xdg.sh` reference

`conf/autostart.conf` in the dotfiles ran `~/.config/hypr/scripts/xdg.sh` at
every login. No commit on any branch of that repository ever contained that
script, and the line had been there since March 2025. It failed in silence at
every login for over a year. The dotfiles have since dropped it too, in commit
`682f9a9` of 12 August 2026, so the line survives in neither repository.

The line is **dropped** here, and nothing replaces it, because the work it named
is already done. Hyprland performs the environment import itself. The binary of
Hyprland 0.56.2 carries it as a literal string:

```
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME PATH XDG_DATA_DIRS && … dbus-update-activation-environment --systemd …
```

Screen sharing needs the `xdg-desktop-portal-hyprland` package beside
`xdg-desktop-portal`, and no configuration file at all. Both belong in the
package manifest of [issue #7](https://github.com/qdrtech/xghost/issues/7).

## The authentication agent

`conf/autostart.conf` starts one program that the dotfiles never started:

```
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
```

A polkit request needs an agent to ask through. Two programs of this autostart
make such requests: `blueman-applet` asks when a device is paired, and
`nm-applet` asks when a system connection is saved. With no agent running, both
requests are refused and no dialog is shown at all, so the user sees a bluetooth
device that will not pair and no reason for it.

The package was already in the manifest and nothing started it. The line is the
missing half of that decision, and it is the one line of the file that names an
absolute path: `polkit-gnome` installs the agent in a library directory rather
than on the `PATH`, and the `.desktop` file of the package runs that same path.

## The other references that were not carried over

The same rule was applied to every line of the dotfiles that named a file this
project does not ship. A prescribed file cannot write its own location: Hyprland
expands `$XDG_CONFIG_HOME` itself, and expands it to nothing when the variable
is not set, so a path written into a prescribed file is right only on a machine
whose config directory is the default. Every `exec` line therefore names a
program on the `PATH`.

| Line in the dotfiles                              | What happened to it                                                     |
| ------------------------------------------------- | ----------------------------------------------------------------------- |
| `exec-once = ~/.config/hypr/scripts/xdg.sh`        | Dropped. The script never existed, and Hyprland does the work.          |
| `exec-once = sh ~/.config/waybar/scripts/launch.sh` | `exec-once = waybar`. The script killed the bar and chose its configuration by user name. [The Waybar bundle](waybar.md) records why it is gone. |
| `exec = sh ~/.config/scripts/import-gsettings.sh`  | Dropped. GTK is [issue #17](https://github.com/qdrtech/xghost/issues/17). |
| `exec = hyprshade auto`                            | Dropped. hyprshade is [issue #17](https://github.com/qdrtech/xghost/issues/17). |
| `bind = … exec, sh ~/.config/hypr/scripts/hyprpaper.sh` | The two commands of that script are inline in the binding, and the script is gone. |
| `bind = $SUPER_SHIFT, f, fullscreen`               | `bind = $mainMod SHIFT, F, fullscreen`. No file ever defined `$SUPER_SHIFT`, so neither key that used it worked. |
| `bind = $SUPER_SHIFT, l, exec, hyprlock`           | `bind = $mainMod SHIFT, L, exec, hyprlock`. The same fault.             |
| `input-field { monitor = DP-1 }` in `hyprlock.conf` | `monitor =`, which is every monitor. No output name may appear.        |
| `background { path = $HOME/.config/cache/blurred_wallpaper.png }` | Dropped, and the block was live. See below.               |
| `image { path = …/ml4w/cache/square_wallpaper.png }` | Dropped. No commit of the dotfiles ever held that file, and the tool it named is not used here. |
| `conf/environment.conf`                            | Dropped. The file was empty, so the fragment and its `source` line both did nothing. |
| The ML4W comments in `hypridle.conf`               | Dropped. They instruct a settings application this project does not use. |

### The lock-screen background was live, and it is still dropped

The `background` block of `hyprlock.conf` named
`$HOME/.config/cache/blurred_wallpaper.png`, and that file is real. It is
`config/.config/cache/blurred_wallpaper.png` in the dotfiles, added in commit
`8c6033a`, and it is still there at `HEAD`. It sits in the `config` stow
package, which stows to `~/.config/`, so it lands at exactly the path the block
names. The lock screen drew that image at every lock.

It is dropped for a different reason. The image is a file of that machine, not
a file this project ships, and a background this bundle cannot generate is a
background it must not name:
[issue #20](https://github.com/qdrtech/xghost/issues/20) owns the backgrounds
and supplies one image per theme. Until it lands, hyprlock draws its own
colour. The `image` block in the row above is the other case, and that file
really never existed.

### What else changed from the dotfiles

Four changes that are neither a dropped reference nor a monitor name. Each one
is a deliberate change of the configuration itself.

| Change                                                    | Why                                                                  |
| --------------------------------------------------------- | -------------------------------------------------------------------- |
| `hyprlock.conf`: `font_family` is `JetBrainsMono Nerd Font`, and the dotfiles wrote `Fira Semibold`, in both labels | The desktop draws in one family. [The Ghostty bundle](ghostty.md) already ships that one, from `ttf-jetbrains-mono-nerd`, and nothing here ships a Fira package. It is the **default** of `KNOB_FONT` and it is written out rather than generated, so the lock screen keeps that family when the knob moves: hyprlock has no offline check of its configuration, and a generated file it refused would leave the machine going idle and never locking. `tests/hyprland.bats` pins the two together, and [Knobs](../knobs.md) records the decision. |
| `hyprpaper.conf`: `ipc = on`, which the dotfiles never set | The control socket. [Issue #24](https://github.com/qdrtech/xghost/issues/24) reloads the wallpaper of a running daemon through it. |
| `hyprland.conf`: `source = conf/decoration.conf`, which the dotfiles never had | The dotfiles carried `conf/decoration.conf` and sourced it from nowhere, so the file was dead and every decoration value came from `conf/theme.conf`. |
| `conf/decoration.conf` and `conf/window.conf` hold the values of the dotfiles' `conf/theme.conf` | `conf/theme.conf` was sourced last, so it overrode `conf/window.conf`, and `conf/decoration.conf` was never sourced at all. Its values are the ones that reached the compositor. The rounding is 6 rather than 10, and the border width is 1 rather than 3. |

The last row has a cost, and it is the one to weigh. The dead
`conf/decoration.conf` of the dotfiles carried eleven blur and shadow settings —
seven in `blur`, four in `shadow` — and no file ever sourced them.
`conf/theme.conf` switched both blocks off, and that is what the compositor ran.
This bundle prescribes what ran, so the blur and the shadow are off here and the
eleven settings are not carried over. Switching them back on is editing one
prescribed file, and every value is in the history of the dotfiles.

## hyprpaper, and what issue #20 has to supply

`hyprpaper.conf` carries the daemon and no wallpaper. No background file is
invented here. Until
[issue #20](https://github.com/qdrtech/xghost/issues/20) lands, hyprpaper starts
and holds no image, and `conf/misc.conf` keeps Hyprland's own wallpaper switched
on so the desktop is never bare.

Issue #20 has to supply three things:

1. **One image per theme**, written by the renderer into the generated output,
   at a fixed relative path such as `hypr/background.png`. A theme may ship it
   by hand under `themes/<name>/files/`, or a template may generate it from the
   palette.
2. **A generated `hypr/wallpaper.conf`** holding one `preload` line and one
   `wallpaper` line whose monitor is empty, so every display carries the image
   and no output name is written down. An empty monitor is what keeps criterion
   2 of this bundle true.
3. **One `source` line in `config/hypr/hyprpaper.conf`**, in the form the other
   bundles use: `../xghost-generated/hypr/wallpaper.conf`. hyprpaper resolves a
   relative `source` against the directory of the file it opened, as Hyprland
   does.

The dotfiles also named a wallpaper per monitor, by output name. That shape must
not come back. One wallpaper with an empty monitor covers every display and
names none of them.

Reloading the running daemon after a theme switch is
[issue #24](https://github.com/qdrtech/xghost/issues/24). `ipc = on` is set here
for it.

## hyprlock is not themed yet

`hyprlock.conf` keeps the literal colours of the dotfiles. hyprlock does read a
`source` line, and it resolves a relative one the same way, so the same bridge
would work. It is not used, because this project has no way to prove it offline:
hyprlock has no `--verify-config`, and running it locks the screen. A lock
screen that fails to start is a session the user cannot get back into, so the
proof has to come first. Theming it belongs with issue #20, which touches the
lock screen background in any case.

## The packages this bundle needs

For the manifest of [issue #7](https://github.com/qdrtech/xghost/issues/7).
Nothing here installs them.

| Package                        | Repository | What needs it                                  |
| ------------------------------ | ---------- | ---------------------------------------------- |
| `hyprland`                     | `extra`    | The compositor.                                |
| `hypridle`                     | `extra`    | `hypridle.conf`, and the autostart.            |
| `hyprlock`                     | `extra`    | `hyprlock.conf`, and the lock keybinding.      |
| `hyprpaper`                    | `extra`    | `hyprpaper.conf`, and the autostart.           |
| `xdg-desktop-portal-hyprland`  | `extra`    | Screen sharing.                                |
| `xdg-desktop-portal`           | `extra`    | The portal front end that the backend needs.   |
| `polkit-gnome`                 | `extra`    | The authentication agent, in the autostart.    |
| `psmisc`                       | `extra`    | `killall`, in the two restart keybindings.     |
| `wireplumber`                  | `extra`    | `wpctl`, in the volume keybindings.            |
| `brightnessctl`                | `extra`    | The brightness keybindings.                    |
| `playerctl`                    | `extra`    | The media keybindings.                         |
| `network-manager-applet`       | `extra`    | `nm-applet`, in the autostart.                 |
| `blueman`                      | `extra`    | `blueman-applet`, in the autostart.            |
| `nautilus`                     | `extra`    | `$fileManager`.                                |
| `ttf-jetbrains-mono-nerd`      | `extra`    | The two labels of `hyprlock.conf`, and the default of `KNOB_FONT`. The Ghostty bundle names it as well. |
| `ttf-cascadia-code-nerd`       | `extra`    | The second value of `KNOB_FONT`. See [Knobs](../knobs.md). |
| `hyprshot`                     | `extra`    | The two screenshot keybindings.                |

Every package above is declared in `install/packages/base.txt`, and
[Installing](../installing.md) records the manifest. `hyprshot` was an AUR
package when the dotfiles recorded it, and it is in `extra` today, so nothing
this bundle needs requires an AUR helper. `pacman -Si hyprshot` names the
repository.

Three more programs are named by this bundle and belong to another one:
`ghostty` is `$terminal` and comes with
[issue #6](https://github.com/qdrtech/xghost/issues/6), `waybar` is the bar and
comes with [issue #12](https://github.com/qdrtech/xghost/issues/12), and `rofi`
is `$menu` and comes with
[issue #13](https://github.com/qdrtech/xghost/issues/13).

`ghostty` and `waybar` are installed, because their own bundles landed first.
`rofi` is not, so a session started today does nothing on
<kbd>Super</kbd>+<kbd>Space</kbd>. [Installing](../installing.md) records what a
first installation leaves out.

## What the tests prove

- `tests/hyprland.bats` proves the bundle. It renders the layout against machine
  facts it writes itself, for one, two and three monitors with names, modes,
  positions, scales and rotations that are not those of any computer running the
  suite. It asserts the exact monitor lines and the exact workspace assignment
  for each. It proves that no monitor output name appears in any prescribed file
  or in any template, that no `exec` line names a script file, and that the
  fallback fragment names no output either. It proves each of the three knobs at
  more than one value, that the animation choice holds one fragment for every
  value the schema names, and that neither the gaps nor the font is left behind
  in a prescribed file.
- The tests that need Hyprland run `Hyprland --verify-config` and skip when
  Hyprland is absent, because continuous integration has none. They prove that
  the whole configuration parses for one, two and three monitors and for the
  fallback, that it parses at every value of every knob, that the missing
  include before the first `theme set` is reported by name, and that removing
  the bridge breaks every include.
- `tests/golden.bats` compares the rendered colours, the monitor layout, the
  workspace assignment, the animations and the knob settings of every theme with
  the committed output under `tests/golden/<knob set>/<theme>/hypr/`. It renders
  against the fixed machine facts of `tests/fixtures/machine/golden.conf` and the
  two fixed knob sets, so the committed output never depends on the hardware
  that produced it or on the preferences of whoever ran it.

## What this bundle does not do

- **It has never been observed running.** Every claim above is proved by
  rendering and by parsing. The machine this bundle was written on runs a live
  Hyprland session that must not be reconfigured, so no `hyprctl reload`, no
  `hyprctl keyword` and no restart was ever run. A first login on a machine with
  a different monitor set is still unobserved.
- **It reloads nothing.** A theme switch and a knob change both write the new
  files and stop. Picking the change up without a restart is
  [issue #24](https://github.com/qdrtech/xghost/issues/24).
- **The keyboard layout is prescribed, not detected.** Detection records
  `MACHINE_KEYBOARD_LAYOUT` and its variant already. The layout in
  `conf/keyboard.conf` is a preference of this desktop rather than a fact of the
  machine, so it is a knob this bundle has not asked for yet. Adding it is a
  record in `schema/knobs.conf` and one template, and no code changes. See
  [Knobs](../knobs.md).
