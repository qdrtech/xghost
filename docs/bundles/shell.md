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
install.sh             ~/.zshenv                          holds one ZDOTDIR line
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

**This bundle names the bridge all the same.** The prescribed zshrc holds:

```sh
export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/xghost-generated/starship/starship.toml"
```

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

## zsh has one entry point, and it is not in the config directory

zsh reads `~/.zshrc`. It reads `$ZDOTDIR/.zshrc` instead when `ZDOTDIR` is set,
and `ZDOTDIR` can be set in one place: `~/.zshenv`, which zsh reads before
anything else.

That file is in the home directory rather than in the config directory, so
[the linker](../linking.md) cannot reach it: it links the top level entries of
`config/` into `$XDG_CONFIG_HOME` and creates the bridge, and it writes nothing
anywhere else. `install/steps/config/40-shell.sh` is what puts the line there:

```sh
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
```

The step **creates** `~/.zshenv` and never edits one. It follows
`install/steps/post-install/10-command-path.sh`, which creates one path under
the home directory when nothing is there, names what it found when something
is, and is removed by neither `xghost config unlink` nor anything else, because
no prescribed entry stands behind it.

Five cases, and four of them change nothing:

| What the step finds                        | What it does                                                   |
| ------------------------------------------ | -------------------------------------------------------------- |
| Neither `~/.zshenv` nor `~/.zshrc`         | Writes `~/.zshenv` with the line above, and says so.           |
| A `~/.zshenv` that already holds the line  | Nothing. This is the second run of an installation.            |
| A `~/.zshenv` that sets `ZDOTDIR` itself   | Nothing. That path is a choice the user made.                  |
| A `~/.zshenv` that sets something else     | Nothing. It prints the line and where to put it.               |
| No `~/.zshenv` and a `~/.zshrc`            | Nothing. See below.                                            |

The last case is the one worth the paragraph. `ZDOTDIR` moves the file zsh
reads, so a `~/.zshrc` that is already there stops being read: every alias and
every export in it goes, at the next login, with no message anywhere. The step
refuses that. It names both files, states that the two cannot both be the file
zsh reads, and prints the line for the reader to add once they have moved what
they want to keep.

None of the five cases fails the installation. The rest of the desktop is in
place either way, and zsh is a login shell rather than a part of the session.

**To undo it: remove `~/.zshenv`.** zsh then reads `~/.zshrc` again, and nothing
of this bundle is left in the home directory.

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

## What the dotfiles keep

This is criterion 3 of [issue #15](https://github.com/qdrtech/xghost/issues/15),
and it is a filter rather than a migration. Every line below stayed in
`qdrtech/dotfiles`. A line that could be read either way stayed there too:
shipping the working configuration of one person in a public product is worse
than a bundle that is thin.

| Line of `zshrc/.zshrc`                                  | Why it stayed                                                                |
| -------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `alias dle='sh ~/.config/scripts/docker-login-ecr.sh'`   | The work-specific line the issue names. The script runs `aws sts get-caller-identity` and logs Docker into an ECR registry in `us-east-1`. It is the configuration of an employer. |
| `alias gitprune='sh ~/.config/scripts/git-prune.sh'`     | Names a script in the dotfiles that this project does not ship, and this project ships no scripts directory. |
| `sh ~/.config/scripts/term-startup.sh`                   | Runs `figlet qdrtech` and `fastfetch`. The word it prints is the name of the maintainer, and this project installs neither program. |
| `export PATH=$PATH:$HOME/.config/scripts`                | The scripts directory of the maintainer.                                      |
| `alias ts='bash "${DOTFILES_DIR:-$HOME/dotfiles}/scripts/theme-switch.sh"'` | Replaced by `xghost theme set`, which is criterion 4. The path it named is a checkout of the dotfiles. |
| `export EDITOR="nvim"` and `export SUDO_EDITOR="$EDITOR"` | This desktop installs no editor, so the line names a program that need not be on the machine. Which editor to ship is a decision this bundle does not carry. |
| `export FZF_DEFAULT_COMMAND='fd'`                        | Neither `fzf` nor `fd` is installed by this project.                          |
| The `bun` completions, `BUN_INSTALL` and its `PATH` line  | A runtime the user installed by hand into `$HOME/.bun`.                       |
| `NVM_DIR` and the two files it sources                   | The same, for `nvm`.                                                          |
| The `pnpm` block                                         | The same, for `pnpm`.                                                         |
| `FLYCTL_INSTALL` and its `PATH` line                     | A `fly.io` account of the maintainer.                                         |
| `export PATH="$HOME/.opencode/bin:$PATH"`                | A tool the user installed by hand.                                            |
| The `wal` sequence block, and the `sed` in it            | Reads the colour cache of pywal. This project renders its colours instead, and [the Waybar bundle](waybar.md) dropped the pywal colour picker for the same reason. |
| `PS1='%n@%m %~$'`                                        | starship replaces the prompt two lines later, so the line already did nothing. |
| `zstyle :compinstall filename "$HOME/.zshrc"`            | A marker `compinstall` writes about its own bookkeeping, naming a file this bundle does not use. |
| `HISTFILE=~/.histfile`                                   | The setting is kept and the path is not. See "What the shell writes, and where" above. |
| `alias ls="ls -G"`                                       | `-G` is the colour flag of the BSD `ls` of macOS. GNU `ls -G` drops the group column instead, so the line changed the output and undid the `--color=auto` alias above it. |
| `alias ..` through `alias .........`                     | Eight levels of parent directory. It is a navigation habit of one person, and there is no depth this project could defend as the right one. |

| Line of `tmux/.tmux.conf`                                | Why it stayed                                                                |
| -------------------------------------------------------- | ----------------------------------------------------------------------------- |
| The four `tpm` lines: the plugin manager, `tmux-resurrect`, `tmux-continuum`, and `@continuum-restore` | `tpm` is a repository the user clones into `~/.tmux/plugins/tpm` by hand. This project installs no package for it and clones no repository, so `run -b ~/.tmux/plugins/tpm/tpm` would name a path that is not there at every server start. Shipping it would also mean running code fetched from GitHub at the start of every session, which no other bundle of this project does. |

Two lines of the dotfiles reached this bundle changed rather than dropped, and
both are in "What changed from the dotfiles" below.

## What changed from the dotfiles

| Change                                                    | Why                                                                        |
| ---------------------------------------------------------- | --------------------------------------------------------------------------- |
| `~/.local/bin` is put on the `PATH`, with a guard          | `xghost theme set` replaces the `ts` alias, and it runs by name only from a directory on the `PATH`. `install/steps/post-install/10-command-path.sh` links the command into `~/.local/bin`, and Arch puts that directory on the `PATH` of no login shell. The guard is what keeps a second read of the file from naming the directory twice. |
| `bind r source-file ~/.tmux.conf` is a `run-shell`         | See "The reload binding" below.                                             |
| `bind -n m-j` is `bind -n M-j`                             | tmux accepts the lower case form and binds `M-j`, which was read back from a running server, so the key worked. The line is written like its three neighbours so that a reader is not left wondering. |
| The starship `[aws]` module and `$aws` in the format string | The prompt showed an AWS profile and the duration of its credentials. The issue names the AWS content of these dotfiles as the thing that stays behind, and a module that draws an employer's profile name into a prompt is on that side of the line. |
| The empty starship `[git_state]` section                    | It set nothing. A section that declares no key states an intent that the file does not carry. |
| The starship palette is named `xghost` rather than `theme`  | One name for the palette of this project, in the one file that declares it.  |

Everything else is carried over unchanged, the emoji of `[package]` and `[bun]`
included: changing a symbol is a styling decision, and this bundle makes none.

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

## The colours

The prompt takes its colours from the starship palette, which the renderer
writes from the palette of the theme. Every name of the palette reaches it:

| Palette name  | Where the prompt draws it                                  |
| ------------- | ----------------------------------------------------------- |
| `accent`      | The directory, and the Node version.                        |
| `accent_alt`  | The Python version, and the Docker context.                 |
| `error`       | The git branch, the root user name, the job marker, and the error character. |
| `success`     | The git status, the Bun version, and the prompt character.  |
| `warn`        | The user name, the Rust version, the package version, and the command duration. |
| `text`        | The word `on` before a branch, and the corner of the second line. |
| `bg`, `surface`, `surface_alt`, `text_muted` | Declared in the palette and named by no module today. A palette that declared only what it draws would break every time a module was added. |

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
  It reads every setting and every key binding back out of a running tmux server,
  and runs the reload binding with `XDG_CONFIG_HOME` moved. It runs the install
  step in all of its cases, including the one where a `~/.zshrc` is already
  there. It holds the list of everything the dotfiles keep, so a line that came
  back would fail there.
- `tests/golden.bats` compares the rendered starship configuration of every
  theme with the committed output under
  `tests/golden/<knob set>/<theme>/starship/starship.toml`. No knob reaches this
  bundle, so the two knob sets hold the same file, and the palette of each theme
  is what differs.
- `tests/install.bats` reads the package table above and fails when a package it
  lists is declared by no manifest.

Every test that needs zsh, tmux or starship skips when the program is absent,
because continuous integration has none of the three. Every tmux command names a
private socket inside the temporary directory of the test, and kills the server
on that socket when the test ends. A bare `tmux` command would reach the default
socket, which on a developer machine holds the sessions of whoever is running
the tests.

## What this bundle has never been observed doing

- **No installation has run this step.** `install/steps/config/40-shell.sh` was
  driven directly, in a temporary home directory, in all five of its cases. No
  `./install.sh` has written a `~/.zshenv` on a real machine.
- **No login shell has read the file.** The zsh the tests start is an
  interactive zsh with `ZDOTDIR` and `HOME` inside a temporary directory. It is
  the same file by the same path, and it is not a login of a user at a display
  manager.
- **tmux has never been used, only started.** The tests read the settings and
  the bindings out of a server. No key has been pressed, and no pane has been
  split by a person.
- **The prompt has never been seen.** `starship prompt` was read as text, and
  the colours in it were compared with the palette. Whether the glyphs of the
  Nerd Font draw is not something a string comparison answers.
