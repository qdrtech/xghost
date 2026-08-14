# Installing

One command installs the desktop:

```
./install.sh
```

Run it as the user who will use the desktop, from the checkout. It installs the
packages the manifests declare, links the prescribed configuration into your
config directory, reads your machine, renders the theme, and puts the `xghost`
command in reach.

```
./install.sh --dry-run          # report every change and make none
./install.sh --theme tokyonight # set this theme rather than the default one
./install.sh --help
```

## The package manifests

The manifests under `install/packages/` are the single source of truth for what
an installation needs. The packaging steps install exactly what they declare,
and nothing installs a package they do not name.

| File                        | Installed by  | What it holds                                  |
| --------------------------- | ------------- | ---------------------------------------------- |
| `install/packages/base.txt` | `pacman`      | Every package an official repository carries.  |
| `install/packages/aur.txt`  | An AUR helper | Every package only the AUR carries.            |

The format is one package per line. A `#` starts a comment, which may open a
line or follow a package name, and an empty line is allowed.

```
hyprland
psmisc      # killall, in the two restart keybindings
```

The list is derived from two places: the package table of each bundle page under
`docs/bundles/`, and the dependency tables of `qdrtech/dotfiles`,
`docs/installation.md`. A package a later bundle owns is not declared yet. The
bar, the launcher and the notifications arrive with issues #12, #13 and #14, and
each one adds its line then.

Two rules keep the list honest:

- A package of the Arch `base` group is not declared. `util-linux` carries
  `flock` and `systemd` carries `localectl`, and every Arch installation has
  both already. Declaring them would say that this project chose them.
- `tests/install.bats` reads the package table of `docs/bundles/hyprland.md` and
  fails when a package that table lists is in neither manifest. The manifest
  cannot drift away from the bundle that needs the packages.

### Why the AUR is a second file rather than a marked line

The repository a package comes from decides which tool installs it. `pacman`
cannot install an AUR package at all, so that fact has to reach the installer as
something it reads. A file name does. A comment does not: a comment is text the
parser drops, and text the parser drops must never decide which program runs
against a package name.

**The base installation requires no AUR helper.** `aur.txt` declares no package
today. Both the bundle page and the dotfiles call `hyprshot` an AUR package, and
`pacman -Si hyprshot` answers `extra`, so it is in `base.txt` with the rest. The
file and its step stay because a later bundle will need them: `hyprshade`, which
issue #17 owns, has no official package at all.

When `aur.txt` does name a package and no helper is installed, the packaging step
names that package, says what it serves, and lets the installation finish. It
installs no AUR helper by itself, because that would mean building a PKGBUILD
nobody vetted on a machine that asked for a desktop. Install `yay` or `paru` and
run `./install.sh` again, and the step picks the package up.

## The four groups, and what each step does

The installer runs four groups in a fixed order. Inside a group the steps run in
the order of their names.

| Group          | Step                            | What it does                                                     |
| -------------- | ------------------------------- | ----------------------------------------------------------------- |
| `preflight`    | `10-system.sh`                  | Refuse a system that is not Arch, and a machine with no `pacman` or `flock`. |
| `preflight`    | `20-privileges.sh`              | Refuse a run as root. Check that `sudo` is there for the packaging step. |
| `preflight`    | `30-manifests.sh`               | Read both manifests, and report the file and the line of anything that is not a package name. |
| `packaging`    | `10-official.sh`                | Install the packages of `base.txt` that this machine does not have. |
| `packaging`    | `20-aur.sh`                     | Install the packages of `aur.txt` with an AUR helper, when there is one. |
| `config`       | `10-link.sh`                    | `xghost config link --backup`.                                    |
| `config`       | `20-detect.sh`                  | `xghost machine detect`.                                          |
| `config`       | `30-theme.sh`                   | `xghost theme set`.                                               |
| `post-install` | `10-command-path.sh`            | Link `bin/xghost` into your bin directory.                        |
| `post-install` | `20-summary.sh`                 | Prove that a theme is active, then report the end state.          |

Preflight changes nothing at all. Every refusal above happens before the first
package is installed and before the first link is created.

## Why the order is this one

The order is decided by one fact about detection, and it is the reason a naive
order produces a desktop that fails to come up rather than a themed one.

> `hyprctl` answers only inside a running Hyprland session. Detection run before
> that session records `MACHINE_MONITOR_COUNT=unknown`.

Three constraints follow, and they pull against each other:

1. **The render has to happen before the first session.** Hyprland reports a
   `source` line that matches no file as an error, and every prescribed file
   that draws a border names a generated colour. The generated files have to be
   on disk before Hyprland reads its configuration.
2. **The render needs a machine facts file.** The monitor layout and the
   workspace assignment are structural choices keyed on `MACHINE_MONITOR_COUNT`.
   A render with no facts file at all fails by name on that value, so detection
   has to run before the render.
3. **Detection before the session cannot read the monitors.** It records
   `MACHINE_MONITOR_COUNT=unknown`, and no run of the installer can change that.

The order that satisfies all three is link, detect, render, then detect and
render again inside the first session:

```
install.sh   config/10-link.sh    the prescribed configuration and the bridge
             config/20-detect.sh  every fact except the monitors
             config/30-theme.sh   the generated output, complete
first login  xghost machine refresh   the monitors, then the render again
```

The third step works because `unknown` is a value the bundle prescribes a
fragment for. The `default` monitor fragment names no output, so Hyprland takes
the preferred mode of every display it finds and lays them out left to right.
That is the whole point of that fragment: it is what makes a first login
possible on a machine nobody has read yet.

`xghost machine refresh` is one line of the prescribed autostart. It runs
detection again, where `hyprctl` answers, and renders the active theme from what
it read. Running detection twice is safe, and running it at every login is safe
as well: a run that writes the same file makes no copy, so `machine.conf.previous`
still holds the file that was replaced the last time something did change.

**The cost, stated plainly.** The prescribed monitor layout is in place from the
second login. The first login uses the layout Hyprland works out itself. The
terminal, the colours and every other fact are right from the first login,
because none of them needs a compositor.

A step under `post-install/` was the other candidate, and it cannot work: the
installer finishes before any session exists, so a step of the installer is
always outside the session.

## Every step is idempotent

Run `./install.sh` as many times as you like. An installation that stopped part
way through is resumed by running it again, and a finished installation that is
run again changes nothing.

| Step             | What makes it idempotent                                                          |
| ---------------- | ----------------------------------------------------------------------------------- |
| The packaging    | `pacman -T` names what is missing first. With nothing missing, no package operation runs at all. |
| The link         | The linker adopts a path that already points at the prescribed entry and reports `already linked`. |
| The detection    | It writes the whole file from what it reads, so the same machine writes the same file. |
| The render       | The renderer builds a new output directory and moves it into place. The second build of the same inputs is the same output. |
| The command link | A link that already points at this command is reported and left alone.             |

A second run keeps the theme you set. `--theme` overrides that, because naming a
theme is an instruction rather than a default.

## Existing configuration is backed up

The config step runs `xghost config link --backup`. A path that is in the way is
**moved** into a backup directory under your state directory, the exact path it
was moved to is printed, and only then is the link created. The backup is the
original file, because the path is moved and never copied.

```
backup: moved /home/ada/.config/hypr to /home/ada/.local/state/xghost/backups/20260814T151726Z.a7Kq2M/hypr
linked: /home/ada/.config/hypr -> /home/ada/.local/share/xghost/config/hypr
```

One backup directory holds one run, and no run can name the directory of another
run, so a backup never overwrites a backup. [Linking](linking.md) records the
rest of the rules. This project has one backup mechanism, and that is it.

## When a step fails

A step reports the problem, reports what to do about it, and stops. The runner
then names the step:

```
xghost: this is not an Arch Linux system: /etc/os-release reports ID='ubuntu' and ID_LIKE='debian'
xghost: what to do: install xghost on Arch Linux, or on a distribution whose os-release names arch in ID_LIKE. Nothing was changed.
xghost: the step preflight/10-system.sh failed
xghost: what to do: fix the problem reported above, then run './install.sh' again. Every step is idempotent, so the steps that already did their work do nothing the second time.
```

The groups that follow a failed step do not run.

A step is sourced into a shell of its own, and that shell runs under `set -e`.
A step that fails a command it did not guard therefore stops at that command,
and the runner names it. The shell is a separate process rather than a subshell
for exactly that reason: bash ignores `set -e` inside a subshell that is part of
a `||` list, and it ignores it for every command in that subshell, so a step
would carry on to its next line and report success.

## The paths, and how to override each one

| Path                             | Variable               | Default                     |
| -------------------------------- | ---------------------- | ---------------------------- |
| The os-release file preflight reads | `XGHOST_OS_RELEASE` | `/etc/os-release`            |
| The step directory               | `XGHOST_STEPS_DIR`     | `<checkout>/install/steps`   |
| The manifest directory           | `XGHOST_PACKAGES_DIR`  | `<checkout>/install/packages` |
| The bin directory                | `XGHOST_BIN_DIR`       | `$HOME/.local/bin`           |
| The theme a first installation sets | `XGHOST_INSTALL_THEME` | `macos-dark`              |
| The AUR helpers to look for      | `XGHOST_AUR_HELPERS`   | `yay paru`                   |

The paths the config steps write to are the paths of the commands they run.
[Linking](linking.md) and [Machine facts](machine-facts.md) record those.

The `xghost` command is linked into the bin directory, and that link is not in
the link record, so `xghost config unlink` does not remove it. It is the command
itself rather than prescribed configuration. When the bin directory is not on
your `PATH`, the step says so: the command has to be on the `PATH` of your login
shell, because the Hyprland autostart runs `xghost machine refresh` by name.

## What an installation has never been observed doing

The suite proves the order of the steps, every refusal, the dry run, the backup,
the idempotency of a second run, and the end state of a whole installation. Two
things it does not prove, and neither one is worked around:

- **No test installs a package.** Every test that reaches the packaging group
  puts a stub `pacman` first on the `PATH`. The step is proved by the command
  line it builds and by the packages it leaves out, never by a package that was
  installed.
- **No test starts a desktop.** No Hyprland session, no terminal window, and no
  login. The end state is proved as far as an offline test reaches: a complete
  generated output, an active theme, and every prescribed entry linked. That the
  desktop then comes up is the claim the first real installation tests.

[The Hyprland bundle](bundles/hyprland.md) records the same limit for the
configuration itself.
