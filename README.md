# xghost

A prescribed Arch Linux desktop: one command installs a complete, coherent,
themed Hyprland environment.

xghost ships one considered answer for every choice — the bar, the launcher,
the keybindings, the animations. Users configure two things: **machine facts**
(what is physically true about the computer) and **knobs** (a defined set of
supported preferences). Everything else is prescribed configuration owned by
the project.

Requirements, architecture, and scope are recorded in
[issue #1](https://github.com/qdrtech/xghost/issues/1).

This project is under initial development. The terminal and the compositor are
in place; the bar, the launcher and the notifications are not.

## Install

One command installs the desktop on Arch Linux. Run it as the user who will use
the desktop:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/qdrtech/xghost/main/boot.sh)"
```

`boot.sh` installs git if this machine has none, clones the repository to
`~/.local/share/xghost`, and hands off to the installer in that clone. It does
nothing else, and it is under a hundred lines, so you can read it before you run
it rather than piping a script you have not seen into a shell:

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

## Documentation

- [Installing](docs/installing.md) — the package manifests and the installer
  steps.
- [Repository layout](docs/repository-layout.md) — what each directory holds.
- [Adding a command](docs/adding-a-command.md) — the metadata contract of the
  dispatcher.
- [Theming](docs/theming.md) — the palette format, the templates, and the
  renderer that turns them into configuration.
- [Backgrounds](docs/backgrounds.md) — the wallpaper each theme draws from its
  own colours, and the one dependency it proposes.
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
