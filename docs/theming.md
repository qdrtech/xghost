# Theming

One module generates all themed configuration. It is the renderer. It reads a
theme, the machine facts, and a directory of templates, and it writes a
directory of finished configuration files at a stable path. Applications read
that path, so a theme switch never rewrites the configuration file of an
application.

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
  lock                           held for the whole of one switch
```

`xghost theme list` reads the checkout alone. It needs none of the paths above,
and it works on a machine that has neither `XDG_STATE_HOME` nor `HOME` in its
environment. `xghost theme current` and `xghost theme set` do need them, and
each names the missing value rather than failing before it reads its arguments.

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
  command in it. `&` and a backslash are ordinary characters of the value, and
  they reach the output exactly as the theme author wrote them.
- A value that itself holds `@NAME@` reaches the output as that text. The
  renderer reads a template once and never reads back what it wrote, so a value
  is never substituted a second time.
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

A name comes from the theme palette or from the machine facts. A machine fact
starts with `MACHINE_`, so the two never collide, and a name that both files
declare is a problem the renderer reports.
[Machine facts](machine-facts.md) documents that file and every key it holds.

There is no template language. A template holds no condition, no loop, and no
expression. A choice between two blocks of configuration is a structural choice,
which selects between prescribed fragments rather than templating them. The next
section documents it.

A template is a text file. One that holds a NUL byte is refused by name,
because reading it as text would drop that byte and write a file that quietly
differs from its template.

## Structural choices

A structural choice is the second substitution mechanism of
[ADR 0001](adr/0001-prescribed-config-architecture.md). Substitution by name
replaces a value inside one file. A structural choice picks a whole file.

A directory named `<file>.choice.<NAME>` is a choice. It holds one fragment per
value of `NAME`, and exactly one of them reaches the output, at `<file>` beside
that directory.

```
templates/hypr/monitors.conf.choice.MACHINE_MONITOR_COUNT/
  1          the fragment for a machine with one monitor
  2          the fragment for a machine with two
  3          the fragment for a machine with three
  default    the fragment for every other value
```

With `MACHINE_MONITOR_COUNT=2` that directory writes `generated/hypr/monitors.conf`
from the fragment named `2`, and it writes nothing else.

The rules:

- The name of a fragment is the value it is chosen for. The comparison is exact.
- `default` is the fragment for every value no fragment names. A choice without
  it fails the render when the value matches no fragment, and the report names
  the value and every fragment the choice holds.
- A fragment is an ordinary template. It is substituted by name like any other,
  so a fragment for two monitors names the facts of two monitors.
- A value is never used to build a path. The chosen fragment is looked up among
  the files the renderer already found, so a value that holds a path separator
  can reach nothing outside the directory.
- `NAME` has to be declared, by the theme palette or by the machine facts. A
  choice whose value is missing fails the render and names it, exactly as a
  template that names a missing value does.
- A choice holds fragments and nothing else. A directory inside one, and a
  choice inside a choice, are both refused by name.
- A hand-written file the theme ships at `<file>` wins over the choice, as it
  wins over a template.

This is a selection, never a loop and never a condition inside a template. It is
what lets one prescribed layout serve a machine with one monitor and a machine
with three, without the project growing a template language. Adding the
prescribed layout for a fourth monitor is adding one file, and no code changes.
[The Hyprland bundle](bundles/hyprland.md) records the case the mechanism was
built for.

A template may be a symbolic link. The renderer follows it and renders what it
points at. A link that points at nothing fails the render and is named, because
a theme that ships a link means the file to be there.

Two details of the output:

- Each rendered file ends with exactly one newline.
- An executable template produces an executable file.

## The modes of the generated output

The renderer sets the mode of everything it writes. It does not leave the mode
to the umask of whoever ran the command, so the same inputs produce the same
output on every machine.

| What                      | Mode   |
| ------------------------- | ------ |
| A directory of the output | `0755` |
| A rendered file           | `0644` |
| A rendered file that came from an executable template | `0755` |

The output is read by desktop components and holds no secret, so it is readable
by everybody and writable by its owner alone. `xghost theme set` sets the same
modes on the state directory, the build directory, and each build it creates.

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

The file may be a symbolic link, which is the natural shape for a theme whose
upstream is a stow-managed dotfiles repository. The renderer reads through the
link and writes a real file into the output. A link that points at nothing fails
the render and is named. Following a link never carries a write out of the
output: the renderer resolves the directory it is about to write into and
refuses any path that lands outside.

## The switch is atomic

`xghost theme set` builds a complete new output directory beside the live one.
Only when every file is written does it move that directory into place, by
replacing the `generated` symbolic link with one rename.

The result: an interrupted or failed switch leaves the previous theme fully
intact. A reader of the stable path sees either the whole previous build or the
whole new one, and never a half-written directory. A failed render reports every
problem it found, removes the half-built directory, and states that the active
theme is unchanged.

A switch holds an exclusive lock on `$XDG_STATE_HOME/xghost/lock` from end to
end, so two switches started at the same time run one after the other. The lock
is what makes the paragraph above true of a second switch as well as of an
interrupt.

The old builds are dropped after the rename, never before it. A build is
therefore removed only once some switch has finished writing it, and a directory
another switch is still writing is out of reach. Only the build the stable path
points at survives a switch.

## What the renderer does not do yet

- **Knobs.** The renderer takes three inputs by design: the theme, the machine
  facts, and the knobs. Two of the three exist today. Issue #11 defines the
  knobs file. The interface accepts all three now and rejects a value for the
  one that does not exist, rather than guessing at its format. A structural
  choice already reads any declared value, so a knob drives one the day the
  knobs file lands, with no change to the renderer.
- **Reloading a running component.** A switch writes the new configuration and
  stops there. It sends no signal and restarts nothing, so a running application
  shows the new theme when it next reads its configuration. Reloading every
  component at once is out of scope until the components exist.

## The golden-file tests

`tests/golden.bats` renders every theme against every template and compares the
result with the expected output committed under `tests/golden/`. A template
change that breaks any theme fails there.

The render uses fixed machine facts, `tests/fixtures/machine/golden.conf`, and
never the facts of the computer that runs the suite. They describe two monitors
that never change, so the committed output depends on the templates and the
palettes alone. `tests/regenerate-golden` reads the same file.

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
