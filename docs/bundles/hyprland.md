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
| `templates/hypr/monitors.conf.choice.MACHINE_MONITOR_COUNT/`  | Choice | The monitor layout, one fragment per count.  |
| `templates/hypr/workspaces.conf.choice.MACHINE_MONITOR_COUNT/` | Choice | Which workspace opens on which monitor.     |

The file categories are those of
[ADR 0001](../adr/0001-prescribed-config-architecture.md). The structural choice
is documented in [Theming](../theming.md).

Everything is carried over from `qdrtech/dotfiles`, path
`hyprland/.config/hypr/`. What changed, and why, is recorded below.

## How the files meet

```
xghost config link     $XDG_CONFIG_HOME/hypr             -> <install location>/config/hypr
                       $XDG_CONFIG_HOME/xghost-generated -> $XDG_STATE_HOME/xghost/generated
xghost theme set NAME  $XDG_STATE_HOME/xghost/generated/hypr/colors.conf
                       $XDG_STATE_HOME/xghost/generated/hypr/monitors.conf
                       $XDG_STATE_HOME/xghost/generated/hypr/workspaces.conf
                       $XDG_STATE_HOME/xghost/generated/hypr/theme.conf
```

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

## The colours

`templates/hypr/colors.conf` defines the palette of the theme as Hyprland
variables, and `hyprland.conf` sources it first, so every prescribed file below
may name `$bg`, `$accent` and the rest.

`templates/hypr/theme.conf` holds the styling that depends on those colours, and
it is sourced last, so the theme wins over every prescribed file. Today it is
the two border colours. The dotfiles carried a `conf/theme.conf` that set the
rounding, the gaps and the border width a second time as well; those values are
prescribed now, in `conf/decoration.conf` and `conf/window.conf`, with the
values that actually reached the compositor.

## The dead `xdg.sh` reference

`conf/autostart.conf` in the dotfiles ran `~/.config/hypr/scripts/xdg.sh` at
every login. No commit on any branch of that repository ever contained that
script, and the line had been there since March 2025. It failed in silence at
every login for over a year.

The line is **dropped**, and nothing replaces it, because the work it named is
already done. Hyprland performs the environment import itself. The binary of
Hyprland 0.56.2 carries it as a literal string:

```
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME PATH XDG_DATA_DIRS && … dbus-update-activation-environment --systemd …
```

Screen sharing needs the `xdg-desktop-portal-hyprland` package beside
`xdg-desktop-portal`, and no configuration file at all. Both belong in the
package manifest of [issue #7](https://github.com/qdrtech/xghost/issues/7).

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
| `exec-once = sh ~/.config/waybar/scripts/launch.sh` | `exec-once = waybar`. The bar is [issue #12](https://github.com/qdrtech/xghost/issues/12). |
| `exec = sh ~/.config/scripts/import-gsettings.sh`  | Dropped. GTK is [issue #17](https://github.com/qdrtech/xghost/issues/17). |
| `exec = hyprshade auto`                            | Dropped. hyprshade is [issue #17](https://github.com/qdrtech/xghost/issues/17). |
| `bind = … exec, sh ~/.config/hypr/scripts/hyprpaper.sh` | The two commands of that script are inline in the binding, and the script is gone. |
| `bind = $SUPER_SHIFT, f, fullscreen`               | `bind = $mainMod SHIFT, F, fullscreen`. No file ever defined `$SUPER_SHIFT`, so neither key that used it worked. |
| `bind = $SUPER_SHIFT, l, exec, hyprlock`           | `bind = $mainMod SHIFT, L, exec, hyprlock`. The same fault.             |
| `input-field { monitor = DP-1 }` in `hyprlock.conf` | `monitor =`, which is every monitor. No output name may appear.        |
| `background { path = …/blurred_wallpaper.png }`    | Dropped. No commit of the dotfiles ever held that file.                 |
| `image { path = …/ml4w/cache/square_wallpaper.png }` | Dropped. The same fault, and the tool it named is not used here.      |
| `conf/environment.conf`                            | Dropped. The file was empty, so the fragment and its `source` line both did nothing. |
| The ML4W comments in `hypridle.conf`               | Dropped. They instruct a settings application this project does not use. |

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
| `polkit-gnome`                 | `extra`    | The authentication agent a desktop session needs. |
| `psmisc`                       | `extra`    | `killall`, in the two restart keybindings.     |
| `wireplumber`                  | `extra`    | `wpctl`, in the volume keybindings.            |
| `brightnessctl`                | `extra`    | The brightness keybindings.                    |
| `playerctl`                    | `extra`    | The media keybindings.                         |
| `network-manager-applet`       | `extra`    | `nm-applet`, in the autostart.                 |
| `blueman`                      | `extra`    | `blueman-applet`, in the autostart.            |
| `nautilus`                     | `extra`    | `$fileManager`.                                |
| `hyprshot`                     | AUR        | The two screenshot keybindings.                |

Three more programs are named by this bundle and belong to another one:
`ghostty` is `$terminal` and comes with
[issue #6](https://github.com/qdrtech/xghost/issues/6), `rofi` is `$menu` and
comes with [issue #13](https://github.com/qdrtech/xghost/issues/13), and
`waybar` is the bar and comes with
[issue #12](https://github.com/qdrtech/xghost/issues/12).

## What the tests prove

- `tests/hyprland.bats` proves the bundle. It renders the layout against machine
  facts it writes itself, for one, two and three monitors with names, modes,
  positions, scales and rotations that are not those of any computer running the
  suite. It asserts the exact monitor lines and the exact workspace assignment
  for each. It proves that no monitor output name appears in any prescribed file
  or in any template, that no `exec` line names a script file, and that the
  fallback fragment names no output either.
- The tests that need Hyprland run `Hyprland --verify-config` and skip when
  Hyprland is absent, because continuous integration has none. They prove that
  the whole configuration parses for one, two and three monitors and for the
  fallback, that the missing include before the first `theme set` is reported
  by name, and that removing the bridge breaks every include.
- `tests/golden.bats` compares the rendered colours, the monitor layout and the
  workspace assignment of every theme with the committed output under
  `tests/golden/<theme>/hypr/`. It renders against the fixed machine facts of
  `tests/fixtures/machine/golden.conf`, so the committed output never depends on
  the hardware that produced it.

## What this bundle does not do

- **It has never been observed running.** Every claim above is proved by
  rendering and by parsing. The machine this bundle was written on runs a live
  Hyprland session that must not be reconfigured, so no `hyprctl reload`, no
  `hyprctl keyword` and no restart was ever run. A first login on a machine with
  a different monitor set is still unobserved.
- **It reloads nothing.** A theme switch writes the new files and stops.
  Picking the change up without a restart is
  [issue #24](https://github.com/qdrtech/xghost/issues/24).
- **The keyboard layout is prescribed, not detected.** Detection records
  `MACHINE_KEYBOARD_LAYOUT` and its variant already. The layout in
  `conf/keyboard.conf` is a preference of this desktop rather than a fact of the
  machine, and a preference is a knob
  ([issue #11](https://github.com/qdrtech/xghost/issues/11)).
