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

Run it as the user who will use the desktop, on Arch Linux:

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
- [Architecture decision records](docs/adr/) — the decisions and their reasons.
