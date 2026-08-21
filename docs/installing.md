# Installing

## The one command

On a fresh Arch Linux machine, one command installs the whole desktop. Run it as
the user who will use the desktop:

```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/qdrtech/xghost/main/boot.sh)"
```

`boot.sh` does three things, and nothing else:

1. It installs `git`, when this machine has none. That is the one package it
   installs and the one command it runs as root.
2. It clones the repository to the install location, `~/.local/share/xghost`.
3. It hands off to `install.sh` in that clone, which is what installs the
   desktop.

Everything else is a step under `install/steps/`, where it is grouped,
idempotent and tested. A bootstrap that grows is a second installer that nobody
runs the tests against.

### Read it before you run it

You do not have to pipe a script you have not seen into a shell. The bootstrap
is under a hundred lines, and close to half of them are comments, so reading it
first is realistic:

```
curl -fsSLO https://raw.githubusercontent.com/qdrtech/xghost/main/boot.sh
less boot.sh
sh boot.sh
```

Both forms run the same file, and the bootstrap hands its own arguments to the
installer: `sh boot.sh --dry-run` reports every change and makes none.

Two choices in that command are deliberate. It is `sh` rather than `bash`,
because the bootstrap runs before anything has been installed and uses nothing
beyond POSIX shell. And it is `sh -c "$(curl ...)"` rather than `curl ... | sh`,
because a piped script *is* the standard input of the shell reading it: handing
the text to `sh -c` leaves the standard input of the installation attached to
your terminal, so every prompt pacman and `sudo` make still reaches you.

### Running it again is safe

An install location that already holds a checkout is left exactly as it is. The
bootstrap pulls nothing, resets nothing and removes nothing. It reports the
checkout and hands off, and the steps of the installer are all idempotent, so a
second run reaches the same end state. Updating the checkout is one command, and
the bootstrap prints it:

```
git -C ~/.local/share/xghost pull
```

A run that was killed part way through is the case that causes real trouble. git
removes the directory of a clone it interrupts itself, so a directory is left
behind only when the machine lost power or a process took a `SIGKILL`. The
bootstrap then finds a path it cannot clone into, names that path, says what to
do about it, and stops. It deletes nothing: a script fetched over the network must not remove
a directory it did not create. Look at the path, move it aside, then run the
bootstrap again.

### The paths, and how to override each one

| Path                    | Variable             | Default                                 |
| ----------------------- | -------------------- | --------------------------------------- |
| The repository to clone | `XGHOST_REPO`        | `https://github.com/qdrtech/xghost.git` |
| The install location    | `XGHOST_INSTALL_DIR` | `$XDG_DATA_HOME/xghost`, and `$HOME/.local/share/xghost` when that is not set |

The bootstrap clones the default branch of that repository. This project ships
no tag, so a bootstrap that named one would clone a release that does not exist.
The clone is a full one rather than a shallow one, because no image is committed
to this repository and it is therefore the size of its text: what the depth
would save is not worth handing the user a checkout they cannot branch from.

## From a checkout

The installer itself is one command, run from a checkout you already have:

```
./install.sh
```

Run it as the user who will use the desktop. It installs the packages the
manifests declare, links the prescribed configuration into your
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

Two packages are in the file for xghost itself rather than for a bundle:
`xdg-utils`, which detection reads the default browser with, and `python`,
which draws the background of a theme.
[Backgrounds](backgrounds.md) carries the vetting of the second one, and the
line **is a proposal** until the maintainer accepts it.

Two rules keep the list honest:

- A package of the Arch `base` group is not declared. `util-linux` carries
  `flock` and `systemd` carries `localectl`, and every Arch installation has
  both already. Declaring them would say that this project chose them.
- `tests/install.bats` reads the package table of every page under
  `docs/bundles/` and fails when a package one of those tables lists is in
  neither manifest. The manifest cannot drift away from the bundles that need
  the packages.

### Why the AUR is a second file rather than a marked line

The repository a package comes from decides which tool installs it. `pacman`
cannot install an AUR package at all, so that fact has to reach the installer as
something it reads. A file name does. A comment does not: a comment is text the
parser drops, and text the parser drops must never decide which program runs
against a package name.

**The base installation requires no AUR helper.** `aur.txt` names one package,
`hyprshade`, and the desktop draws itself without it. Every package the desktop
needs to draw itself is in `base.txt`, the GTK theme and the icon theme
included, so a machine with no helper still gets a complete desktop. That is the
rule `aur.txt` states for anything added to it later.

Both the bundle page and the dotfiles call `hyprshot` an AUR package, and
`pacman -Si hyprshot` answers `extra`, so it is in `base.txt` with the rest.
`pacman -Si hyprshade` finds nothing at all, which is why that one is not.

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
| `preflight`    | `40-checkout.sh`                | Refuse a `bin/xghost` that is not executable, and a theme name this checkout does not carry. |
| `packaging`    | `10-official.sh`                | Install the packages of `base.txt` that this machine does not have. |
| `packaging`    | `20-aur.sh`                     | Install the packages of `aur.txt` with an AUR helper, when there is one. |
| `config`       | `10-link.sh`                    | `xghost config link --backup`.                                    |
| `config`       | `20-detect.sh`                  | `xghost machine detect`.                                          |
| `config`       | `30-theme.sh`                   | `xghost theme set`.                                               |
| `config`       | `40-shell.sh`                   | Write `~/.zshenv`, so zsh reads the prescribed shell configuration. |
| `post-install` | `10-command-path.sh`            | Link `bin/xghost` into your bin directory.                        |
| `post-install` | `20-summary.sh`                 | Prove that a theme is active, then report the end state.          |

Preflight changes nothing at all. Every refusal above happens before the first
package is installed and before the first link is created. The theme name is
one of those refusals: `./install.sh --theme tokoyonight` stops in preflight and
names the themes this checkout carries.

**The window a config step can still fail in.** Preflight cannot prove that the
render will finish. A theme directory that cannot be read, a full disk, or any
other failure of `config/30-theme.sh` stops the installation after
`config/10-link.sh` has linked the prescribed configuration, and the generated
files the prescribed files include are then not on disk. Hyprland reports a
`source` line that matches no file as an error, so a login made at that point
does not come up. The step names the problem and what to do about it, and
running `./install.sh` again once the problem is fixed completes the render.
`xghost theme set NAME` does the same work on its own. The other way out is
`xghost config unlink`, which removes the links the run created; the
configuration it moved aside is in the backup directory the run printed, and
moving it back is yours to do.

## The one command that needs root

The packaging step is the only step that raises privileges, and it announces the
escalation immediately before it happens:

```
the next command needs root, and it is the only one that does:
  sudo pacman -S --needed -- hyprland hypridle hyprlock
sudo asks for your password now, unless it has one from this terminal already.
```

A run with no package missing raises nothing and prints no such notice. Every
other step runs as you, because every other step writes into your own
directories.

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
             config/40-shell.sh   the ZDOTDIR line that zsh reads first
first login  xghost machine refresh   the monitors, then the render again
```

`config/40-shell.sh` is last of the four because it is the only step that
writes into the home directory rather than into the config directory, and
because it changes nothing at all on a machine whose home directory already
holds a `~/.zshenv` or any startup file of zsh. It never fails the installation:
six of its seven cases are a report, and a home directory that will not take the
write is one of the six. zsh is a login shell rather than a part of the session,
so the rest of the desktop is in place either way and a report is the whole of
what a stop would buy. [The shell bundle](bundles/shell.md) records every case
it meets and how to undo the one file it writes.

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

**A later run does not undo it.** `./install.sh` run again from a terminal, and
`xghost machine refresh` run when `hyprctl` cannot answer, both meet the same
absent source. Neither one puts the monitors back to `unknown`: detection keeps
the value of the previous run for any fact whose source did not answer, names
every fact it kept, and writes the file it was already holding. [Machine
facts](machine-facts.md) records the rule.

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
itself rather than prescribed configuration.

## The one step the installer cannot make for you

Arch puts nothing of `~/.local/bin` on the `PATH` of a login shell. `/etc/profile`
does not name that directory, and this installer edits no shell file of yours.
The `xghost` command therefore lands in the bin directory and may still not run
by name.

That matters because the prescribed autostart carries
`exec-once = xghost machine refresh`, which names a program on the `PATH`. When
the command does not run by name, the installer says so twice: the link step
reports the directory, and the summary reports the `PATH` edit as the step that
is left, in place of the promise that the refresh will run.

```
xghost: one step is left, and it is yours to make: 'xghost' does not run by name on this PATH
xghost: what to do: put /home/ada/.local/bin on the PATH of your login shell, then log out and log in again.
```

Add the line the summary prints to the file your login shell reads, such as
`~/.bash_profile` or `~/.zprofile`, and log in again. Until then the autostart
line fails at every login, the monitors are never read, and the session keeps
the layout Hyprland works out itself. Everything else is already in place.

## What a first installation does not give you yet

The prescribed configuration names two programs that no manifest declares, and
it names them on purpose: each one is a bundle of its own, and the manifest
takes its line when that bundle lands. A first installation therefore has one
visible gap, and one more thing that is simply not there yet.

| What is missing              | What you see                                                     | Issue |
| ---------------------------- | ---------------------------------------------------------------- | ----- |
| The launcher, `rofi`         | <kbd>Super</kbd>+<kbd>Space</kbd> does nothing. `$menu` names `rofi`, and the binding fails the same way. | [#13](https://github.com/qdrtech/xghost/issues/13) |
| The notifications, `swaync`  | No notification is shown, and the bell of the bar opens nothing. Nothing prescribes a daemon yet, so nothing else fails either. | [#14](https://github.com/qdrtech/xghost/issues/14) |

Nothing else in the session depends on those, so the desktop comes up, the
terminal is themed, the bar is styled, and every keybinding that names an
installed program works. Install `rofi` by hand to have it before its bundle
lands. xghost prescribes no configuration for it yet, so it runs with its own
default.

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
