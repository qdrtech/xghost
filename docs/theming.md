# Theming

One module generates all themed configuration. It is the renderer. It reads a
theme, the machine facts, the knobs, and a directory of templates, and it writes
a directory of finished configuration files at a stable path. Applications read
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

`xghost settings set` drives it as well: a knob change renders the same tree
from the same three inputs. [Knobs](knobs.md) documents that command.

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
  command in it. `&` is an ordinary character of the value, and it reaches the
  output exactly as the theme author wrote it.
- A value holds none of the six characters below. See "What a value may hold".
- A value that itself holds `@NAME@` reaches the output as that text. The
  renderer reads a template once and never reads back what it wrote, so a value
  is never substituted a second time.
- A palette that declares no value at all is a mistake, and the renderer reports
  it.

The renderer keeps the case the theme author wrote, so `#1A1B26` reaches the
output as `#1A1B26`.

### The names a palette must declare

The templates decide these names, not the renderer. The renderer holds no list
of its own. A template that names a value the palette does not declare fails the
render and reports the file and the name, so a theme that leaves one of the
names below out fails at the first switch.

| Name          | What it is for                                                             |
| ------------- | -------------------------------------------------------------------------- |
| `ACCENT`      | Focus, a selection and the cursor. The background image is tinted with it. |
| `ACCENT_ALT`  | The second accent, for what the first one does not mark.                   |
| `BG`          | The colour behind everything. The background image is drawn from it.       |
| `ERROR`       | A failure, and red in the terminal.                                        |
| `SUCCESS`     | A success, and green in the terminal.                                      |
| `SURFACE`     | A panel that sits on the background.                                       |
| `SURFACE_ALT` | The second surface colour, for a panel on a panel.                         |
| `TEXT`        | Ordinary text.                                                             |
| `TEXT_MUTED`  | Text that recedes and stays readable. Ghostty draws bright black in it.    |
| `WARN`        | A warning, and yellow in the terminal.                                     |

Every one of the ten is a colour, so each one carries the three forms of "The
three forms of a scalar" below. A template that names `@BG_HEX@` or `@BG_RGB@`
names `BG`: the palette declares the plain name alone, and the renderer derives
the other two. A palette key may not end in `_HEX` or `_RGB`, so a derived form
always folds back to exactly one declared name.

`tests/docs.bats` reads this table against the templates, both ways round. A
name a template starts to read has to reach this table, and a name that leaves
the templates has to leave it. So the list is what the renderer requires, and
not what the two shipped themes happen to declare.

Both shipped palettes declare these ten names and no other, and two tests keep
that true. `tests/golden.bats` renders every shipped theme against every
template, so a template that read an eleventh name would fail there.
`tests/docs.bats` holds the other direction: a palette name that no template
reads is dead weight the author of a new theme would copy, and no render would
ever report it.

A structural choice reads a name the same way. `<file>.choice.<NAME>` needs
`NAME` declared, so a choice keyed on a palette name belongs in the table above
as well. No shipped choice is keyed on one today.

Two of the ten are read outside a template as well: `lib/background.sh` draws
the background image from `BG` and from `ACCENT`. A theme without one of the two
still renders. The image is not drawn, and one sentence reaches standard error.
[Backgrounds](backgrounds.md) records that.

## What a value may hold

A value reaches a file that another program reads as code. Neovim loads
`nvim/colors.lua` as a Lua chunk and a shell sources `shell/colors.sh`, and in
both of them the value sits inside a string literal. In `hypr/knobs.conf` the
same kind of value sits inside no literal at all.

The renderer substitutes by name in one pass. It reads no syntax around a
placeholder, so it cannot know which of those a value is landing in, and it
holds no table of output languages. The rule is therefore the value rather than
the file: **a value has to be inert wherever it lands.**

Six characters are not, so a value may hold none of them:

| Character           | Why a value may not hold it                                                    |
| ------------------- | ------------------------------------------------------------------------------ |
| `"`                 | It closes a literal in Lua, in JSON, in TOML, in CSS and in a shell.           |
| `'`                 | It closes one in a shell, in Lua and in CSS.                                   |
| `` ` ``             | It runs a command in a shell.                                                  |
| `\`                 | It escapes the character after it, the closing quotation mark included.        |
| `$`                 | It expands a variable or runs a command in a shell, and names a variable in a Hyprland file. |
| A control character | It ends the line, so the rest of the value becomes a directive of its own.     |

The rule belongs to the renderer, so it holds for every template and for all
three sources of a value: the theme palette, the [machine facts](machine-facts.md)
and the [knobs](knobs.md). A value that holds one of the six stops the whole
render. The report names the theme, the template, the value and the character:

```
xghost: tokyonight: nvim/colors.lua: the value of 'BG' holds a quotation mark:
'#1a1b26"'. A value reaches a file another program reads as code, so it holds no
quotation mark, no apostrophe, no backtick, no backslash, no dollar sign and no
control character. Correct it in the theme palette, the machine facts or the
knobs.
```

The renderer never mends such a value. A value it escaped would be a value the
theme author did not write, and a file another program reads as code is not the
place to guess. The previous generated output is left exactly as it was, because
the renderer builds a whole tree and `lib/theme.sh` moves it into place only
once the render is complete.

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

A name comes from the theme palette, from the machine facts, or from the knobs.
A machine fact starts with `MACHINE_` and a knob with `KNOB_`, so those two never
collide, and a name that two of the three files declare is a problem the
renderer reports. [Machine facts](machine-facts.md) documents the second file
and every key it holds, and [knobs](knobs.md) documents the third.

A machine fact whose value is `unknown` never reaches a rendered file. That word
is what detection writes for a fact it could not read, so a template that names
one fails the render and reports the file and the name, exactly as a template
that names a value nobody declares does. Writing it would produce a
configuration file that states something about the machine nobody read:
`monitor = eDP-1,unknown,0x0,1.5,transform,0` is a line Hyprland refuses, and
the theme switch that wrote it would report success. A structural choice still
selects on `unknown`, because selection picks a whole file and `default` is the
file for a fact nobody read.

There is no template language. A template holds no condition, no loop, and no
expression. A choice between two blocks of configuration is a structural choice,
which selects between prescribed fragments rather than templating them. The next
section documents it.

A template is a text file. One that holds a NUL byte is refused by name,
because reading it as text would drop that byte and write a file that quietly
differs from its template.

### Writing a literal `@NAME@`

Some configuration has to carry the exact spelling the renderer substitutes.
SwayNC names the default audio device `@DEFAULT_AUDIO_SINK@`, and no palette, no
machine fact and no knob declares that name, so a template holding it fails the
render.

`@@NAME@@` writes the literal text `@NAME@`:

| The template holds | The output holds       |
| ------------------ | ---------------------- |
| `@BG@`             | `#1a1b26`              |
| `@@BG@@`           | `@BG@`                 |
| `@@NOSUCHNAME@@`   | `@NOSUCHNAME@`         |

The escape reads no value, so the name inside it names nothing. `@@NOSUCHNAME@@`
renders, where `@NOSUCHNAME@` fails the render.

The escape is exactly this wide, and no wider:

- A lone `@` is ordinary text and always was. A CSS `@import` and a Hyprland
  `$variable` need nothing.
- `@@` on its own is ordinary text as well.
- `@@BG@` and `@BG@@` keep the meaning they had: one `@` beside a placeholder.

`@@NAME@@` is the only spelling whose meaning this rule changed, and it is the
one spelling a template could not write before. So every template written
before the rule renders exactly as it did.

The escape belongs to the template text and never to a value. A value that
holds `@@NAME@@` reaches the output as `@@NAME@@`, because the renderer reads a
template once and never reads back what it wrote.

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
- `NAME` has to be declared, by the theme palette, by the machine facts or by
  the knobs. A choice whose value is missing fails the render and names it,
  exactly as a template that names a missing value does. A knob is always
  declared, because the schema gives every knob a default.
- A choice holds fragments and nothing else. A directory inside one, and a
  choice inside a choice, are both refused by name.
- Exactly one file of the project reaches `<file>`. A choice that writes the
  path another choice writes, or the path an ordinary template writes, fails
  the render and names both. Neither one wins, because no rule says which
  should.
- A hand-written file the theme ships at `<file>` wins over the choice, as it
  wins over a template. That is the one rule of precedence, and it is written
  down here.

This is a selection, never a loop and never a condition inside a template. It is
what lets one prescribed layout serve a machine with one monitor and a machine
with three, without the project growing a template language. Adding the
prescribed layout for a fourth monitor is adding one file, and no code changes.
[The Hyprland bundle](bundles/hyprland.md) records the case the mechanism was
built for.

A knob drives a choice in exactly the same way, because both read one table of
values. `templates/hypr/animation.conf.choice.KNOB_ANIMATIONS/` holds `on` and
`off`, and the animations of the desktop are one whole prescribed file rather
than a setting with a condition around it. [Knobs](knobs.md) documents that
file and the two kinds of knob.

### One file takes one choice, and a choice holds no choice

Two of the rules above were read as defects and were examined as such. Both
stay. This is the record of why, so the next reader who meets one of the two
refusals reads a decision rather than a gap.

**One output file takes exactly one structural choice.** Two choice directories
that write one path fail the render, and both are named:

```
xghost: demo: swaync/config.json.choice.MACHINE_BACKLIGHT_COUNT: it writes
'swaync/config.json', and 'swaync/config.json.choice.KNOB_BAR_POSITION' writes
that path as well
```

Composing them means writing one file out of two prescribed fragments, and that
is a merge rather than a selection. To merge, the renderer would have to know
where in the file the second fragment belongs, which means reading the syntax of
the file it is writing. The renderer reads no syntax anywhere, which is the rule
"What a value may hold" above rests on, and it holds no table of output
languages.

The merged file would also break the property the mechanism is sound on. What
the renderer writes at `<file>` today is one prescribed fragment, the file
itself, chosen by a name the walk of `templates/` already found. A value never
builds a path and never builds text. A merged file is text the renderer
assembled, and no file under `templates/` would hold it. So the limit stays,
and a file that needs two structural variations needs a mechanism this project
does not have. [ADR 0001](adr/0001-prescribed-config-architecture.md) names two
substitution mechanisms, and a third is an ADR decision rather than a renderer
change.

**A structural choice cannot hold another one.** A choice inside a choice fails
the render and is named:

```
xghost: demo: swaync/config.json.choice.KNOB_BAR_POSITION/top.choice.MACHINE_BACKLIGHT_COUNT:
a structural choice cannot hold another one, and this one is inside
'swaync/config.json.choice.KNOB_BAR_POSITION'
```

Nesting keeps the property above whole: every leaf is still one prescribed file
the walk found, and the value at each level is still compared against names
rather than joined into a path. So this limit stays for a different reason, and
the reason is cost.

A nested choice is the product of its levels. Two values by two values is four
whole copies of the file, and the file this was examined for is
`config/swaync/config.json`, which is 160 lines and which the two settings reach
in a handful of them. Every later change to the daemon would have to be made
four times, in four files that a reader has to diff to tell apart. Duplication is the accepted price of a
structural choice — `monitors.conf.choice.MACHINE_MONITOR_COUNT` holds four
layouts of about fifteen lines each — but a product rather than a sum turns that
price into one the project would refuse to pay at the one file that asked for
it. A mechanism whose only intended caller should not use it is not worth its
complexity, so it is not built.

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

## The background of the theme

One file of the output is not a template and not a fragment: the background
image. It is a raster image, so no substitution can produce it, and the
renderer draws it from the same table of values every template reads.

```
<generated>/hypr/background.png     the image, drawn from BG and ACCENT
<generated>/hypr/wallpaper.conf     the hyprpaper block that names it
```

It is drawn inside the render, so it is moved into place by the one rename that
makes a theme switch atomic. It is not a third substitution mechanism: nothing
a template writes can reach it, and [ADR 0001](adr/0001-prescribed-config-architecture.md)
still names two.

A theme that has no `BG` or no `ACCENT`, and a machine whose display resolution
nobody has read, each get no image and one sentence on standard error. Neither
is a failure of the render, because neither is something to invent a value for.
[Backgrounds](backgrounds.md) documents the whole of it, and the one dependency
it proposes.

## A file a theme ships by hand

A theme may ship a finished file for any application. Put it under
`themes/<name>/files/`, at the relative path it must have in the output.

```
themes/<name>/files/gtk/colors.css
```

The renderer copies that file unchanged and does not render the template of the
same relative path. The file is preserved exactly, placeholders included. Every
other template is still rendered, so a theme gives up generation for one file
only. The same rule covers the background: a theme that ships
`files/hypr/background.png` keeps it, and nothing is drawn over it.

A hand-written file needs no matching template. A file the templates do not
mention is added to the output.

The file may be a symbolic link, which is the natural shape for a theme whose
upstream is a stow-managed dotfiles repository. The renderer reads through the
link and writes a real file into the output. A link that points at nothing fails
the render and is named. A link that points at a directory fails the render and
is named as well: the output holds a copy of the file, so a theme ships a file
here, or a link to one, and nothing else. A directory that is not a link is not
a file the theme ships at all, and the template of that path is rendered as
usual. Following a link never carries a write out of the
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

- **Restarting a running component.** A switch writes the new configuration and
  then tells the running components to read it again. It restarts nothing, and
  it signals nothing that has no reload of its own, so an application outside
  that set shows the new theme when it next starts. A knob change is the same.
  [Reloading](reloading.md) records which components take a signal, which need
  none and why, and what a component that did not take one is reported as.

## The golden-file tests

`tests/golden.bats` renders every theme against every template, at every knob
set, and compares the result with the expected output committed under
`tests/golden/<knob set>/<theme>/`. A template change that breaks any theme
fails there.

Two files of the output are left out of that comparison: the background image,
which is megapixels of generated output, and the file that names it, which
holds a path of the machine that rendered it. `tests/background.bats` renders
both and asserts the size, the colours and the text.

The render uses fixed machine facts, `tests/fixtures/machine/golden.conf`, and
never the facts of the computer that runs the suite. They describe two monitors
that never change. It uses two fixed knob sets, and never the preferences of
whoever runs the suite:

| Knob set    | The knobs                                                            |
| ----------- | --------------------------------------------------------------------- |
| `default`   | No knobs file at all, so every knob holds the default of `schema/knobs.conf`. |
| `alternate` | `tests/fixtures/knobs/alternate.conf`, which holds every knob at a value that is not its default. |

The committed output therefore depends on the templates, the palettes and the
schema alone. Two knob sets are what prove that a knob reaches the output: one
tree alone would pass with a knob that no template consumes, and one test
asserts that the two trees differ. `tests/regenerate-golden` reads the same
files.

`tests/renderer.bats` covers the behaviour around the render: the commands, the
three scalar forms, the escape, the hand-written file, the palette rules, the
structural choice and every way one can be wrong, and what a failed switch
leaves behind.

One test of `tests/golden.bats` reads `@NAME@` in the committed output as a
placeholder nobody substituted. No shipped template uses `@@NAME@@` yet, so the
two do not meet today. The first template that escapes one writes `@NAME@` into
the golden output on purpose, and that test has to learn the difference in the
same commit.

When a change to a template, a palette, or the renderer is intentional, rewrite
the expected output with the `--update` flag:

```
tests/regenerate-golden --update
```

Then read `git diff -- tests/golden` before you commit it. The flag is required,
so a bare run rewrites nothing. The script also refuses to run when `CI` is set,
because continuous integration proves the committed output and never rewrites
it.
