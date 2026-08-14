# Theming

One module generates all themed configuration. It is the renderer. It reads a
theme and a directory of templates, and it writes a directory of finished
configuration files at a stable path. Applications read that path, so a theme
switch never rewrites the configuration file of an application.

The renderer is a pure function. The same inputs always produce the same output,
and it writes nothing outside the output directory it is given.

Three commands drive it:

| Command                  | What it does                              |
| ------------------------ | ----------------------------------------- |
| `xghost theme list`      | Names every installed theme, one per line. |
| `xghost theme set NAME`  | Renders that theme and moves it into place. |
| `xghost theme current`   | Names the theme the output was built from. |

## Where the generated output lands

The stable path is:

```
$XDG_STATE_HOME/xghost/generated
```

`XDG_STATE_HOME` defaults to `~/.local/state`, so the usual path is
`~/.local/state/xghost/generated`. An empty or relative `XDG_STATE_HOME` is
ignored, which the XDG base directory specification requires.

The path is the state directory for three reasons:

- It is outside every repository working tree. The project installs to a fixed
  location under the user's data directory, and generated output must never land
  in that checkout, because a checkout holds only files git tracks.
- The state directory holds derived files that must survive a reboot. The cache
  directory is wrong, because a cache cleaner may empty it at any moment, and the
  desktop would then come up unstyled.
- The data directory is wrong, because it holds the checkout itself and files the
  user owns. Generated output is owned by nobody and is rebuilt on demand.

Under that directory:

```
~/.local/state/xghost/
  builds/build.XXXXXXXX/theme    the name of the theme this build was made from
  builds/build.XXXXXXXX/tree/    the finished configuration files
  generated -> builds/build.XXXXXXXX/tree
```

`generated` is a symbolic link, because a link is what the kernel replaces in one
step. See "The switch is atomic" below.

## Adding a theme

A theme is a directory under `themes/`. Adding one means adding files. It
requires no change to any project code.

```
themes/<name>/
  palette.conf            required: the named colours of the theme
  files/<relative path>   optional: a file the theme ships by hand
```

The name of the directory is the name of the theme. It holds lower case letters,
digits, and hyphens, and it starts with a letter or a digit. A directory without
`palette.conf` is not a theme: `xghost theme list` leaves it out and
`xghost theme set` refuses it.

## The palette format

`palette.conf` is a data file. The renderer reads it line by line and never runs
it, so a palette can never run code.

```
# A comment starts with a hash. An empty line is allowed.

BG=#1a1b26
ACCENT=#7aa2f7
FONT=Inter Display
```

The rules:

- One `KEY=value` pair per line.
- A key holds upper case letters, digits, and underscores, and it starts with a
  letter.
- A key may be given once.
- A key may not end in `_HEX` or `_RGB`. The renderer reserves those two suffixes
  for the derived forms below.
- A value may carry one pair of quotation marks, single or double, which the
  renderer drops. Quote a value that starts or ends with a space.
- The white space at both ends of a name and of a value is dropped.
- A value is text. The renderer never expands a variable and never runs a
  command in it.
- A palette that declares no value at all is a mistake, and the renderer reports
  it.

The renderer keeps the case the theme author wrote, so `#1A1B26` reaches the
output as `#1A1B26`.

Which names a palette must declare is decided by the templates, not by the
renderer. A template that names a value the palette does not declare fails the
render and reports the file and the name. Read `templates/` for the names the
project uses today.

## The three forms of a scalar

A colour is needed in three forms, so the renderer derives two of them. A value
that matches `#rrggbb` carries all three. Any other value carries the plain form
only.

| Form               | Name        | Example       |
| ------------------ | ----------- | ------------- |
| Plain              | `ACCENT`     | `#7aa2f7`     |
| Without the hash   | `ACCENT_HEX` | `7aa2f7`      |
| Decimal components | `ACCENT_RGB` | `122, 162, 247` |

The convention is one suffix per derived form, appended to the name the palette
declares. `_HEX` suits the Hyprland `rgb()` function. `_RGB` suits a CSS function
that takes an alpha channel of its own, such as `rgba(@ACCENT_RGB@, 0.35)`.

## Templates

A template is a text file under `templates/`. The renderer walks that directory,
including its subdirectories, and writes each file to the same relative path in
the output. `templates/hypr/colors.conf` becomes `generated/hypr/colors.conf`.

Substitution is by name. `@NAME@` is replaced by the value of `NAME`. The name is
upper case, so ordinary text such as a CSS at-rule is never mistaken for a
placeholder.

There is no template language. A template holds no condition, no loop, and no
expression. A choice between two blocks of configuration is a structural choice,
which selects between prescribed fragments rather than templating them.
Structural choices are driven by knobs, and they arrive with the knobs
(issue #11).

Two details of the output:

- Each rendered file ends with exactly one newline.
- An executable template produces an executable file.

## A file a theme ships by hand

A theme may ship a finished file for any application. Put it under
`themes/<name>/files/`, at the relative path it must have in the output.

```
themes/<name>/files/gtk/colors.css
```

The renderer copies that file unchanged and does not render the template of the
same relative path. The file is preserved exactly, placeholders included. Every
other template is still rendered, so a theme gives up generation for one file
only.

A hand-written file needs no matching template. A file the templates do not
mention is added to the output.

## The switch is atomic

`xghost theme set` builds a complete new output directory beside the live one.
Only when every file is written does it move that directory into place, by
replacing the `generated` symbolic link with one rename.

The result: an interrupted or failed switch leaves the previous theme fully
intact. A reader of the stable path sees either the whole previous build or the
whole new one, and never a half-written directory. A failed render reports every
problem it found, removes the half-built directory, and states that the active
theme is unchanged.

The build the link pointed at before the switch is kept until the next switch,
and is dropped then.

## What the renderer does not do yet

- **Machine facts and knobs.** The renderer takes three inputs by design: the
  theme, the machine facts, and the knobs. Only the theme exists today. Issue #9
  defines the machine facts file and issue #11 defines the knobs file. The
  interface accepts all three now and rejects a value for the two that do not
  exist, rather than guessing at their format.
- **Reloading a running component.** A switch writes the new configuration and
  stops there. It sends no signal and restarts nothing, so a running application
  shows the new theme when it next reads its configuration. Reloading every
  component at once is out of scope until the components exist.

## The golden-file tests

`tests/golden.bats` renders every theme against every template and compares the
result with the expected output committed under `tests/golden/`. A template
change that breaks any theme fails there.

`tests/renderer.bats` covers the behaviour around the render: the commands, the
three scalar forms, the hand-written file, the palette rules, and what a failed
switch leaves behind.

When a change to a template, a palette, or the renderer is intentional, rewrite
the expected output with the `--update` flag:

```
tests/regenerate-golden --update
```

Then read `git diff -- tests/golden` before you commit it. The flag is required,
so a bare run rewrites nothing. The script also refuses to run when `CI` is set,
because continuous integration proves the committed output and never rewrites
it.
