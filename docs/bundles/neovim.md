# The Neovim bundle

The editor, and the first bundle whose configuration is a programming language.

It arrived differently from every other bundle as well. The rest were written
for this project. This one was a repository of its own, `qdrtech/xghost-config`,
kept as a submodule of the maintainer's dotfiles and reachable over SSH alone,
so a clean clone of the dotfiles by anybody else came back without it.
[Issue #16](https://github.com/qdrtech/xghost/issues/16) is that bug. The
configuration is now a plain directory of this repository, imported with
`git subtree add` and with its 73 commits, and nothing about it needs an SSH key
any more.

```
config/nvim/                    the prescribed configuration, imported whole
config/nvim/init.lua            the entry point, with one line added
config/nvim/lua/config/xghost.lua   the theme bridge, written for this project
templates/nvim/colors.lua       the template that writes the palette
```

## How the files meet

`xghost config link` links `config/nvim` to `~/.config/nvim`, exactly as it
links every other prescribed entry. The Neovim bundle needed nothing new from
the linker.

`xghost theme set <name>` renders `templates/nvim/colors.lua` to
`<generated>/nvim/colors.lua`. The prescribed Lua reads that file at startup and
applies its colours to the highlight groups it names.

The configuration itself is a LazyVim configuration. It loads a plugin manager,
which loads a colourscheme, which paints the editor. This bundle paints over the
part of it that the desktop theme should decide.

## The import

The configuration was imported from the local checkout of the submodule rather
than from the SSH remote, so the import needed no network and no credentials and
produced the same history:

```
git subtree add --prefix=config/nvim \
  /home/…/dotfiles/nvim/.config/nvim 9d693d8368bcd0b861dfafce3a1ed02a6de9a887
```

The tree the import wrote is byte for byte the tree of that commit.

**The history was kept rather than squashed.** `--squash` would have replaced 73
commits with one, which is what
[acceptance criterion 2](https://github.com/qdrtech/xghost/issues/16) asks this
project not to do. The cost was measured rather than guessed, by cloning both
results:

| A fresh clone of | Size of the pack | Objects | Commits |
| ---------------- | ---------------- | ------- | ------- |
| `main`, before the import | 518.34 KiB | 622 | 20 |
| the import with `--squash` | 533.69 KiB | 650 | 22 |
| the import with its history | 602.46 KiB | 1005 | 94 |

The history costs 68.77 KiB more than the squash, on a repository that already
carries half a megabyte. It buys the 73 commits that would otherwise survive
only inside a private repository nobody else can read.

One consequence is worth writing down. `git subtree add` merges the source
history unchanged, and every one of those commits records the files at their old
paths, at the root of the source repository rather than under `config/nvim`. So
a path-scoped log finds one commit:

```
git log --oneline -- config/nvim          # one commit: the import itself
git log --oneline $(git rev-list --max-count=1 --grep="Add 'config/nvim/'" HEAD)^2
                                          # the 73 commits of the import
```

## The rule of this bundle: the include cannot use '..'

Every other bundle of this project reaches the generated output with a path
relative to the prescribed file:

```
?../xghost-generated/<app>/<file>
```

**That form does not work here**, and the reason is the same one that makes Rofi
the exception in
[ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md). `xghost config
link` makes `~/.config/nvim` a symbolic link into the checkout. A `..` in a path
is applied by the kernel *after* it has followed every link before it, so
`~/.config/nvim/..` is not `~/.config`. It is the `config` directory of the
checkout, and the bridge is not there.

Measured, with the bundle linked and a theme rendered:

```
vim.fn.stdpath("config")                     ~/.config/nvim
vim.uv.fs_realpath(that)                     <install location>/config/nvim
stdpath("config") .. "/../xghost-generated/nvim/colors.lua"    not readable
fnamemodify(stdpath("config"), ":h") .. "/xghost-generated/nvim/colors.lua"
                                                               readable
```

Lua is what gets this bundle out of the trap Rofi could not escape. Rofi has to
write a path and let Rofi resolve it. Lua can take the parent directory **as
text**, which is what `fnamemodify(…, ":h")` does, and a path with no `..` in it
has nothing for the kernel to apply physically. So:

```lua
local parent = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h")
return parent .. "/" .. "xghost-generated/nvim/colors.lua"
```

`stdpath("config")` is the config directory **as it was opened**, which is
`$XDG_CONFIG_HOME/nvim` and not the checkout. Its parent is therefore
`$XDG_CONFIG_HOME`, which is where the linker puts the bridge, and the bridge
points at `$XDG_STATE_HOME/xghost/generated`. Both ends follow the environment,
which is the whole point of ADR 0002, and this bundle keeps that property
without giving up `XDG_CONFIG_HOME` the way the Rofi bundle had to.

## What happens when the generated file is not there

A user who has installed the desktop and has not yet run `xghost theme set` has
no `<generated>/nvim/colors.lua`. In every other bundle that moment is an
include that misses, and the worst it costs is an unthemed application. Here it
can cost the whole editor, because Lua raises.

Measured on Neovim 0.12.4, with the generated palette removed and the rest of
the bundle in place. Each fixture sets a variable, loads the palette, and sets a
second variable, and the report says whether the second one was ever set:

| The prescribed Lua uses | The rest of `init.lua` | What is reported | Exit code |
| ----------------------- | ---------------------- | ---------------- | --------- |
| `dofile(path)`          | **never runs**         | `E5113`, on standard error | 0 |
| `require("colors")`, with `package.path` set | **never runs** | `E5113`, on standard error | 0 |
| `loadfile(path)`, which is what this bundle ships | runs | one warning that names the file and the command to run | 0 |

`dofile` and `require` both raise, and an error raised in `init.lua` stops
`init.lua`: every line after it is skipped. The editor then comes up with no
options, no keybindings and no plugins, because of a colour file. `loadfile`
returns `nil` and a message instead, so the missing palette is a value the
bundle can report rather than an exception that unwinds the startup.

`pcall` around `dofile` would also keep the editor alive, and it is the wrong
tool for a different reason: it swallows every error the file could raise,
including the ones worth reading. `loadfile` separates the two. A file that is
not there is `nil` and a message; a file that is there and is broken is a chunk
that fails when it is called, which the bundle catches separately and reports by
name.

Note the exit code in every row. **A run with a broken startup exits 0.** This
is the rule ADR 0002 states for every bundle: assert on the state the
application holds after it has read every file, never on the code it exited
with. `tests/nvim.bats` reads highlight groups back out of the running editor
with `nvim_get_hl`.

### The report goes through `nvim_echo`, not through `vim.notify`

The first draft of this bundle reported the missing palette with `vim.notify`,
which is the idiomatic call. Measured against the real configuration, the
warning reached **neither the message history nor standard error**. It was
swallowed.

`vim.notify` is a variable, and a plugin may replace it. `snacks.nvim`, which
LazyVim loads, replaces it at `lua/snacks/init.lua:220` — before `init.lua`
reaches the line that loads this bundle — and its stand-in dropped the message.
The measurement:

```
vim.notify at the point init.lua calls setup():
  defined at …/lazy/snacks.nvim/lua/snacks/init.lua:220
```

`vim.api.nvim_echo` is an API function rather than a variable, so nothing can
stand in front of it, and its second argument puts the line in `:messages` for a
user who was not looking when it was printed. Measured with the real
configuration and the palette absent, the warning now reaches both the message
history and standard error, and the rest of `init.lua` still runs.

The call is scheduled rather than immediate, so the line is printed once the
editor is up. A long message printed in the middle of startup asks the user to
press ENTER before the first buffer appears.

## The colourscheme, and the honest limit of this bundle

**Loading a colourscheme clears every highlight group.** A palette applied once,
at the point `init.lua` runs, is a palette that the next `:colorscheme` wipes.
So this bundle applies its highlights from a `ColorScheme` autocommand as well
as immediately, and the palette of the active theme is therefore applied last
whichever colourscheme is in use.

Proved by reading `nvim_get_hl(0, { name = "Normal" })` back out of the running
editor, with `tokyonight` active:

```
after a colourscheme, before this bundle   fg=#C7C7C7 bg=#1C1C1C   (habamax)
after this bundle                          fg=#C0CAF5 bg=#1A1B26   (the theme)
after a second colourscheme                fg=#C0CAF5 bg=#1A1B26   (the theme)
```

And end to end, with the real configuration and its real plugins, in a sandbox:

```
theme tokyonight   colors_name=xghost   Normal fg=#C0CAF5 bg=#1A1B26
theme macos-dark   colors_name=xghost   Normal fg=#E8E8ED bg=#0F1115
```

### What this bundle does not colour

Now the honest part, which a reader should have before they run
`xghost theme set` and look at an editor.

**This bundle themes the chrome of the editor, not its syntax.** The list of
highlight groups in `config/nvim/lua/config/xghost.lua` is the whole of what the
active theme reaches: the background, the floats, the line numbers, the popup
menu, the status line, the tab line, the search, the diagnostics, the diff
colours, and comments. Everything else — every language construct, every
Treesitter capture, every plugin that paints its own window — keeps the colour
the colourscheme gave it.

The configuration pins five colourscheme plugins in `lua/config/lazy.lua`:
`catppuccin`, `tokyonight.nvim`, `gruvbox.nvim`, `onedark.nvim` and
`qdrtech/xghost.nvim`. Measured, the one that ends up active is `xghost.nvim`;
`vim.g.colors_name` reads `xghost` after a real start. None of the five draws
from `themes/<name>/palette.conf`, so **the editor after a theme switch is a
hybrid**: xghost chrome over the syntax colours of a plugin.

For the `tokyonight` theme that hybrid is nearly seamless, because
`themes/tokyonight/palette.conf` was ported from the same Tokyo Night colours
the plugin uses. For `macos-dark` it is visibly a hybrid: the background and the
chrome go macOS dark, and the syntax stays where `xghost.nvim` put it.

Two ways out of that exist and neither is in this bundle:

- **Generate a whole colourscheme.** Several hundred highlight groups rendered
  from ten palette names. It would replace `xghost.nvim` rather than sit over
  it, and it is a bundle of its own rather than a slice of this one.
- **Choose the colourscheme from the theme.** A structural choice keyed on a new
  palette name would map the theme `tokyonight` to the plugin `tokyonight` and
  the theme `macos-dark` to `xghost`. That gives a coherent editor, but the
  colours would then come from the plugin rather than from the palette, which is
  not what
  [acceptance criterion 5](https://github.com/qdrtech/xghost/issues/16) asks
  for.

A half-themed editor recorded here is better than a half-themed editor nobody
wrote down.

## The generated file is Lua, and what follows from that

Every other bundle generates data that its application parses: CSS, JSON, an
`ini`-like config, a `rasi` theme. This one generates a Lua module, and the
editor **executes** it.

The generated file therefore holds a table literal and nothing else. It calls
nothing, it requires nothing, and it reads no state of the editor, so loading it
can only produce that table. The bundle checks what it got: a return value that
is not a table is reported by name, and a value that is not `#rrggbb` is
reported by name and nothing at all is applied. A group with half a definition
would look worse than the one the colourscheme gave it.

One property is shared with the shell bundle and is worth naming. The renderer
substitutes a palette value into a template as text and escapes nothing, so a
palette value that carried a quotation mark would end up inside the Lua string
literal of the generated file, exactly as it would end up inside the single
quotes of `templates/shell/colors.sh`, which a shell sources. Both shipped
themes are project-owned and neither does this. A theme is a directory a user
may add, so this is a property of the renderer rather than of this bundle, and
it is recorded here rather than worked around here.

## No knob reaches this bundle

The project has four knobs, and none of them is a setting of the editor.
`KNOB_ANIMATIONS` and `KNOB_GAP_SIZE` are the compositor. `KNOB_BAR_POSITION` is
the bar. `KNOB_FONT` is the family the terminal draws with, and Neovim in a
terminal draws no glyphs of its own: `guifont` is read by a graphical client and
this desktop ships none.

So this bundle has one template rather than the `colors` and `knobs` pair every
other bundle has. `tests/nvim.bats` renders at both knob sets and asserts that
the Neovim palette is the same file in each, with a check that the second knob
set really did reach the rest of the output.

## The packages this bundle needs

| Package   | Repository | What needs it                                            |
| --------- | ---------- | -------------------------------------------------------- |
| `neovim`  | `extra`    | The editor itself.                                       |
| `ripgrep` | `extra`    | The Telescope live grep of `lua/config/keybindings.lua`. Without it `<leader>fg` opens a window that finds nothing and says nothing. |

Both are declared in `install/packages/base.txt`, and `tests/install.bats`
fails when a package this table lists is in no manifest.

`git` is not declared here. `boot.sh` installs it before this repository exists
on the machine, and `lua/config/lazy.lua` clones the plugin manager with it.

The plugins are not packages and no manifest names them. `lazy.nvim` bootstraps
itself on first start and installs what `lazy-lock.json` pins, from GitHub, over
HTTPS. `qdrtech/xghost.nvim` is a public repository, so that first start needs
no SSH key either.

## What changed from the source repository

| What | Why |
| ---- | ---- |
| One line added to `init.lua`: `require("config.xghost").setup()` | The entry point of this bundle. It sits after the plugin manager, so a reader meets the colours after the things that paint them. |
| `lua/config/xghost.lua` added | The theme bridge. It is the only file of `config/nvim` this project wrote. |
| `README.md` removed | It documented a standalone repository, and its installation section told the reader to `git clone git@github.com:qdrtech/xghost-config.git ~/.config/nvim` — the private SSH remote that [acceptance criterion 3](https://github.com/qdrtech/xghost/issues/16) exists to remove. The configuration is now placed by `xghost config link`, and this page replaces it. What was worth keeping is in "The key mappings" below. |

Nothing else was touched. The plugin specs, the options, the keybindings and
`lazy-lock.json` are the files of commit `9d693d8`.

### The key mappings

From `lua/config/keybindings.lua`, and carried over from the README that was
removed:

| Keys                          | What they do                                      |
| ----------------------------- | ------------------------------------------------- |
| `<leader>ff` `<leader>fg` `<leader>fb` `<leader>ft` | Telescope files, live grep, buffers, help tags. |
| `<leader>e` / `<leader>E`     | Snacks Explorer, at the project root or the working directory. |
| `jj` in insert mode           | Leave insert mode.                                |

The leader is the space bar.

## What the tests prove

`tests/nvim.bats` holds 32 tests. No test starts the real `init.lua`: that file
loads LazyVim, which clones plugins from the network on first start and writes a
data directory of hundreds of megabytes. Every test that runs Neovim runs it
with `-u` against a fixture it wrote, and Neovim still puts the linked config
directory on its `runtimepath`, so the fixture reaches the prescribed Lua by the
same `require` the real `init.lua` uses.

| What                                              | How                                              |
| ------------------------------------------------- | ------------------------------------------------ |
| The configuration is a directory, not a submodule | No `.gitmodules`, and no tree entry of mode `160000` anywhere. |
| The history is here                               | The commit the import was taken from is an ancestor of `HEAD`. Skipped in a shallow checkout. |
| No file of the bundle names the private repository | A grep of `config/nvim` for `xghost-config` and for `git@github.com`. |
| `xghost config link` places it                    | The link is created, points at the prescribed directory, and `unlink` removes it. |
| The path reaches the bridge                       | Read out of a running editor, and compared with the path the linker created. |
| A `..` would not reach the bridge                 | The same run resolves both forms and reports which one is readable. |
| The palette follows the theme                     | Every palette name of every theme, asserted as a whole assignment line rather than as a value somewhere in the file. |
| A missing palette does not stop `init.lua`        | A fixture writes a file after the load, and that file exists. |
| A missing palette is reported                     | On standard error, and in `:messages`. |
| `dofile` and `require` would stop `init.lua`      | The same fixture, with those two calls, writes no file. |
| A colourscheme loaded afterwards does not win     | `nvim_get_hl` for `Normal`, after a second `:colorscheme`. |
| No knob reaches the bundle                        | Two renders at two knob sets, with a check that the knob set reached the rest of the output. |

`tests/negative-control` holds 20 mutations aimed at those tests, including the
one that puts the relative include of every other bundle back, the one that
swaps `loadfile` for `dofile`, the one that applies the palette once instead of
on `ColorScheme`, and the one that sends the report back through `vim.notify`.
Two of the 20 are the weaker kind that mutate an assertion, because they record
what Lua and the kernel do rather than what this project wrote.

### The tests that can skip, and why

| Test | When it skips |
| ---- | ------------- |
| Every test that runs the editor | `nvim` is not on `PATH`. |
| `the history of the imported configuration is in this repository` | The checkout is shallow, so no commit older than `HEAD` is present. |

Neither skips in continuous integration. The workflow installs Neovim and sets
`XGHOST_REQUIRE_NVIM`, which turns the first skip into a failure, and it checks
out with `fetch-depth: 0`, which removes the second. No test enforces that this
list stays complete; `tests/supporting.bats` has such a check for its own suite
and this suite does not.

## What this bundle has never been observed doing

- **Starting the real `init.lua` in the test suite.** Every measurement of the
  editor in `tests/nvim.bats` runs a fixture. The real entry point was started
  by hand, once, in a sandbox with the plugin tree copied into it, and the two
  `colors_name` and `Normal` readings above are from that run. Nothing in
  continuous integration repeats it.
- **Running against a Neovim older than 0.12.4.** Every measurement on this page
  was taken on 0.12.4. The prescribed Lua uses no call newer than 0.9, which the
  source repository already named as its minimum, but that was read from the
  documentation rather than measured against an old build.
- **Being looked at.** No test opens a window. The tests read highlight groups
  out of a headless editor, which says what colour a group holds and says
  nothing about whether the result is pleasant.
