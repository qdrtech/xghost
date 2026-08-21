# 0002. The bridge to the generated output

- Status: accepted
- Date: 2026-08-14

## Context and problem statement

[ADR 0001](0001-prescribed-config-architecture.md) splits a running
installation into four categories of file. Two of those categories meet in
every bundle. A prescribed file holds all real configuration and is symlinked
into the user's config directory. Generated output is written by the renderer
to `$XDG_STATE_HOME/xghost/generated`, which [theming](../theming.md)
documents as the stable path that applications read.

The two categories live in two directories, and each directory follows its own
environment variable. A prescribed file has to include a generated file across
that gap.

The question this ADR answers: how does a prescribed file name a generated
file, so that the include is right for every value of `XDG_CONFIG_HOME` and
`XDG_STATE_HOME`, in every application the project prescribes?

The first answer was wrong, which is why this ADR exists. The Ghostty bundle
shipped `config-file = ?~/.local/state/xghost/generated/…`. Ghostty expands no
environment variable, so a user who moves `XDG_STATE_HOME` gets a renderer
writing to one path and a terminal reading another. The terminal then comes up
unthemed and reports nothing, because the `?` that lets a fresh installation
start also swallows the miss.

The review of that bundle checked every application in the remaining bundles
against its upstream source, on a real machine, with both `XDG_CONFIG_HOME` and
`XDG_STATE_HOME` set away from their defaults. The findings are recorded under
"Decision outcome" below. They belong on this page, because a bundle author
needs them before the bundle is written.

## Decision drivers

- The include has to be right for every value of `XDG_CONFIG_HOME` and
  `XDG_STATE_HOME`. The renderer follows both variables, so a path that assumes
  a default is wrong on the machine that moved it.
- Most of what the project prescribes expands no environment variable.
- Several applications report nothing when an include misses. A wrong path
  costs a debugging session rather than an error message.
- The include has to be optional. The generated output does not exist before
  the first `xghost theme set`, and an application that refuses to start on a
  fresh installation is a bad first impression.
- One construction has to serve every application. A separate form per
  application is a separate form per application to get wrong.
- The linker owns every link it creates. Any link this decision needs is
  therefore recorded, removed by `xghost config unlink`, and refuses to clobber
  a path the user put at that name.

## Considered options

1. **The direct path.** The prescribed file writes the state directory out in
   full: `?~/.local/state/xghost/generated/<app>/<file>`.
2. **The environment variable.** The prescribed file names the variable:
   `?$XDG_STATE_HOME/xghost/generated/<app>/<file>`.
3. **The relative include through a bridge symlink.** The prescribed file names
   a path relative to its own directory, and the linker places one link that
   reaches the generated output.

## Decision outcome

Chosen option: **the relative include through a bridge symlink**.

```
prescribed file:  ?../xghost-generated/<app>/<file>
linker places:    $XDG_CONFIG_HOME/xghost-generated -> $XDG_STATE_HOME/xghost/generated
```

Neither end of that path is written out in full. The directory the include
starts from moves with `XDG_CONFIG_HOME`, and the bridge moves with
`XDG_STATE_HOME`, so the include is right for every value of both. One relative
include and one link serve every application in the table below except one,
because GTK resolves an `@import` against the directory of the importing file,
which is the rule Ghostty already follows. The exception is Rofi, which resolves
such a path twice and by two rules that disagree; "Rofi tests one path and opens
another" below records the measurement and the form the Rofi bundle writes
instead.

`generated` under the state directory is itself a symbolic link, which
`xghost theme set` replaces in one step. The bridge points at that link rather
than at a build directory, so a theme switch changes no include.
[Linking](../linking.md) records the rest of the behaviour of the bridge: it is
created whether or not the generated output exists yet, and the `?` in front of
the path covers exactly that moment.

Option 1 is rejected because the path is right only while `XDG_STATE_HOME`
holds its default. The renderer follows the variable and the application does
not, so the two halves part company on any machine that moved it. The miss is
silent in three of the applications below. Neither GTK CSS route expands `~` at
all, so two bundles have no form of this option to write.

Option 2 is rejected because only Hyprland, the Waybar include array, and the
shell expand a variable. Ghostty, Rofi, and both GTK CSS routes read the text
as a literal path, so the include is never found.

### What each application does

Verified against upstream source and against the versions named, on a real
machine.

| Application    | Directive                | Expands `$VAR`?             | Expands `~`? | A target that is missing            |
| -------------- | ------------------------ | --------------------------- | ------------ | ----------------------------------- |
| Ghostty 1.3.1  | `config-file`            | no                          | yes          | **silent**                          |
| Hyprland 0.56.2| `source =`               | yes, as `$VAR`, not `${VAR}`| yes          | loud                                |
| Waybar 0.15.0  | `include` array          | yes, through `wordexp`      | yes          | loud: `spdlog::warn`, at the default log level |
| Waybar, GTK3   | CSS `@import`            | no                          | **no**       | fatal, Waybar exits 1               |
| Rofi 2.0.0     | `@import` and `@theme`   | no                          | yes          | **silent**; a missing `@theme` target leaves no theme at all, a missing `@import` merges nothing. A relative path is resolved twice; see below. |
| SwayNC 0.12.6  | `config.json`            | **no include mechanism**    | —            | an unknown key is dropped in silence |
| SwayNC, GTK4   | CSS `@import`            | no                          | **no**       | loud once: one `Gtk-WARNING` on standard error, and the daemon runs on |
| Neovim 0.12.4  | Lua: `loadfile`          | yes, whatever Lua is given  | yes, through `stdpath` | loud, and **fatal to the rest of `init.lua`** with `require` or `dofile`; see below |
| bash and zsh   | `source`                 | yes, and `${XDG_STATE_HOME:-…}` | yes      | loud                                |

The shell is the only entry that can express the XDG default inline. Every
other application needs the construction above.

### Ghostty prefers the real path

This is the resolution rule the whole construction rests on, so it is written
out.

The prescribed file is opened as `$XDG_CONFIG_HOME/ghostty/config`, and that
path is a symbolic link into the checkout. A relative `config-file` therefore
has two possible bases: the path as opened, and the real path.

**Ghostty tries both, and the real path wins.** When a file exists under both
bases, Ghostty reads the one under the real path. Only when the real path finds
nothing does Ghostty fall back to the path as opened, and the bridge lives
under the path as opened.

One rule follows for every bundle:

> **The checkout must never hold `config/xghost-generated`.** Such a directory
> sits under the real path, so Ghostty would read it in place of the bridge,
> and the terminal would carry the colours of the checkout rather than those of
> the active theme.

[The Ghostty bundle](../bundles/ghostty.md) records how the rule was verified.

### Rofi tests one path and opens another

This one is a correction. The row above was taken from the source and from the
behaviour of `~`, and it is right about both. What it did not cover is a
relative path resolved through a symbolic link, which is the shape every bundle
of this project writes, and Rofi is the one application in the table that gets
it wrong.

Rofi resolves a relative `@import` or `@theme` twice:

- It **tests the file for existence** on the raw joined path, `<directory of the
  including file>/<import>`. The kernel resolves that path, so `..` is applied
  physically, after following every symbolic link before it.
- It then **opens the path it canonicalises itself**, which applies `..`
  lexically, to the text of the path.

The two agree while nothing on the path is a symbolic link. `xghost config link`
makes the config directory of every bundle one, so for this project they
disagree:

```
tested   $XDG_CONFIG_HOME/rofi/../xghost-generated/rofi/colors.rasi
      -> <install location>/config/xghost-generated/rofi/colors.rasi
opened   $XDG_CONFIG_HOME/xghost-generated/rofi/colors.rasi
```

The file has to exist at **both** paths, and Rofi reads the second. The bridge
puts it at the second alone, so the import is dropped, nothing is printed, and
the launcher exits 0. The first path is `config/xghost-generated` inside the
checkout, which the rule above forbids, and a file there would be one that
nothing ever reads.

Ghostty is not affected, and the reason is directly above: Ghostty tries both
bases and takes whichever one holds a file. Rofi tries one base for the test and
one for the open.

[The Rofi bundle](../bundles/rofi.md) therefore writes the path from the home
directory, `~/.config/xghost-generated/rofi/colors.rasi`. That keeps the bridge
and keeps `XDG_STATE_HOME` followed, and it gives up `XDG_CONFIG_HOME`, which is
the one place in the project where a variable is assumed rather than followed.
That page records the consequence, the ways out of it, and the one that was
considered and rejected.

### The optional import of Rofi works, and it is the one directive that reports

This is the second correction, and it reverses what the first draft of this
section said. `?import "file"` resolves its argument against the **directory of
the including file first**, and it falls back to the working directory. The
path named in its warning is the last attempt, which is the working directory
one, and reading that path as the rule is how the first draft got it wrong.

Measured with a file present in one place at a time, and the working directory
somewhere else in every case:

```
present only beside the including file   found
present in both places                   the copy beside the including file wins
present only in the working directory    found
present nowhere                          a warning on standard error, exit 0
```

The difference between the two forms is that last line, and it holds through the
path a session takes:

```
?import "~/gen/missing.rasi"   exit 0, a WARNING on standard error
@import "~/gen/missing.rasi"   exit 0, standard error empty
```

The warning is printed both for `rofi -no-config -theme FILE -dump-theme` and
for a launcher reading its own configuration out of `$XDG_CONFIG_HOME`, which is
the form that reports nothing about a parse failure. It is the only signal this
application gives about a missing include.

`@theme` has no optional form. `?theme` is not in this language: it is a parse
error, it drops the whole file that holds it, and it drops it in silence when
that file is the configuration of the launcher. So a bundle that loads a palette
with `@theme` keeps `@theme`, and it can make its other includes optional.

[The Rofi bundle](../bundles/rofi.md) writes the font line as `?import` for that
reason, and the colours line stays `@theme`. One render writes both files, so
the warning about the font file is the report that the colours are missing as
well.

### Neovim computes the path, and a miss can stop the whole configuration

Neovim is the first application in the table whose configuration is a
programming language, and it is the only one that neither expands a path nor
resolves one. It runs Lua, and Lua is given whatever path the prescribed file
builds. So the two questions of this ADR change shape: not "does the directive
expand a variable" but "which call builds the path", and not "is a miss silent"
but "what does the miss do to the rest of the file".

Both were measured on Neovim 0.12.4, with the bundle linked and a theme
rendered. [The Neovim bundle](../bundles/neovim.md) records the measurements in
full.

**The relative include of every other bundle does not work here.** It is the
Rofi fault again, from the other end. `xghost config link` makes
`$XDG_CONFIG_HOME/nvim` a symbolic link into the checkout, and a `..` is applied
by the kernel *after* it has followed that link, so the path lands in the
checkout rather than in the config directory:

```
stdpath("config") .. "/../xghost-generated/nvim/colors.lua"    not readable
  -> <install location>/config/xghost-generated/nvim/colors.lua
```

That is the directory this ADR forbids the checkout to hold, so the file would
be one nothing ever writes.

**Lua is what gets this bundle out of it.** `vim.fn.stdpath("config")` returns
the config directory **as it was opened**, which is `$XDG_CONFIG_HOME/nvim` and
not the checkout, and `fnamemodify(…, ":h")` takes its parent **as text**. A
path built that way has no `..` for the kernel to apply, so it reaches the
bridge:

```lua
vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h") .. "/xghost-generated/nvim/colors.lua"
```

Both ends of that path still follow the environment, so the Neovim bundle keeps
the property this ADR exists for, and it does not have to give up
`XDG_CONFIG_HOME` the way [the Rofi bundle](../bundles/rofi.md) did.

**A missing generated file is worse here than anywhere else in the table.** In
every other bundle the worst case is an include that is dropped and an
application that looks wrong. In Lua, the call that loads the file decides
whether the rest of the configuration runs at all. Measured with the generated
palette absent, each fixture setting a variable after the load:

| The prescribed Lua uses | The rest of `init.lua` | The report | Exit code |
| ----------------------- | ---------------------- | ---------- | --------- |
| `dofile(path)` | **never runs** | `E5113`, on standard error | 0 |
| `require(name)`, with `package.path` set | **never runs** | `E5113`, on standard error | 0 |
| `loadfile(path)` | runs | whatever the bundle chooses to print | 0 |

`require` and `dofile` raise, and an error raised in `init.lua` stops
`init.lua`. A user who has not yet run `xghost theme set` would get an editor
with no options, no keybindings and no plugins, because of a colour file. **So a
Lua bundle of this project uses `loadfile`**, which returns `nil` and a message
rather than raising, and reports the message itself.

`pcall` around `dofile` keeps the editor alive too, and it is rejected for a
different reason: it swallows every error the file could raise, which is the
silence this ADR spends its length avoiding.

Note the exit code in every row. A start with a broken `init.lua` exits 0, so
Neovim belongs with Ghostty and Rofi under the rule at the end of the next
section: read the state the application holds, never the code it exits with.

**One more thing can swallow the report, and it is not the application.**
`vim.notify` is a variable, and a plugin may replace it. The configuration this
project prescribes loads `snacks.nvim` through LazyVim, which replaces
`vim.notify` at `lua/snacks/init.lua:220` before `init.lua` reaches the bundle,
and measured against the real configuration the warning then reached neither the
message history nor standard error. `vim.api.nvim_echo` is an API function
rather than a variable, so nothing can stand in front of it, and its second
argument keeps the line in `:messages`. A Lua bundle of this project reports
through `nvim_echo`.

### Which applications fail in silence

Ghostty and Rofi report nothing when an include misses. A missing `@import`
target is dropped by Rofi and the launcher keeps the theme it has; a missing
`@theme` target leaves it with **no theme at all**, because `@theme` discards
the default before it reads the file it names. SwayNC drops an unknown key from
`config.json` without a word. In each case the application starts, it looks
wrong, and no log line says why.

Hyprland, the shell, the Waybar `include` array and the SwayNC GTK4 stylesheet
are loud: each reports a source that it could not read. `Config::resolveConfigIncludes` calls
`spdlog::warn("Unable to find resource file: {}", …)`, and that line prints on a
default run: `src/main.cpp` sets a log level only when `-l` is passed, so the
logger holds the default level of spdlog, which is `info`. The Waybar GTK3
stylesheet is louder still, because an `@import` that misses is fatal and Waybar
exits 1.

The GTK4 stylesheet reports through the **default** `parsing-error` handler,
which runs only when a caller has connected none of its own. Measured on
GTK 4.22.4: `Gtk.CssProvider.load_from_path` returns normally, and GTK writes
one line to standard error naming the file, the line and the column range —
`Gtk-WARNING **: Theme parser error: style.css:1:1-49: Failed to import: …`.
Connecting a handler **suppresses** that line and delivers the error on the
signal instead, so a probe that connects one measures a case the daemon never
takes. SwayNC 0.12.6 connects none: `strings -a /usr/bin/swaync` holds no
`parsing-error` at all, while `nm -D --undefined-only` names five CSS symbols.
The report is therefore one line, at startup, and the daemon runs on with the
packaged colours.

A bundle author therefore cannot treat "it started" as evidence that the
include was found. The Ghostty bundle asserts on `ghostty +show-config`, which
prints the settings the application holds after it has read every file, rather
than on the exit code of `ghostty +validate-config`, which is zero on an
unthemed terminal. Every bundle needs a check of that shape: read back the
state the application holds, not the code it exits with.

### Neither GTK CSS route can use `~`

GTK expands no `~` in an `@import`, in GTK3 and in GTK4 alike. The Waybar
stylesheet ([issue #12](https://github.com/qdrtech/xghost/issues/12)) and the
SwayNC stylesheet ([issue #14](https://github.com/qdrtech/xghost/issues/14))
therefore have no home-relative form available, even though one works
elsewhere. The relative include is the only path either of them can write.

### SwayNC has no include mechanism

SwayNC reads one `config.json` and offers no include of any kind. Its whole
configuration file has to be rendered, rather than a prescribed file that
includes a generated fragment. This is a constraint on
[issue #14](https://github.com/qdrtech/xghost/issues/14): SwayNC is the one
bundle whose configuration is generated output in full. Its stylesheet still
uses the construction above, because GTK4 CSS supports `@import`.

An unknown key in that file is dropped in silence, so a mistake in a key name
costs a setting and reports nothing.

### A Waybar include path is trusted input

Waybar expands an include path with `wordexp` and passes flags `0`. That leaves
`WRDE_NOCMD` unset, so command substitution inside an include path runs. An
include path in a Waybar configuration is executed input.

Only the project may write such a path. No value from a theme, from the knobs,
or from any other user-supplied source may reach a Waybar include.

## Consequences

What becomes easier:

- Every bundle writes one form of include, and a bundle author copies one line
  rather than researching an application.
- A user who moves `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, or both keeps a themed
  desktop, because both ends of the path follow the environment.
- A theme switch replaces one symbolic link and changes no include.
- The bridge is a link the linker created, so it is recorded, `unlink` removes
  it, and a path the user already put at that name is a conflict rather than a
  casualty.

What becomes harder:

- Every include in the installation depends on one link. A user who removes the
  bridge unthemes every silent application at once, with no error anywhere.
  That link is a thing for `xghost doctor` to check.
- One bundle assumes `XDG_CONFIG_HOME` rather than following it, because of the
  resolution rule above. A machine that moves that variable has an unthemed
  launcher and no message anywhere, so `xghost doctor`
  ([issue #19](https://github.com/qdrtech/xghost/issues/19)) has a second thing
  to check: that `$XDG_CONFIG_HOME` is `$HOME/.config`, reported against
  [the Rofi bundle](../bundles/rofi.md) and against no other.
- The checkout must never hold `config/xghost-generated`, because of the
  path-precedence rule above.
- A prescribed file has to sit one directory below the config directory, so
  that `..` reaches it. A bundle that nests a prescribed file deeper has to
  count its own `..` segments. A bundle written in a programming language does
  not count them: it builds the parent as text and writes no `..` at all, which
  is what [the Neovim bundle](../bundles/neovim.md) does from three directories
  down.
- A bundle whose configuration is a programming language has a failure mode no
  other bundle has: the call that loads the generated file decides whether the
  rest of the configuration runs. `loadfile` is the call that reports rather
  than raises, and it is the one such a bundle uses.
- The SwayNC configuration file is prescribed, not generated. It has no include
  to reach a rendered fragment through, and the only route to a generated copy
  is `swaync -c <path>` written into a compositor line that expands
  `$XDG_STATE_HOME` to nothing when the variable is unset. So a SwayNC setting
  that has to follow a theme, a knob or a machine fact is a setting this project
  pins or drops, and records. [The SwayNC bundle](../bundles/swaync.md) names
  the two it has.
- A Waybar include path is executed, so it stays a project-owned constant.

## Confirmation

- `tests/linker.bats` proves the bridge: it is created, it is recorded, it is
  removed by `xghost config unlink`, and it never clobbers a path the user put
  at that name.
- `tests/ghostty.bats` renders under a non-default `XDG_STATE_HOME` and proves
  that the include reaches the file the renderer wrote. That case is the
  divergence this ADR exists to prevent, so every later bundle needs one like
  it.
- A bundle test asserts on the state the application reports after it has read
  every file. A validator exit code proves nothing, because a silent miss
  validates clean.
- A reviewer checks that no `config/xghost-generated` directory has entered the
  checkout.
- `tests/rofi.bats` proves the exception: it asserts that neither path of the
  Rofi bundle is relative and that neither names the state directory, and it
  follows both through the bridge under a non-default `XDG_STATE_HOME`.
- `tests/nvim.bats` proves the other exception: it resolves both the `..` form
  and the lexical form inside a running editor and asserts which one reaches
  the bridge, and it asserts that a missing generated file leaves the rest of
  `init.lua` running and reports itself on standard error and in `:messages`.

## More information

The construction is implemented by the Ghostty bundle and documented from two
other sides: [linking](../linking.md) describes the bridge as a link, and
[the Ghostty bundle](../bundles/ghostty.md) describes it as an include.

The per-application findings come from the adversarial review of
[issue #28](https://github.com/qdrtech/xghost/issues/28) and are recorded in
[issue #29](https://github.com/qdrtech/xghost/issues/29). They were taken from
upstream source and confirmed against Ghostty 1.3.1, Hyprland 0.56.2, Waybar
0.15.0, Rofi 2.0.0, and SwayNC 0.12.6.

This ADR is written for the bundles that come next: Waybar
([#12](https://github.com/qdrtech/xghost/issues/12)), Rofi
([#13](https://github.com/qdrtech/xghost/issues/13)), SwayNC
([#14](https://github.com/qdrtech/xghost/issues/14)), the shell
([#15](https://github.com/qdrtech/xghost/issues/15)), and the supporting
bundles ([#17](https://github.com/qdrtech/xghost/issues/17)).
