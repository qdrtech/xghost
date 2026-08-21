# The Rofi bundle

Rofi is the launcher of xghost. `rofi -show drun` is what the compositor runs on
`SUPER + space`, and `config/hypr/hyprland.conf` names that command as `$menu`.

It is the first bundle that cannot use the relative include every other bundle
writes, and the first whose application says nothing about a file it failed to
parse. It says one thing, and one only: the optional import of the font file
reports when that file is missing, and this bundle is built around that one
report.

The bundle is one prescribed file and two generated ones:

| File                          | Category   | What it holds                                   |
| ----------------------------- | ---------- | ----------------------------------------------- |
| `config/rofi/config.rasi`     | Prescribed | The modes, the layout and the styling, except the colours and the font. |
| `templates/rofi/colors.rasi`  | Template   | The palette of the active theme.                |
| `templates/rofi/knobs.rasi`   | Template   | The font family, from `KNOB_FONT`.              |

The file categories are those of
[ADR 0001](../adr/0001-prescribed-config-architecture.md). The bridge to the
generated output is [ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md),
and the knobs are documented in [Knobs](../knobs.md).

The prescribed file is carried over from `qdrtech/dotfiles`, path
`rofi/.config/rofi/config.rasi`. What changed, and why, is recorded below.

## How the files meet

```
xghost config link     $XDG_CONFIG_HOME/rofi              -> <install location>/config/rofi
                       $XDG_CONFIG_HOME/xghost-generated  -> $XDG_STATE_HOME/xghost/generated
xghost theme set NAME  $XDG_STATE_HOME/xghost/generated/rofi/colors.rasi
                       $XDG_STATE_HOME/xghost/generated/rofi/knobs.rasi
```

`xghost settings set` writes the same two files, because a knob change renders
the same tree.

## The path this bundle writes, and the one it cannot

Every other bundle reaches the generated output by a path relative to the
prescribed file: `../xghost-generated/<app>/<file>`. This one writes the path
from the home directory:

```
@theme "~/.config/xghost-generated/rofi/colors.rasi"
?import "~/.config/xghost-generated/rofi/knobs.rasi"
```

The second one is the optional form, and "The optional import is the one report
this bundle gets" below records why.

**The relative form does not work in Rofi 2.0.0, and it fails in silence.** This
is a measurement rather than a preference, and it was taken on a real machine
with the real linker and the real renderer:

> Rofi tests an import for existence against the **raw joined path**, which the
> kernel resolves physically, and then opens the path it **canonicalises
> itself**, which is lexical. `$XDG_CONFIG_HOME/rofi` is the symbolic link
> `xghost config link` makes, so the two disagree:
>
> ```
> tested   $XDG_CONFIG_HOME/rofi/../xghost-generated/rofi/colors.rasi
>       -> <install location>/config/xghost-generated/rofi/colors.rasi
> opened   $XDG_CONFIG_HOME/xghost-generated/rofi/colors.rasi
> ```
>
> The file has to exist at **both** paths, and Rofi reads the second. With the
> bridge in place and the file the renderer wrote at the end of it, the import
> is dropped, no line is printed, and the launcher exits 0.

The path it tests is `config/xghost-generated` inside the checkout, which
[ADR 0002](../adr/0002-the-bridge-to-the-generated-output.md) forbids for the
Ghostty bundle, and which would be a file nothing ever reads in any case. That
ADR records the resolution rule and the reason Ghostty is not affected: Ghostty
tries both bases, and Rofi tries one and one.

### What the home-relative path keeps, and what it gives up

It keeps the important half. `xghost-generated` is the bridge, so the state
directory is still never written out and **`XDG_STATE_HOME` is still followed**:
a machine that moves it keeps a themed launcher, and `tests/rofi.bats` proves
that case.

It gives up the other half. `~/.config` is the default of the XDG base
directory specification written out, so:

> **A machine that moves `XDG_CONFIG_HOME` has a launcher that reaches neither
> generated file.** Rofi reads its configuration from
> `$XDG_CONFIG_HOME/rofi/config.rasi`, and that file then names a bridge under
> `$HOME/.config`, where `xghost config link` created none. The launcher opens
> with no colour of the theme and no font of the knob. The `?import` of the font
> file reports it on the standard error of the launcher, which in a session is
> the log of the compositor rather than a terminal, so the report is written
> down somewhere the person at the keyboard is not looking.

This is the one path in the project that assumes a variable rather than
following it, and it is written down here rather than hidden. Three things
follow:

- **This belongs on the list for `xghost doctor`
  ([issue #19](https://github.com/qdrtech/xghost/issues/19)).** The doctor
  already has to check that the bridge exists; for this bundle it has to check
  one thing more, that `$XDG_CONFIG_HOME` is `$HOME/.config`, and report the
  launcher as unthemed when it is not. Every other bundle is unaffected, so the
  check belongs to this one.
- **One way out is the linker.** If `xghost config link` ever placed
  `$XDG_CONFIG_HOME/rofi` as a real directory of per-file links rather than as
  one directory link, the relative form would work here as it does everywhere
  else: the two resolutions agree when nothing on the path is a symbolic link,
  and that was measured as well. It was not done for this bundle because a
  per-file link means a prescribed file added by a `git pull` no longer appears
  until the link command is run again.
- **A second way was considered and rejected: a stub in the checkout.** Rofi
  tests `<install location>/config/xghost-generated/rofi/colors.rasi` for
  existence and then opens the bridge copy, so a committed stub at the tested
  path satisfies the test and the launcher reads the **bridge** file, not the
  stub. That was measured: with the relative form and a stub reading
  `font: "STUB 11"`, the launcher holds `font: "BRIDGE 11"`, and with the stub
  removed it holds neither and says nothing. ADR 0002 forbids
  `config/xghost-generated` because Ghostty resolves an include under the real
  path and would read the checkout copy in place of the bridge, and a subtree
  that holds `rofi/` alone does not shadow the Ghostty path, so the rule that
  forbids it is not the rule that would break. It is rejected anyway: a
  committed file that nothing ever reads, whose whole purpose is to exist, is
  worse than a hole that is written down. It would also have to be kept in step
  with the name of every generated file this bundle ever adds.

### The optional import is the one report this bundle gets

Rofi offers an optional import, `?import "file"`. An earlier draft of this page
and of ADR 0002 said it resolves its argument against the current working
directory. **That was wrong**, and the mistake was to read the path in its
warning message, which names the last place it looked, as the rule.

Measured, with the working directory somewhere else in every case:

| The file is                             | Result                                  |
| --------------------------------------- | --------------------------------------- |
| only beside the including file          | found                                   |
| in both places                          | the copy beside the including file wins |
| only in the working directory           | found                                   |
| nowhere                                 | a warning on standard error, exit 0     |

So it resolves against the directory of the including file **first**, and the
working directory is a later fallback. The path this bundle writes starts from
the home directory, so no base is used at all and the difference does not reach
it.

What does reach it is the last line of the table:

```
?import "~/.config/xghost-generated/rofi/knobs.rasi"   exit 0, a WARNING on standard error
@import "~/.config/xghost-generated/rofi/knobs.rasi"   exit 0, standard error empty
```

**The font line is therefore `?import`.** That warning is printed when Rofi
reads its own configuration out of `$XDG_CONFIG_HOME`, which is the form that
reports nothing about a parse failure, so it is the only thing this launcher
ever says about a missing include. One render writes both generated files, so a
missing font file is the report that the colours are missing with it, and every
failure this page names as the worst one, the bridge gone, the render not run
yet, `XDG_CONFIG_HOME` moved, reaches standard error instead of nothing.

**The colours line stays `@theme`, because there is no optional form of it.**
`?theme` is not in this language. It is a parse error, it drops the whole
prescribed file, and through the launcher's own configuration path it drops it
without a word.

## The rule of this bundle: `@theme` first, and once

`@import` merges a file into the theme. `@theme` **discards the theme loaded so
far** and starts a fresh one from the file it names. The prescribed file uses
one of each, and the order is the whole design:

1. `@theme` loads the generated palette. The default theme of Rofi is discarded
   here, and that is why it is `@theme` and not `@import`.
2. `?import` merges the generated font, and reports when that file is missing.
3. Every block of the prescribed file is parsed after both, so each one draws
   with the colours of step 1 and the family of step 2.

Two failures follow from getting that wrong, and neither reports anything:

> **A second `@theme` throws the first away.** A `@theme` written below the
> blocks of the prescribed file throws every one of them away as well, and the
> launcher comes up as stock Rofi.

The default theme of Rofi is Solarized light. Discarding it is what keeps the
launcher from mixing that palette into every widget the prescribed file does not
style, and it is what the dotfiles did. The measured result is a launcher whose
whole theme holds ten colours, each one a colour of the active theme.
`tests/rofi.bats` reads them back out of Rofi itself.

Step 3 gives this bundle the same rule the Waybar bundle has, in the opposite
direction. There, the including file wins; here, the file parsed last wins, and
the prescribed file is parsed last:

> **A colour or a font written in the prescribed file wins over the generated
> one.** So `config/rofi/config.rasi` holds no `#rrggbb` at all and names no
> font, and `font` appears in exactly one file of this project:
> `templates/rofi/knobs.rasi`.

The generated palette declares all ten colours of the theme, and the launcher
draws with three of them: `bg`, `text` and `accent`. That is what the dotfiles
drew with, under three other names. The other seven are declared for the same
reason [the Waybar bundle](waybar.md) declares them: the file is the palette of
the theme rather than the subset one application happens to use today, and a
block added later names a colour that is already there.

## An underscore in a name is a parse error

A name in this language holds letters, digits and hyphens. `text_muted` is a
parse error, and a parse error drops the **whole file**.

This one is worth its own section because the project walks straight into it:
every palette key of every theme holds an underscore, `SURFACE_ALT`,
`TEXT_MUTED` and `ACCENT_ALT`, and the Waybar bundle writes them into GTK with
the underscore kept. `templates/rofi/colors.rasi` converts them to hyphens, and
`tests/rofi.bats` fails on a name that holds one.

The first draft of this bundle carried three of them. Rofi reported
`Failed to parse theme` and exited 0, and the launcher held the default theme:
the file the `@theme` named was reached and dropped, so the default was never
discarded. That is the difference between a file that fails to parse and a file
that is missing, and "What this bundle has never been observed doing" below uses
it to tell the two apart on sight.

## How theme validity is tested

**The exit code proves nothing.** Rofi 2.0.0 exits 0 on a theme that fails to
parse, and it exits 0 on a theme whose imports reached nothing.
[Issue #13](https://github.com/qdrtech/xghost/issues/13) names this, and it was
measured again here: a file with an underscore in a name exits 0 and reports on
standard error. The size of that report is not a constant, because the message
carries the process id and the path of the file, so no test of this project
counts its bytes.

**Empty standard error is the only reliable signal, and it is reliable in one of
the two forms.** The asymmetry is measured, and it decides the shape of every
test in `tests/rofi.bats`:

| Invocation                                | A file that fails to parse | Reads the linked configuration |
| ----------------------------------------- | -------------------------- | ------------------------------ |
| `rofi -no-config -theme FILE -dump-theme` | **reports on standard error**, exits 0 | no  |
| `rofi -dump-theme`                        | **reports nothing**, exits 0 | yes |

A missing include is the other way round, and it is the reason the font line is
`?import`: the second form **does** report a missing optional import, and
neither form reports a missing `@import` or a missing `@theme` target.

So the suite uses both, for two different questions:

- **Does this file parse?** `-no-config -theme FILE -dump-theme`, and the proof
  is that standard error is empty. Every prescribed file and every generated
  file of the bundle goes through it.
- **Did the generated files reach the launcher?** `-dump-theme`, and the proof
  is the theme it prints. Standard error cannot answer this one: a launcher
  whose imports reached nothing is silent. The test reads every palette name
  back out of the printed theme and compares it with the palette of the active
  theme, and it counts the colours so that no eleventh one can appear.

`tests/rofi.bats` carries the negative control of the first form: a file with an
underscore in a name, asserted to exit 0 **and** to report on standard error. A
check that cannot fail proves nothing, and this one is a check on the behaviour
of another program.

Neither form opens a window. Both print and return, and the suite removes
`DISPLAY` and `WAYLAND_DISPLAY` from the environment of every invocation, so no
test of this project can put a launcher on a screen. `-show` and `-modi` appear
in no test file.

## What changed from the dotfiles

Everything that is not a colour, a font or a path is carried over unchanged. The
rest is here.

| Change                                                     | Why                                                                    |
| ---------------------------------------------------------- | ---------------------------------------------------------------------- |
| `font` is gone from the `configuration` block              | It is `KNOB_FONT`. A `font` in the theme wins over a `font` in the configuration block, so the two lines the dotfiles carried were one line doing nothing. |
| `@theme "generated-theme.rasi"` is the two directives above | The generated files of the dotfiles were written by `scripts/theme-switch.sh` into the config directory. This project renders into the state directory and reaches it through the bridge. |
| The geometry of `generated-theme.rasi` is dropped           | That file set `window` width, padding and border, `listview` lines and spacing, and `element` padding, and the prescribed file below it set every one of them again. The prescribed values are the ones that drew. Only the colours are generated here, so nothing generated is overruled. |
| The global `* { background-color: @bg; text-color: @fg; }` is gone | `generated-theme.rasi` set both for every widget at once. `templates/rofi/colors.rasi` declares the palette and no default, so the global block of the launcher holds ten colours, a font, and no `background-color` and no `text-color`. `@theme` has discarded the block Rofi ships, which sets `background-color: transparent`. Every widget the prescribed file styles carries its own colours; a widget it does not style, `message`, `case-indicator`, `num-filtered-rows` and `element-index` among them, now has no colour source at all, and `textbox` outside `error-message` inherits from nothing. Whether any of them is ever drawn is one of the things below that has never been observed. |
| `@color11` is `@accent`                                     | The generated file of the dotfiles aliased `color11` to `accent`. One name for one colour. |
| `@background` is `@bg`, `@foreground` is `@text`            | The same aliases, in the other direction: the palette names of this project are what every other bundle writes. |
| `@border-width` is `1px` and `@border-radius` is `6px`      | See "The names the dotfiles drew with that nothing defined" below.      |
| `background-image: @current-image` is dropped from `mainbox`| The same: nothing ever defined `current-image`.                         |
| Two `background-image: url("~/.config/wallpapers/…")` are dropped | They named one wallpaper file by name, in a directory this project does not ship. The background of a theme is drawn by `lib/background.py` and lives in the generated output. See [Backgrounds](../backgrounds.md). |

### The names the dotfiles drew with that nothing defined

The launcher named `@border-width`, `@border-radius`, `@current-image` and
`@color11`. The generated file beside it defined only the last of those four.
Three values of every login therefore resolved to nothing, and Rofi reported
none of it.

This is the same fault the [Waybar bundle](waybar.md) found in the style sheet of
the same dotfiles, and it is caught the same way: `tests/rofi.bats` reads every
`@name` out of the prescribed file and fails when the generated palette does not
define it. The guard holds for a name added later as well as for these four.

`border-width` and `border-radius` are geometry rather than colour, so they are
written into the prescribed file, and the values are not invented:

| Name              | This bundle writes | Where it comes from                                    |
| ----------------- | ------------------ | ------------------------------------------------------ |
| `@border-width`   | `1px`              | `border_size = 1`, `config/hypr/conf/window.conf`.      |
| `@border-radius`  | `6px`              | `rounding = 6`, `config/hypr/conf/decoration.conf`.     |

The launcher is a window on this desktop, so it carries the border and the
corner of every other window on it.

## The packages this bundle needs

| Package                   | Repository | What needs it                                                    |
| ------------------------- | ---------- | ---------------------------------------------------------------- |
| `rofi`                    | `extra`    | The launcher itself. It provides and replaces `rofi-wayland`, so this desktop needs no second package for the compositor it runs on. |
| `ttf-jetbrains-mono-nerd` | `extra`    | The prompt glyph of the input bar, and the default of `KNOB_FONT`. The Ghostty and Waybar bundles name it as well. |
| `ttf-cascadia-code-nerd`  | `extra`    | The second value of `KNOB_FONT`. See [Knobs](../knobs.md).       |

Every package above is declared in `install/packages/base.txt`, and
`tests/install.bats` fails when a package this table lists is in no manifest.
[Installing](../installing.md) records the manifest.

The prompt of the input bar is a glyph of the Nerd Font private use area, which
is why the two font packages are in this table rather than in the Waybar one
alone. A machine without one of those families draws an empty box where the
prompt is.

No icon theme is in the table. `show-icons` is on, so `drun` draws the icon each
desktop entry names, and the lookup uses the icon theme the desktop already
carries: `hicolor-icon-theme` is a hard dependency of `rofi` itself, and
`adwaita-icon-theme` is a hard dependency of `gtk3`, which the bar needs. An
entry whose icon no theme provides draws no icon, which is a gap in a row rather
than a launcher that fails.

## What the tests prove

- `tests/rofi.bats` proves the bundle. It reads the prescribed file as the data
  it is: exactly one `@theme`, first, naming the colours; one `?import` and no
  `?theme`; no relative import and no state directory in either path; no colour
  and no font of its own; every `@name` it draws with defined by the generated
  palette; no underscore in any name; the prompt glyph still there, as the one
  non-ASCII line of the file; no machine fact in any template. Every loop over
  the palette names counts what it compared and fails when that count is not the
  number of names the template declares, so a name the reader of the template
  cannot read is a name that fails the suite rather than one that disappears
  from it. It follows both imports through the
  bridge to the files the renderer wrote, and does it again with
  `XDG_STATE_HOME` moved. It renders every theme and compares the generated
  palette with the palette of the theme, and it drives `KNOB_FONT` at every
  value the schema names. Two tests are the order of an installation: after
  link, detect and render, every path the launcher reads is a file; after link
  alone, neither is.
- `tests/rofi.bats` also runs Rofi, in the two read-only forms above. It proves
  that every file of the bundle parses with nothing on standard error, that a
  file which does not parse still exits 0 and does report, that the same broken
  file reports nothing when it is the launcher's own configuration, that the
  launcher holds the palette of each theme and exactly ten colours, that it
  holds the family `KNOB_FONT` names, and that before the first render it holds
  none of the palette and says so on standard error through the `?import`. The
  test of the silent form carries a positive control: it dumps a valid marker
  out of the same configuration directory first, so that empty standard error
  cannot be the silence of a file that was never read. The palette assertions
  match one whole line, so a name bound to the wrong value fails. Those tests
  skip on a machine with no Rofi, which is the continuous integration runner;
  everything they prove about the shipped files is proved again by reading
  them.
- `tests/golden.bats` compares the rendered colours and font family of every
  theme with the committed output under `tests/golden/<knob set>/<theme>/rofi/`.
- `tests/install.bats` reads the package table above and fails when a package it
  lists is declared by no manifest.

## What this bundle has never been observed doing

**The launcher has never been seen.** No window was opened against this bundle,
because the machine it was written on runs a live session and a launcher started
there would appear on it. Every claim above is proved by rendering, by reading
the prescribed file, and by asking Rofi 2.0.0 itself what it parsed and what
theme it holds. What that leaves unobserved:

- **Nothing has been drawn.** No entry, no icon, no prompt glyph, no selected
  row. The layout, the two columns, the mode switcher and the sizes are carried
  over from a launcher that ran in the dotfiles; the colours, the font, the nine
  element states and the two dropped wallpapers are new.
- **`drun` has never listed an application.** That the modes are the modes the
  keybinding asks for is proved from the two files that name them, and not from
  a run.
- **The corner and the border have never been compared with a window.** They are
  the numbers `config/hypr/conf/window.conf` and `conf/decoration.conf` hold,
  read from those files. Whether Rofi draws a 6 pixel corner the same way
  Hyprland draws one is not known here.
- **No icon lookup has been watched.** The two icon themes above are read out of
  the dependencies of `rofi` and of `gtk3` rather than from a launcher that drew
  an icon.
- **No widget outside the prescribed file has been seen.** The dotfiles set a
  colour for every widget at once through the global block named in the table
  above, and this bundle does not. `rofi -dump-theme` shows the twenty-four
  widgets the prescribed file styles and no other, so `message`,
  `case-indicator`, `num-filtered-rows` and `element-index` have no colour of
  their own. Which of them `drun` draws, and what they look like when it does,
  is not known here.

A first session with this launcher is therefore the first test of it. Three
failures are the ones to look for:

- **A launcher with no colour at all**, or one whose text is invisible. The
  `@theme` target was missing, so the default theme was discarded and nothing
  took its place. The font file is missing with it, so the `?import` reported it
  on the standard error of the launcher: read the log of the compositor. Check
  `$XDG_CONFIG_HOME` first, and the bridge second: if the variable is not
  `$HOME/.config`, that is this page, above.
- **A Solarized light launcher.** This is **not** a path that missed. A `@theme`
  whose target is missing discards the default theme and loads nothing in its
  place, which leaves a launcher with no colour at all, the symptom above.
  Solarized light means a file **was** reached and **failed to parse**, so the
  whole of it was dropped and the default theme survived. Run
  `rofi -no-config -theme ~/.config/xghost-generated/rofi/colors.rasi -dump-theme`
  and read standard error: that form reports a parse failure, and the launcher's
  own configuration path does not. An underscore in a name is the likeliest
  cause, and it has its own section above.
- **A launcher that ignores a theme switch or `KNOB_FONT`.** A colour or a font
  was written into the prescribed file, which is parsed last and wins.
