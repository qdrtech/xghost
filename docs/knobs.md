# Knobs

Knobs are the preferences this desktop supports. They are a defined set that the
project owns, not a free-form override surface: the project names every knob and
every value it takes, and it refuses a value it does not name.

Knobs are the third file category of
[ADR 0001](adr/0001-prescribed-config-architecture.md), and the third input of
the renderer, beside the theme palette and the
[machine facts](machine-facts.md).

```
xghost settings list                 every knob, its value, and the values it takes
xghost settings set KNOB VALUE       change one knob and render again
```

## Two files

| File                                | Owner       | What it holds                                       |
| ----------------------------------- | ----------- | --------------------------------------------------- |
| `schema/knobs.conf`                  | The project | Every knob, the values it takes, and its default.   |
| `$XDG_CONFIG_HOME/xghost/knobs.conf` | You         | The values you chose. Every other knob is absent.   |

The schema is in the checkout, because the project owns it. Your file is in your
config directory, because you own it. An update replaces the checkout and never
writes to your config directory, so your preferences survive every update
untouched.

Three variables move the path of your file, and the first one that is set wins:

| Variable             | What it names                                                 |
| -------------------- | ------------------------------------------------------------- |
| `XGHOST_KNOBS_FILE`  | The file itself. The tests use this.                          |
| `XGHOST_CONFIG_HOME` | Your config directory.                                        |
| `XDG_CONFIG_HOME`    | The same directory, per the XDG base directory specification. |

## A knob that is absent is a knob at its default

Your file names the knobs you changed and nothing else. A knob it does not name
holds the default of the schema, so an absent line and the default are the same
thing, and a machine with no file at all runs every default.

Two consequences follow, and both are the point of this rule:

- A knob a later version of xghost adds reaches your old file as its default.
  Nothing breaks, and `xghost settings list` shows it the day it arrives.
- A fresh machine renders before you have chosen anything.

A knob the project **drops** is the other direction, and it is refused by name:
the file is read against the schema, and a knob that is no longer in the schema
stops the render until you take the line out. The report names the line and the
knob. That is the same rule that refuses a misspelled name, and the project
prefers one clear refusal over guessing at what you meant.

## The format of your file

The file is a data file, not a script. The reader reads it line by line and
never sources it, so a knobs file can never run code.

```
# A comment starts with a hash. An empty line is allowed.

KNOB_ANIMATIONS=off
KNOB_GAP_SIZE=20
KNOB_FONT=CaskaydiaCove Nerd Font
```

The rules:

- One `KNOB_NAME=value` pair per line.
- Every key starts with `KNOB_`, and then holds upper case letters, digits and
  underscores. The prefix is what keeps a knob, a machine fact and a theme
  colour in three namespaces.
- A key may be given once.
- The value has to be one the schema names for that knob. The comparison is
  exact, so `OFF` is not `off`.
- A value may carry one pair of quotation marks, single or double, which the
  reader drops.
- The white space at both ends of a name and of a value is dropped.
- A value holds no control character. It is one line of plain text.
- The file holds no NUL byte. It is a text file, and a reader that dropped the
  byte without a word would run a value that is not the one in the file.
- A value is text. The reader never expands a variable and never runs a command
  in it.

The reader reports every problem of one file, not only the first.

You may edit the file by hand. `xghost settings set` reads the whole file before
it writes, so a file with one bad line is reported and left exactly as it is,
and your other preferences are never lost to it.

## The format of the schema

`schema/knobs.conf` is one record per knob. A record starts with a `knob` line,
and holds `summary` once, `value` once per allowed value, and `default` once.

```
knob=KNOB_ANIMATIONS
summary=Whether a window animates when it opens, closes or moves.
value=on
value=off
default=on
```

Every knob is chosen from a list the schema writes out. There is no range and no
pattern, for two reasons: validation is then exact membership of that list, and
a settings application reads the same list as the choices it offers. The file
format is a key and a value per line, so such an application reads it without
parsing a sentence of English. `summary` is the one field written for a person,
and it is one sentence.

The rules the project holds itself to:

- A knob name matches `KNOB_[A-Z0-9][A-Z0-9_]*`.
- A knob is declared once, and declares one `summary`, one `default`, and at
  least one `value`.
- A value is declared once per knob.
- The default is one of the values.
- A value carries no space at either end and no pair of quotation marks around
  it, so a value written into your file reads back as the same text.

A schema that breaks any of these fails the render and names the line, exactly
as a bad palette does. A schema is a file of the project, so such a failure is a
defect of xghost rather than of your machine. `xghost settings list` and
`xghost settings set` say which of the two files failed, and a schema defect
therefore names the schema and never sends you to correct a file of your own.

## The knobs of today

| Knob                 | Values                                              | Default                 |
| -------------------- | --------------------------------------------------- | ----------------------- |
| `KNOB_ANIMATIONS`    | `on`, `off`                                         | `on`                    |
| `KNOB_GAP_SIZE`      | `0`, `5`, `10`, `15`, `20`                          | `10`                    |
| `KNOB_FONT`          | `JetBrainsMono Nerd Font`, `CaskaydiaCove Nerd Font` | `JetBrainsMono Nerd Font` |
| `KNOB_BAR_POSITION`  | `top`, `bottom`                                     | `top`                   |

Where each one lands:

| Knob                 | Reaches                                                              |
| -------------------- | --------------------------------------------------------------------- |
| `KNOB_ANIMATIONS`    | `generated/hypr/animation.conf`, the whole `animations` block of Hyprland. |
| `KNOB_GAP_SIZE`      | `generated/hypr/knobs.conf`, `gaps_in` and `gaps_out` of Hyprland.    |
| `KNOB_FONT`          | `generated/hypr/knobs.conf`, `misc:font_family` of Hyprland, `generated/ghostty/font.conf`, `font-family` of Ghostty, `generated/waybar/knobs.css`, the family the bar draws in, and `generated/rofi/knobs.rasi`, the family the launcher draws in. Not the lock screen. |
| `KNOB_BAR_POSITION`  | `generated/waybar/position.json`, the `position` of the bar.          |

`KNOB_BAR_POSITION` names two of the four positions Waybar draws. `left` and
`right` turn the bar into a column, and the style sheet of
[the Waybar bundle](bundles/waybar.md) lays every module out across the screen
rather than down it, so a value reaches the list only with the styling that
makes it a bar somebody would want.

`KNOB_GAP_SIZE` is one number for both gaps: between two windows, and between a
window and the edge of the screen. The dotfiles this desktop comes from used 10
and 14. One knob is one value, and a desktop whose windows sit 20 pixels apart
but 14 pixels from the screen edge is a desktop nobody asked for.

Each value of `KNOB_FONT` names a family that one Arch package provides, and a
family no package on the machine provides would leave every application falling
back to a font nobody chose. A value therefore reaches the list only with its
package:

| Value                     | Arch package               | Repository |
| ------------------------- | -------------------------- | ---------- |
| `JetBrainsMono Nerd Font` | `ttf-jetbrains-mono-nerd`  | `extra`    |
| `CaskaydiaCove Nerd Font` | `ttf-cascadia-code-nerd`   | `extra`    |

### The lock screen keeps its own font

`KNOB_FONT` reaches the compositor, the terminal and the bar. It does not reach
`hyprlock`, which draws the clock and your user name in the family written out
in `config/hypr/hyprlock.conf`.

The reason is the one the colours of that file already carry. hyprlock has no
offline check of its configuration, the way Hyprland has `--verify-config` and
Ghostty has `+validate-config`, so a generated file it refused would reach a
machine unproven. What that costs is a lock screen that does not start, and a
machine that goes idle and never locks. The project takes a lock screen on the
default family over that risk, and issue #20 owns theming the file as a whole.

A test in `tests/hyprland.bats` pins the family in `hyprlock.conf` to the
default of `KNOB_FONT`, so the lock screen cannot drift onto a family this
desktop no longer ships.

## The two kinds of knob

The renderer has two substitution mechanisms, and a knob drives either one. It
is the same table of values a machine fact and a theme colour reach, so a knob
adds no mechanism of its own. [Theming](theming.md) documents both.

**A scalar knob** is substituted into a template by name. `KNOB_GAP_SIZE`,
`KNOB_FONT` and `KNOB_BAR_POSITION` are scalars:

```
gaps_in = @KNOB_GAP_SIZE@
```

**A structural knob** selects one whole prescribed fragment out of a directory
of them. `KNOB_ANIMATIONS` is structural, because switching the animations off
is switching off a block of a dozen lines rather than changing a value:

```
templates/hypr/animation.conf.choice.KNOB_ANIMATIONS/
  on       the prescribed animation set
  off      animations { enabled = false }
```

`KNOB_BAR_POSITION` is the case that shows where the line between the two lies.
It moves the bar from one edge of the screen to the other, which sounds
structural, and it is a scalar: the position is one word of one key, and the
styling of the bar is symmetric, so nothing else moves with it.
[The Waybar bundle](bundles/waybar.md) records the decision and what would
reverse it.

The value is never used to build a path. The chosen fragment is looked up among
the files the renderer already found, so a value can reach nothing outside that
directory, and the schema refuses a value the project never named in the first
place.

## What `settings set` does, and what it does not

`xghost settings set KNOB VALUE`:

1. reads the schema and your file, and refuses a knob or a value the schema does
   not name. Nothing is written in that case.
2. writes the value into your file. The line that declares the knob is replaced
   where it stands, and a knob your file does not yet name is appended. Every
   comment you wrote, and every other line, is kept exactly as it is. The write
   is one rename of a complete new file, so an interrupted write, and a write
   that ran out of room, both leave the previous file whole.
3. renders the configuration again, which is what `xghost theme set` does. The
   generated output carries the new value the moment the command returns.

Four properties of that write, and each one is the arrangement you made rather
than a detail of the writer:

- **Your symbolic link is kept.** A knobs file you link in from a dotfiles
  repository is written through the link, so the file in your repository carries
  the new value and the link is still a link. The command never puts a regular
  file in its place.
- **The mode of your file is kept.** A file you set to `0600` stays `0600`. A
  file the command creates is `0644`, because the file holds no secret and the
  renderer reads it.
- **Two commands at once do not lose an update.** The read and the write are one
  step under a lock, at `knobs.conf.lock` beside your file, so a second
  `settings set` waits for the first instead of writing over it. A settings
  application is the case this is for.
- **A write that fails changes nothing.** The new file is written whole before
  anything is renamed, and a failure part way through is reported and dropped.
  The temporary file goes with it, and so does the one an interrupt leaves.

What it does **not** do: it reloads nothing. A program that is already running
keeps the configuration it started with, and shows the change when it next reads
its configuration, which for most of them means a restart. The command says so
rather than implying a desktop that changes on its own. Reloading every running
component from one place is
[issue #24](https://github.com/qdrtech/xghost/issues/24).

Two more cases the command reports rather than hides:

- **No theme is active.** The value is stored and nothing is rendered, because
  there is nothing to render into. Run `xghost theme set <name>`.
- **The render fails.** The value is stored, the previous generated output is
  untouched, and the report names every problem. A knob is not what failed:
  a machine that has never run `xghost machine detect` fails the same way for
  the same reason.

## A knob that collides with a palette key or a machine fact

The renderer holds the theme palette, the machine facts and the knobs in one
table of values. A name that two of them declare is a problem, and the report
names the name and the other source:

```
xghost: tokyonight: knobs: 'KNOB_FONT' is declared by the theme palette as well
```

The render fails and the active theme is unchanged. Neither side wins, because
the two files have two owners and quietly preferring either one would make the
output depend on a rule nobody wrote down. It is the same answer the palette and
the machine facts already give each other.

A knob and a machine fact can never collide at all. A knob starts with `KNOB_`
and a machine fact with `MACHINE_`, and both readers refuse a key of the other
shape, so the two namespaces cannot meet. The collision that can happen is a
theme palette that declares a name in either namespace, and it is refused
whichever of the two it hits.

## Adding a knob

Adding a knob is adding a record to `schema/knobs.conf` and naming it in a
template. No code changes.

1. Write the record: the name, one sentence of summary, every value, and the
   default. The default is the behaviour of the desktop today, so an existing
   machine sees no change until somebody chooses another value.
2. Name it in a template, as `@KNOB_NAME@` for a scalar, or as a
   `<file>.choice.KNOB_NAME/` directory with one fragment per value for a
   structural one. A structural knob needs one fragment per value of the schema,
   or a `default` fragment.
3. Regenerate the golden output with `tests/regenerate-golden --update`, and
   read the difference. The knob has to change something, in at least one of the
   two knob sets, or it is a knob no template consumes.

A preference the schema does not cover is a request for a new knob or a fork.
ADR 0001 records that decision, and records that it is reversible.

## The tests

`tests/knobs.bats` covers the two readers, the renderer that reads them, and the
two commands: every way a schema can be wrong, every way a knobs file can be
wrong, a scalar knob, a structural knob, the collision above, and what each
command writes and prints.

It covers the write itself as well, because what goes wrong there costs a user
their preferences and never shows up in the value the command prints: a knobs
file that is a symbolic link, the mode of a file that is already there, two
`settings set` commands at once, and a write that runs out of room. The last one
sets `ulimit -f` and ignores `SIGXFSZ`, so the write is refused with `EFBIG`
exactly as a full disk refuses it.

`tests/hyprland.bats` reads every prescribed file and every template, and
asserts that a setting a knob owns is written in one place. A guard that named
the files by hand let the same setting be added to a third file and stay green.

`tests/golden.bats` renders every theme at two knob sets and compares both with
the committed output under `tests/golden/<knob set>/<theme>/`. One of its tests
asserts that the two sets differ, which is what proves that every knob reaches a
real file.

`tests/hyprland.bats` runs `Hyprland --verify-config` at every value of every
knob, so a value the compositor would refuse fails the suite rather than a first
login. `tests/ghostty.bats` reads `ghostty +show-config` for the font, which is
the family the terminal holds after it has read every file it reads.
