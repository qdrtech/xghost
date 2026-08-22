# xghost

xghost installs one complete Hyprland desktop on Arch Linux, with one command.
The compositor, the terminal, the bar, the launcher, the notifications, the
shell and the editor arrive together, drawn from one palette, and the project
owns every one of those files.

xghost ships one considered answer for every choice: the keybindings, the
animations, the bar layout, the colours. You configure two things. **Machine
facts** are what is physically true about your computer. **Knobs** are a named
set of preferences the project supports. There is no third thing, and there is
no override surface.

## Who it is for

- You run Arch Linux and you want a working Hyprland desktop, rather than a
  weekend of assembling one.
- You want the same desktop on every machine you own.
- You are content to let the project decide what it decides.
- You would rather open an issue than patch a configuration file.

## Who it is not for

Read this half first. It is the half that saves you an installation.

- **You want a dotfiles repository to fork and edit.** Every real configuration
  file belongs to the project and is symbolically linked out of a checkout. An
  edit to one dirties that checkout and conflicts on the next update. That is
  the intended behaviour rather than a rough edge.
- **You want to override a setting the project did not name.** A preference is
  served by a knob or it is not served at all. Run `xghost settings list` to
  read every knob and every value it takes. Anything outside that list is a
  request for a new knob, or a fork.
- **You run a distribution that is not Arch.** The installer refuses to start
  on one, and it says so before it changes anything.
- **You want a release to pin to.** This project has no tags, no version number
  and no release process. `xghost system doctor` reports the commit you are on.

[ADR 0001](docs/adr/0001-prescribed-config-architecture.md) records why the
project is strict, and records that the decision is reversible.

## Install

One command installs the desktop. Run it as the user who will use the desktop:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/qdrtech/xghost/main/boot.sh)"
```

`boot.sh` installs git if this machine has none, clones the repository to
`~/.local/share/xghost`, and hands off to the installer in that clone. It does
nothing else, and it is under a hundred lines, so you can read it first rather
than piping a script you have not seen into a shell:

```sh
curl -fsSLO https://raw.githubusercontent.com/qdrtech/xghost/main/boot.sh
less boot.sh
sh boot.sh
```

From a checkout you already have, run the installer itself:

```sh
./install.sh
./install.sh --dry-run   # report every change and make none
```

The installer runs four groups of steps in order: preflight, packaging, config
and post-install. Every step is idempotent, so an installation that stopped part
way through is resumed by running it again. Existing configuration in the way is
moved into a backup directory, and the exact path is printed.

[Installing](docs/installing.md) records what each group does, why the order is
what it is, and what an installation has never been observed doing.

## What you may change

| What                       | Who owns it                             | Where it lives                        |
| -------------------------- | --------------------------------------- | ------------------------------------- |
| [Machine facts](docs/machine-facts.md) | You, and detection writes the file | `~/.config/xghost/machine.conf`   |
| [Knobs](docs/knobs.md)     | You, against a schema the project owns  | `~/.config/xghost/knobs.conf`         |
| Prescribed configuration   | The project                             | The checkout, linked into `~/.config` |
| Generated output           | Nobody. The renderer rebuilds it        | `~/.local/state/xghost/generated`     |

Edit the first two. Leave the last two alone.

An update replaces the checkout and never writes to your config directory, so
both of your files survive every update untouched. `xghost machine detect`
replaces the machine facts file whole, and it keeps a copy of the file it
replaced. [Machine facts](docs/machine-facts.md) records how to correct a
detection that read your machine wrongly.

## The commands

`xghost` routes a group and a verb. Run `xghost` for this list, and
`xghost <group> <verb> --help` for the detail of one command.

| Command                     | What it does                                                    |
| --------------------------- | --------------------------------------------------------------- |
| `xghost theme list`         | List the available themes.                                       |
| `xghost theme set NAME`     | Set the active theme.                                            |
| `xghost theme current`      | Report the active theme.                                         |
| `xghost settings list`      | List every knob, its value and the values it takes.              |
| `xghost settings set KNOB VALUE` | Set one knob and render the configuration again.            |
| `xghost machine detect`     | Detect this computer and write the machine facts file.           |
| `xghost machine refresh`    | Read this computer again and render the active theme from what it reads. |
| `xghost config link`        | Link the prescribed configuration into your config directory.    |
| `xghost config unlink`      | Remove the configuration links that xghost created.              |
| `xghost system update`      | Update the project, the system packages and this machine.        |
| `xghost system doctor`      | Report whether this installation is healthy.                     |
| `xghost system reload`      | Tell the running components to read their configuration again.   |

A theme change and a knob change both render the configuration again and tell
the running components to read it, so neither one needs a logout:

```sh
xghost theme set tokyonight
xghost settings set KNOB_BAR_POSITION bottom
```

[Adding a command](docs/adding-a-command.md) records the metadata contract
behind that list.

## Known limits

Each one is stated where it belongs as well, and none of them is worked around.

- **The prescribed monitor layout is in place from the second login.**
  `hyprctl` answers only inside a Hyprland session, so the installer cannot read
  your monitors before the first one. [Installing](docs/installing.md) records
  the order and the cost.
- **The wallpaper of a running session follows on the next login.** hyprpaper
  has no reload request in the version this project installs.
  [Backgrounds](docs/backgrounds.md) and [Reloading](docs/reloading.md) record
  it.
- **The editor is themed in its chrome and not in its syntax.** The colours of
  the language constructs come from a colourscheme plugin rather than from the
  palette. [The Neovim bundle](docs/bundles/neovim.md) records what that looks
  like.
- **The lock screen keeps its own colours and its own font.** hyprlock has no
  offline check of its configuration, and a lock screen that fails to start is a
  machine that never locks. [The Hyprland bundle](docs/bundles/hyprland.md)
  records it.
- **The notification centre sits in a fixed corner.** It does not follow
  `KNOB_BAR_POSITION`, so at `bottom` a notification covers the bar.
  [The SwayNC bundle](docs/bundles/swaync.md) records why.
- **The blue light filter is prescribed and not started.** xghost installs no
  systemd unit. [The supporting bundles](docs/bundles/supporting.md) names the
  two commands that start it.
- **A theme change has never been watched reaching a running desktop.** The
  signal each component takes is proved; the redraw is reasoned.
  [Reloading](docs/reloading.md) keeps the list of what is observed and what is
  not.

`xghost system doctor` reports the state of your own installation, and every
problem it names carries the command that fixes it.

## Documentation

- [Installing](docs/installing.md) — the package manifests and the installer
  steps.
- [Updating](docs/updating.md) — what `xghost system update` does, how to write
  a migration, and what the runner records.
- [The doctor](docs/doctor.md) — what `xghost system doctor` checks, what
  "stale" is defined as, and what that definition cannot detect.
- [Reloading](docs/reloading.md) — how a theme change reaches a running desktop,
  which components take a signal, and which need none.
- [Repository layout](docs/repository-layout.md) — what each directory holds.
- [Adding a command](docs/adding-a-command.md) — the metadata contract of the
  dispatcher.
- [Theming](docs/theming.md) — the palette format, the templates, the renderer
  that turns them into configuration, and how to add a theme.
- [Backgrounds](docs/backgrounds.md) — the wallpaper each theme draws from its
  own colours.
- [Machine facts](docs/machine-facts.md) — what detection reads, the file it
  writes, and how you correct it.
- [Knobs](docs/knobs.md) — the preferences this desktop supports, the schema
  behind them, and the two commands that read and change them.
- [Linking](docs/linking.md) — how the prescribed configuration reaches
  `~/.config`.
- [The Ghostty bundle](docs/bundles/ghostty.md) — the terminal, and the first
  application that reads the generated output.
- [The Hyprland bundle](docs/bundles/hyprland.md) — the compositor, and the
  first application whose configuration is rendered from the machine facts.
- [The Waybar bundle](docs/bundles/waybar.md) — the bar, and the first
  application that keeps the value of the file that includes the generated one.
- [The shell bundle](docs/bundles/shell.md) — zsh, starship and tmux, and the
  first bundle whose entry point sits outside the config directory.
- [The Rofi bundle](docs/bundles/rofi.md) — the launcher, and the one
  application that cannot reach the generated output by a relative path.
- [The SwayNC bundle](docs/bundles/swaync.md) — the notification centre, and the
  one application that reports a broken style sheet and starts anyway.
- [The supporting bundles](docs/bundles/supporting.md) — GTK, hyprshade and the
  AUR helper, and the three configurations that sit behind the desktop rather
  than on it.
- [The Neovim bundle](docs/bundles/neovim.md) — the editor, the one
  configuration this project imported from a repository of its own, and the one
  written in a programming language.
- [Architecture decision records](docs/adr/) — the decisions and their reasons.

Requirements and scope are recorded in
[issue #1](https://github.com/qdrtech/xghost/issues/1).
