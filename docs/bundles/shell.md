# The shell bundle

zsh is the shell of xghost, starship draws its prompt, and tmux multiplexes it.
This is the first bundle that no compositor starts. A user starts it, so it is
also the first one whose entry point sits outside the config directory.

The bundle is two prescribed files and one generated one:

| File                              | Category   | What it holds                                       |
| --------------------------------- | ---------- | ---------------------------------------------------- |
| `config/zsh/.zshrc`               | Prescribed | The whole interactive zsh configuration.             |
| `config/tmux/tmux.conf`           | Prescribed | The whole tmux configuration.                        |
| `templates/starship/starship.toml`| Template   | The whole starship configuration, with the palette of the theme. |

The file categories are those of
[ADR 0001](../adr/0001-prescribed-config-architecture.md). The bridge to the
generated output is
[ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md).

The files come from `qdrtech/dotfiles`: `zshrc/.zshrc`, `tmux/.tmux.conf`, and
the Starship section of `scripts/theme-switch.sh`. Most of that zshrc did not
come across. "What the dotfiles keep" below lists every line and its reason.

## How the files meet

```
xghost config link     $XDG_CONFIG_HOME/zsh              -> <install location>/config/zsh
                       $XDG_CONFIG_HOME/tmux             -> <install location>/config/tmux
                       $XDG_CONFIG_HOME/xghost-generated -> $XDG_STATE_HOME/xghost/generated
install.sh             ~/.zshenv                          holds the ZDOTDIR and STARSHIP_CONFIG lines
xghost theme set NAME  $XDG_STATE_HOME/xghost/generated/starship/starship.toml
```

tmux 3.7 reads `$XDG_CONFIG_HOME/tmux/tmux.conf` on its own, so the first link
is the whole of the tmux half. zsh needs the fourth line as well, and "zsh has
one entry point" below is about that line alone.

## The whole starship configuration is generated

starship reads one file and offers no include of any kind. There is no
`include`, no `import`, and no second file it merges. Its palette has to be
declared in the same file as the modules that name a colour of it.

So this bundle has no prescribed starship file. `templates/starship/starship.toml`
is the file the project owns, and `xghost theme set` renders the whole of it.
SwayNC is the only other application in this project in that position, and
[ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md) records both.

What that costs is stated plainly: a change to any starship setting is a change
to a template rather than to a prescribed file, and the golden output has to be
regenerated with it. What it buys is that the prompt carries the ten colours of
the palette directly, as a starship palette, rather than through the sixteen
slots of the terminal.

## The include form: this bundle uses the bridge

The shell can write a path in a form no other application in the project can:

```
${XDG_CONFIG_HOME:-$HOME/.config}/...
```

[ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md) records the shell
as the one entry of its table that expands a variable **and** the XDG default
inline, and that fails loudly on a file it cannot read. That opens a form the
other four bundles have no way to write: naming the state directory itself, and
reaching the generated output with no link in between.

**This bundle names the bridge all the same.** Two files hold the same line,
the prescribed zshrc and the `~/.zshenv` the install step writes:

```sh
export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/xghost-generated/starship/starship.toml"
```

"Where the export lives" below records why it is in both.

The line uses what only the shell can do, and it uses it on the half of the path
that needs it. `XDG_CONFIG_HOME` is unset on most machines, and
`$XDG_CONFIG_HOME/...` alone would then expand to a path that starts at the root
of the file system. That is the same construction, and the same three reasons,
as the Waybar include array in [the Waybar bundle](waybar.md).

Three reasons for the bridge rather than the state directory, and a bundle that
differed from the other four would need better ones:

- **One construction serves five bundles.** A reader who has read one bundle
  page knows how every bundle reaches the generated output. A second form is a
  second form to get wrong, which is the driver ADR 0002 was written under.
- **`xghost config unlink` takes the whole installation out in one step.** The
  bridge is a link the linker created and records. A shell that named the state
  directory would still be reading generated output after every other
  application had stopped, and it would keep reading it after the checkout was
  gone.
- **The shell gains no independence by avoiding the bridge.** `xghost config
  link` creates the bridge and links `config/zsh` in the same run. There is no
  state of a machine in which the prescribed zshrc is in place and the bridge is
  not, so a path that avoided the bridge would avoid a dependency the file
  already has.

`generated` under the state directory is itself a symbolic link that
`xghost theme set` replaces in one step, so a theme switch changes no line of
this bundle.

### The one miss this bundle reports itself

starship reads `STARSHIP_CONFIG`, and when the file is not there it draws its
own default prompt and says nothing at all. That is the silent miss ADR 0002
exists to prevent. Two of this project's applications are loud and three are
silent; starship is a fourth silent one, and it is silent in the one place the
project can do something about it.

The prescribed zshrc therefore reports it:

```
xghost: the generated starship configuration is missing: /home/ada/.config/xghost-generated/starship/starship.toml
xghost: this shell draws the default prompt of starship. Run 'xghost theme set <name>' to render that file.
```

The prompt still starts. A default prompt is better than no prompt, and the two
lines above say which one the reader is looking at. This is the state between
`config/10-link.sh` and `config/30-theme.sh`, and a shell opened in that window
is the only way to meet it on a finished installation.

### Where the export lives, and the boundary it draws

The report above covers a shell that read the prescribed zshrc. A shell that
did not read it is the second half of the same silent fallback, and it needs the
export somewhere else.

zsh reads `.zshrc` for an **interactive** shell alone. `zsh -c` and `zsh -l -c`
both leave `STARSHIP_CONFIG` unset, and starship with that variable unset reads
`~/.config/starship.toml` and says nothing. On a machine that ran the dotfiles
this bundle came from, that path holds the prompt `scripts/theme-switch.sh`
wrote, so a starship outside an interactive zsh would draw the old prompt.

So the export is in the `~/.zshenv` that
`install/steps/config/40-shell.sh` writes, beside the `ZDOTDIR` line. zsh reads
`~/.zshenv` for **every** shell it starts. Two other places were tried and
neither one works:

| Where                       | What zsh does with it                                                     |
| --------------------------- | -------------------------------------------------------------------------- |
| `~/.zshenv`                 | Read for every shell: interactive, login, `zsh -c`, and a zsh script. **This is where the line is.** |
| `config/zsh/.zshenv`        | Never read. zsh reads `~/.zshenv` as `$ZDOTDIR/.zshenv` **before** `ZDOTDIR` is set, and it does not read a `.zshenv` again once the variable names another directory. |
| `config/zsh/.zprofile`      | Read for a login shell only, so `zsh -c` and a zsh script still fall back.  |

The prescribed zshrc keeps the same line, and the two carry the same text on
purpose. That copy covers an interactive shell whose `~/.zshenv` was written by
hand and carries the `ZDOTDIR` line alone, which is what the refusal messages of
the install step ask a reader to write. `tests/shell.bats` compares the two texts
and fails when they stop matching, so the duplication cannot drift.

**A leftover `~/.config/starship.toml`.** This bundle writes nothing at that
path and removes nothing from it. A machine that used the dotfiles has a file
there, and it is now read by no shell of this desktop. Delete it once the prompt
of this bundle is drawing, or keep it: with `STARSHIP_CONFIG` set for every zsh,
nothing reads it either way. It is named here so that a reader who deletes it
knows what they are deleting, and so that a reader who meets an unexpected
prompt has the one path to look at.

## zsh has one entry point, and it is not in the config directory

zsh reads `~/.zshrc`. It reads `$ZDOTDIR/.zshrc` instead when `ZDOTDIR` is set,
and `ZDOTDIR` can be set in one place: `~/.zshenv`, which zsh reads before
anything else.

That file is in the home directory rather than in the config directory, so
[the linker](../linking.md) cannot reach it: it links the top level entries of
`config/` into `$XDG_CONFIG_HOME` and creates the bridge, and it writes nothing
anywhere else. `install/steps/config/40-shell.sh` is what puts the lines there,
and it writes two:

```sh
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/xghost-generated/starship/starship.toml"
```

The first is what makes zsh read the prescribed `.zshrc` at all. The second is
there because `~/.zshenv` is the one file zsh reads for every shell, and "Where
the export lives" above records the boundary it draws.

The step **creates** `~/.zshenv` and never edits one. It follows
`install/steps/post-install/10-command-path.sh` for the one case the two share:
that step creates one path under the home directory when nothing is there, and
`xghost config unlink` removes neither path, because no prescribed entry stands
behind either one. The two differ on a path that holds something else, and they
differ on purpose. `10-command-path.sh` calls `install_fail` there and **stops
the installation**, because every config step runs the command it links. This
step reports and carries on.

Seven cases, and six of them change nothing:

| What the step finds                                                    | What it does                                                       |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Neither `~/.zshenv` nor a zsh startup file                             | Writes `~/.zshenv` with both lines above, and says so.               |
| A `~/.zshenv` that already holds the `ZDOTDIR` line                    | Nothing. This is the second run of an installation. A file that carries no `STARSHIP_CONFIG` line is reported, because the step edits no file it did not write. |
| A `~/.zshenv` that sets `ZDOTDIR` itself                               | Nothing. That path is a choice the user made.                        |
| A `~/.zshenv` that sets something else                                 | Nothing. It prints the two lines and where to put them.              |
| A `~/.zshenv` that is a directory                                      | Nothing. zsh reads nothing from a directory and no line can be added to one, so it says that rather than advice that cannot be followed. |
| No `~/.zshenv` and a `~/.zshrc`, `~/.zprofile`, `~/.zlogin` or `~/.zlogout` | Nothing. It names the file it found. See below.                 |
| A home directory that does not take the write                          | Nothing. It reports the path and the permissions to check.           |

The sixth case is the one worth the paragraph. `ZDOTDIR` moves **every** startup
file of zsh, not `.zshrc` alone: `$ZDOTDIR/.zprofile`, `$ZDOTDIR/.zlogin` and
`$ZDOTDIR/.zlogout` are where zsh looks once the variable is set. A `PATH`
addition, an `ssh-agent`, a `umask` or a keychain unlock in any of those four
would stop running at the next login, with no message anywhere. The step refuses
that. It names the file it found rather than the class of file, states that the
two cannot both be the file zsh reads, and prints the lines for the reader to
add once they have moved what they want to keep.

A file it found that is a **dangling symbolic link** gets its own message. There
is nothing at the end of it to move out, so telling the reader to move what they
want to keep would be advice about an empty path. The step refuses all the same,
because `ZDOTDIR` would stop zsh looking at the link at all and a link that is
repointed tomorrow would then be read by nothing.

None of the seven cases fails the installation, the last one included. The rest
of the desktop is in place either way, and zsh is a login shell rather than a
part of the session, so a home directory that will not take one file is a report
and not a stop.

**To undo it: remove `~/.zshenv`.** zsh then reads `~/.zshrc` again, and nothing
of this bundle is left in the home directory. `xghost config unlink` does not
remove it and never will, because the linker wrote it under no record; that
command names the file and prints the same one line instead. Removing the links
without removing `~/.zshenv` leaves `ZDOTDIR` pointing at a directory that is
gone, and zsh then reads no startup file at all, the `~/.zshrc` of the user
included.

### What the shell writes, and where

`ZDOTDIR` is a symbolic link into the checkout, and two things zsh does would
write into it:

| What                      | Where it goes by default | Where this bundle puts it                          |
| ------------------------- | ------------------------- | -------------------------------------------------- |
| The completion dump       | `$ZDOTDIR/.zcompdump`     | `${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump`     |
| The command history       | `~/.histfile`             | `${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history` |

The first is a requirement rather than tidiness: `compinit` with no `-d` writes
its dump beside the `.zshrc` it read, so every login would drop an untracked
file into a git working tree. The second follows the rule
[theming](../theming.md) gives the generated output: derived state that has to
survive a reboot goes in the state directory.

zsh creates neither directory, so the prescribed file creates both with
`mkdir -p`. A `mkdir` that fails reports on standard error, and nothing in the
file hides one.

**The first shell after an installation has an empty history.** The history of
the dotfiles is at `~/.histfile`, this bundle claims no migration and needs
none, and nothing copies that file to the new path. The old file is left exactly
where it is and is read by nothing. `install/steps/config/40-shell.sh` says so
on the run that writes `~/.zshenv`, so the empty history is not a surprise the
reader meets alone in a terminal. A reader who wants the old history keeps it by
hand: `cat ~/.histfile >>"${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"`
with no shell running, or the file is deleted, or it is left where it is.

## What the dotfiles keep

This is criterion 3 of [issue #15](https://github.com/qdrtech/xghost/issues/15),
and it is a filter rather than a migration. Every line below stayed in
`qdrtech/dotfiles`. A line that could be read either way stayed there too:
shipping the working configuration of one person in a public product is worse
than a bundle that is thin.

The table names the **shape** of each line rather than what it held. A page that
listed the contents would republish exactly what criterion 3 keeps out of the
bundle, so the registry region of an employer, the account names and the private
paths are not here. Each row still says what class of thing was left behind,
which is what a reader needs to tell whether their own line is covered.

| Lines of `zshrc/.zshrc`                                | Why they stayed                                                              |
| -------------------------------------------------------- | ----------------------------------------------------------------------------- |
| A work-specific alias that authenticates against a private container registry | The line criterion 3 names. It is the configuration of an employer, and the registry and the region it names belong to that employer rather than to this desktop. |
| Two aliases and a `PATH` line that name a personal scripts directory | Each one runs a script that lives in the dotfiles. This project ships no scripts directory and no script the alias could reach. |
| A start-up line that draws a banner and a system summary  | The banner is the name of the maintainer, and this project installs neither of the two programs the line runs. |
| The alias that ran the theme switcher of the dotfiles     | Replaced by `xghost theme set`, which is criterion 4. The path it named is a checkout of the dotfiles. |
| The editor exports                                        | This desktop installs no editor, so the lines name a program that need not be on the machine. Which editor to ship is a decision this bundle does not carry. |
| A fuzzy-finder default command                            | Neither the finder nor the search tool it names is installed by this project. |
| Five blocks that set up language runtimes and package managers installed by hand | Each one names a directory under the home directory of one person and sources files that this project neither installs nor creates. A guard would not help: there is nothing on this desktop for them to find. |
| A `PATH` line and an install directory for a hosting provider and for a personal tool | Accounts and installations of the maintainer. |
| The pywal sequence block, and the `sed` in it             | Reads the colour cache of pywal. This project renders its colours instead, and [the Waybar bundle](waybar.md) dropped the pywal colour picker for the same reason. |
| The `PS1` assignment                                      | starship replaces the prompt two lines later, so the line already did nothing. |
| The `compinstall` marker `zstyle`                         | A marker `compinstall` writes about its own bookkeeping, naming a file this bundle does not use. |
| The history path                                          | The setting is kept and the path is not. See "What the shell writes, and where" above. |
| An `ls` alias carrying a BSD colour flag                  | That flag is the colour flag of the BSD `ls` of macOS. GNU `ls` reads it as "drop the group column" instead, so the line changed the output and undid the `--color=auto` alias above it. |
| Eight parent-directory aliases                            | A navigation habit of one person, and there is no depth this project could defend as the right one. |

| Line of `tmux/.tmux.conf`                                | Why it stayed                                                                |
| -------------------------------------------------------- | ----------------------------------------------------------------------------- |
| The four `tpm` lines: the plugin manager, `tmux-resurrect`, `tmux-continuum`, and `@continuum-restore` | `tpm` is a repository the user clones into `~/.tmux/plugins/tpm` by hand. This project installs no package for it and clones no repository, so `run -b ~/.tmux/plugins/tpm/tpm` would name a path that is not there at every server start. Shipping it would also mean running code fetched from GitHub at the start of every session, which no other bundle of this project does. |

Three lines of the dotfiles reached this bundle changed rather than dropped:
the `~/.local/bin` `PATH` line, the reload binding, and the lower case `m-j`.
All three are in "What changed from the dotfiles" below, with the rest of what
that section changed.

## What changed from the dotfiles

| Change                                                    | Why                                                                        |
| ---------------------------------------------------------- | --------------------------------------------------------------------------- |
| `~/.local/bin` is put on the `PATH`, with a guard          | `xghost theme set` replaces the `ts` alias, and it runs by name only from a directory on the `PATH`. `install/steps/post-install/10-command-path.sh` links the command into `~/.local/bin`, and Arch puts that directory on the `PATH` of no login shell. The guard is what keeps a second read of the file from naming the directory twice. |
| `bind r source-file ~/.tmux.conf` is a `run-shell`         | See "The reload binding" below.                                             |
| `bind -n m-j` is `bind -n M-j`                             | tmux accepts the lower case form and binds `M-j`, which was read back from a running server, so the key worked. The line is written like its three neighbours so that a reader is not left wondering. |
| The starship `[aws]` module and `$aws` in the format string | The prompt showed an AWS profile and the duration of its credentials. The issue names the AWS content of these dotfiles as the thing that stays behind, and a module that draws an employer's profile name into a prompt is on that side of the line. |
| The empty starship `[git_state]` section                    | It set nothing. A section that declares no key states an intent that the file does not carry. |
| The starship `[rust]`, `[ruby]`, `[haskell]` and `[bun]` sections | The `format` string names none of the four, so starship rendered none of them. See "Four sections that drew nothing" above. |
| The starship palette is named `xghost` rather than `theme`  | One name for the palette of this project, in the one file that declares it.  |

Everything else is carried over unchanged, the emoji of `[package]` included:
changing a symbol is a styling decision, and this bundle makes none.

### The reload binding

`prefix r` reloads the tmux configuration, and the path it names is the one line
of this bundle that names its own file. Three facts were read from tmux 3.7 on a
private socket:

| What was tried                                       | What tmux did                                    |
| ---------------------------------------------------- | ------------------------------------------------- |
| `source-file ~/path` in a configuration file          | Expands `~`.                                     |
| `source-file "$XDG_CONFIG_HOME/path"`                 | Expands the variable.                            |
| `source-file "${XDG_CONFIG_HOME:-$HOME/.config}/path"`| Refuses it: `invalid environment variable`, and the whole file stops there. |

tmux has the variable and not the default, so a tmux-only path is right only
while `XDG_CONFIG_HOME` is set, which it is not on most machines. That is the
divergence ADR 0002 exists to prevent, in the one directive of this bundle that
could still have it. So the path is expanded by `/bin/sh` instead:

```
bind r run-shell 'tmux source-file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" && tmux display-message "tmux: reloaded"'
```

`tmux` inside `run-shell` reaches the server that ran it, through `$TMUX`, so
the binding reloads the server the key was pressed in. `tests/shell.bats` runs
it with `XDG_CONFIG_HOME` moved away from its default and reads the settings
back out of the server.

### tmux refuses a shell that is not on the machine

`set -g default-shell /usr/bin/zsh` is the Arch path of the `zsh` package the
manifest declares, so it is right on every machine this desktop installs on.
What tmux does when the path is **not** there was read from tmux 3.7 on a
private socket, and it is worth writing down, because the two halves differ:

| When tmux meets it                          | What tmux does                                                     |
| ------------------------------------------- | ------------------------------------------------------------------- |
| Reading the file at start, with `-f`        | Drops the setting **in silence** and works the shell out itself. See the fallback below. |
| `source-file`, in a running server          | Reports `not a suitable shell: <path>` and returns 1. It reads the rest of the file all the same. |

What tmux falls back to is not `$SHELL`. Its `getshell()` takes `$SHELL` only
when that value passes `checkshell()`, which wants an absolute path to something
executable that is not tmux itself; otherwise it takes the shell of the passwd
entry, and if that fails too, `/bin/sh`. Read back from tmux 3.7b on a private
socket, with `default-shell` naming a path that is not there:

| `$SHELL`      | What `default-shell` read back as | Why                                       |
| ------------- | --------------------------------- | ------------------------------------------- |
| `/bin/bash`   | `/bin/bash`                       | Passes `checkshell()`.                     |
| `/bin/dash`   | `/usr/bin/zsh`                    | Not on this machine, so the passwd shell.  |
| unset         | `/usr/bin/zsh`                    | The passwd shell.                          |

That matters for one reason only, and it is the reason the assertion below is
built the way it is: on a machine whose passwd shell is already `/usr/bin/zsh`,
which is every machine this desktop is installed on, the fallback lands on the
very path the prescribed file names.

Two things follow, and the tests are built on both. A machine without the shell
still gets every other setting of this file, because `source-file` carries on
past the line it refused. And the reload binding returns 1 on such a machine, so
the `&&` in it never reaches `display-message`: the configuration is reloaded
and no message is shown.

This is also the one assertion of this bundle that a machine can pass by
accident. The fallback lands on `/usr/bin/zsh` on the machine this bundle was
written on, by way of the passwd entry, which is the very path the file names.
A test that only read the option back proved nothing at all: it passed with the
line deleted from the file. `tests/shell.bats` starts that server with
`SHELL=/bin/sh`, which the prescribed file never names and which `checkshell()`
accepts, so the fallback is `/bin/sh` and the value read back can only have come
from the file. The helper that reads the path out of the prescribed file returns
non-zero on an empty result, so a deleted line fails that test rather than
skipping it.

## The colours

The prompt takes its colours from the starship palette, which the renderer
writes from the palette of the theme. Every name of the palette reaches it:

| Palette name  | Where the prompt draws it                                  |
| ------------- | ----------------------------------------------------------- |
| `accent`      | The directory, the Node version, and the Go version.        |
| `accent_alt`  | The Python version, and the Docker context.                 |
| `error`       | The git branch, the root user name, the job marker, and the error character. |
| `success`     | The git status, and the prompt character.                   |
| `warn`        | The user name, the package version, and the command duration. |
| `text`        | The word `on` before a branch, and the corner of the second line. |
| `bg`, `surface`, `surface_alt`, `text_muted` | Declared in the palette and named by no module today. A palette that declared only what it draws would break every time a module was added. |

Every row above was read back out of `starship explain`, in a directory holding
a `Cargo.toml` and a `package.json`, against the rendered file of a theme. The
table was wrong before that: it credited `warn` with the Rust version and
`success` with the Bun version, and neither one ever drew. "Four sections that
drew nothing" below records why.

### Four sections that drew nothing

starship renders a module only when the `format` string names it. The format
string of this bundle names fourteen, and the file carried four more sections
that it did not name: `[rust]`, `[ruby]`, `[haskell]` and `[bun]`. Each one set
a colour and a symbol that starship never reached. `starship explain` in a
directory holding both a `Cargo.toml` and a `package.json` listed the Node
version and the package version and neither of those two.

The four sections are gone rather than added to the format string. Adding them
would change what the prompt draws, and **this bundle makes no styling
decision**: what it renders is what the dotfiles rendered, to the byte. Deleting
four sections that render nothing changes no prompt at all, and it is the only
one of the two options that can be taken without deciding that this desktop
should show a Rust version. A later issue that wants those modules adds them to
the format string and to the table above in one change.

Two modules draw in a colour of the terminal rather than of the starship
palette, and both are already theme colours: `[time]` takes the default yellow
of starship, and the terminal draws colour slot 3, which
[the Ghostty bundle](ghostty.md) writes from `WARN`. Slot 8 is `TEXT_MUTED` for
the same reason, and that is the slot `zsh-autosuggestions` draws its suggestion
in.

**The prescribed zshrc sets no colour at all.** `ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE`
is left at the default of the plugin, which is `fg=8`. The Ghostty bundle moved
slot 8 from the surface colour to `TEXT_MUTED`, taking its contrast on the
background from 1.10:1 to 8.10:1, and it names this plugin as the reason. A
truecolor value written here would be right in this terminal and would ignore
the palette of every other one.

### The prescribed zshrc does not source `generated/shell/colors.sh`

`templates/shell/colors.sh` is older than this bundle. It renders the palette of
the theme as ten `XGHOST_*` shell variables, for a shell script to source.

No prescribed setting of this bundle reads one of them. The prompt takes its
colours from its own generated file, and the suggestion colour is a slot of the
terminal palette rather than a value written here, so a `source` of that file
would put ten variables into every shell and nothing would read them. The line
is left out for that reason and for no other.

## tmux keeps its own status line

tmux draws a green status line, and this bundle leaves it there. The tmux
configuration of the dotfiles set no colour of any kind, so there is nothing to
port, and a status line drawn from the palette is a design this issue does not
carry. It is the decision `config/hypr/hyprlock.conf` already carries for its
own colours, for a different reason: an application that this project has not
styled keeps its own styling until an issue owns the styling.

What that costs is visible: a tmux session on a themed desktop has a status line
in a colour no theme declares. Putting it right is one template and one
`source-file` line, and the reload binding above proves the path form that line
would need.

## `KNOB_FONT` reaches neither zsh nor tmux

Neither program has a font. zsh draws in the font of the terminal, tmux draws in
the font of the terminal, and [the Ghostty bundle](ghostty.md) takes that font
from `KNOB_FONT` already. A font setting in either file would be a setting
neither program has.

The knob does reach this bundle indirectly, and it has to: every symbol of the
prompt is a glyph of the Nerd Font private use area, so a machine without one of
the two families the knob offers draws a row of empty boxes where the git branch
and the directory icons are. Both families are in the manifest for that reason,
and [Knobs](../knobs.md) names the package of each.

## The packages this bundle needs

| Package                   | Repository | What needs it                                                    |
| ------------------------- | ---------- | ------------------------------------------------------------------ |
| `zsh`                     | `extra`    | The shell itself, and the `default-shell` of the tmux configuration. |
| `starship`                | `extra`    | The prompt.                                                        |
| `tmux`                    | `extra`    | The multiplexer.                                                   |
| `zsh-syntax-highlighting` | `extra`    | The highlighter the prescribed zshrc sources.                      |
| `zsh-autosuggestions`     | `extra`    | The suggestions the prescribed zshrc sources.                      |
| `ttf-jetbrains-mono-nerd` | `extra`    | Every glyph of the prompt, and the default of `KNOB_FONT`. [The Ghostty bundle](ghostty.md) names it as well. |

Every package above is declared in `install/packages/base.txt`, and
`tests/install.bats` fails when a package this table lists is in no manifest.
[Installing](../installing.md) records the manifest.

Neither plugin is sourced behind a guard. Both files come from packages the
manifest declares, so a machine that has this configuration has both, and a
guard would turn a broken installation into a shell that quietly lost its
highlighting.

This bundle installs no login shell of anybody. `zsh` is installed and the
tmux configuration opens it, and nothing here runs `chsh`. A user whose login
shell is `bash` gets a themed tmux and a themed terminal, and the prompt of this
bundle in every tmux pane.

## What the tests prove

- `tests/shell.bats` proves the bundle. It links the prescribed configuration
  and follows it back, expands the `STARSHIP_CONFIG` line the way a shell
  expands it and follows it to the file the renderer wrote, and does that again
  with both XDG directories moved and with `XDG_CONFIG_HOME` unset. It starts a
  real zsh against the prescribed file, inside a temporary home directory, and
  reads `starship prompt` back out of it: the prompt carries the accent colour of
  the theme as a truecolor escape, and the same shell started before the render
  prints the report above instead. It proves that the shell writes no file into
  the checkout, which is what the two paths in "What the shell writes" are for.
  It reads every setting and every key binding back out of a running tmux server
  on a private socket, and runs the reload binding with `XDG_CONFIG_HOME` moved.
  The tmux tests are split by what a machine has to carry for the assertion to
  mean anything: the settings, the key bindings and the reload hold on any
  machine with tmux, and the two that need the shell of this desktop to be
  installed skip when it is not. Neither key assertion reads a column of
  `list-keys` output, because that width is computed from the other keys in the
  table and from the version of tmux; the keys are compared as whole fields, and
  the two splits are read back as the set of prefix keys bound to a split, so a
  `%` or a `"` the file stopped unbinding is a third member of that set. It runs
  the install step in all seven of its cases, including a home directory that
  does not take the write, a `~/.zshenv` that is a directory, a dangling
  `~/.zshrc` symbolic link, and each of the four startup files `ZDOTDIR` moves.
  It plants a symbolic link at the path the temporary file used to be written
  to and proves that the file it points at is untouched. It reads
  `STARSHIP_CONFIG` back out of a `zsh -c`, a `zsh -l -c` and an interactive
  zsh, and compares the two copies of that line byte for byte. It runs
  `xghost config unlink` and reads `~/.zshenv` out of its report. It holds the
  list of everything the dotfiles keep, so a line that came back would fail
  there.
- `tests/golden.bats` compares the rendered starship configuration of every
  theme with the committed output under
  `tests/golden/<knob set>/<theme>/starship/starship.toml`. No knob reaches this
  bundle, so the two knob sets hold the same file, and the palette of each theme
  is what differs.
- `tests/install.bats` reads the package table of **every** bundle page and
  fails when a package one of them lists is declared by no manifest. That is the
  cross-check for the table above, and it is derived: a package added to the
  table is read by it without the test changing. `tests/shell.bats` reads the
  same table and asserts the same thing for this page alone, so a page whose
  table stopped being readable fails in the suite of its own bundle as well.

- `tests/negative-control` is the other direction, and it is a script rather
  than a suite. It copies the checkout, breaks one source on purpose, and
  requires the test aimed at that break to fail and to be named in the report.
  Every test of this bundle that was added or changed for this bundle has a
  control there. It exists because four tests of this bundle shipped unable to
  fail: one compared a variable with itself, one was true whatever the
  prescribed file said, and two skipped rather than failed when the line they
  read was deleted. A green suite does not tell those apart from the tests that
  work, and this script does. It is run by hand; continuous integration runs
  `bats tests`.

Every test that needs zsh, tmux or starship skips when the program is absent,
because continuous integration has none of the three. Every tmux command names a
private socket inside the temporary directory of the test, and kills the server
on that socket when the test ends. A bare `tmux` command would reach the default
socket, which on a developer machine holds the sessions of whoever is running
the tests.

## What this bundle has never been observed doing

- **No installation has run this step.** `install/steps/config/40-shell.sh` was
  driven directly, in a temporary home directory, in all seven of its cases. No
  `./install.sh` has written a `~/.zshenv` on a real machine.
- **No login shell has read the file.** The zsh the tests start is an
  interactive zsh with `ZDOTDIR` and `HOME` inside a temporary directory. It is
  the same file by the same path, and it is not a login of a user at a display
  manager.
- **tmux has never been used, only started.** The tests read the settings and
  the bindings out of a server. No key has been pressed, and no pane has been
  split by a person.
- **tmux 3.4 has never run this file.** Everything above was read from tmux 3.7
  on Arch, and from tmux on the `ubuntu-24.04` runner of continuous integration,
  which is where the version difference in `list-keys` was found. No other
  version has been tried.
- **The prompt has never been seen.** `starship prompt` was read as text, and
  the colours in it were compared with the palette. Whether the glyphs of the
  Nerd Font draw is not something a string comparison answers.
- **No `~/.config/starship.toml` has been deleted by anybody following this
  page.** The leftover file was read on one machine to confirm that the silent
  fallback had something to land on. Nothing of this project writes that path,
  reads it, or removes it.
