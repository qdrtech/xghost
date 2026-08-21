# The doctor

One command reports whether this desktop is healthy:

```
xghost system doctor
```

It prints one section per check, in plain text, and ends with the number of
problems it found. The whole report is meant to be pasted into an issue, so it
carries no colour when it is written to a pipe or to a file.

**Redirect standard error with it.** Some of the detail a check reports comes
from the module that read the file — the manifest reader and the linker both
write their own findings to standard error, as every module of this project
does. A report saved with `>doctor.txt` alone loses those lines:

```
xghost system doctor >doctor.txt 2>&1
```

**It reads.** The one thing it writes is a temporary directory that it renders
the active theme into, and it removes that directory again. It changes no file
of the user, nothing in the checkout, and nothing under the state directory. It
signals no component of the running session and it installs nothing.

## Why the command is `xghost system doctor`

The dispatcher routes `<group> <verb>`, and a command file is named
`<group>-<verb>`, so a single-word top-level command has no legal file name.
[`docs/updating.md`](updating.md) records that decision in full for `xghost
system update`, which landed first. This command follows it rather than
changing the dispatcher: the naming of both is one decision, and it belongs in
one place.

## What it reports

| Section                    | What it answers                                                            |
| -------------------------- | -------------------------------------------------------------------------- |
| `this installation`        | The checkout, the version, the active theme, and a summary of the machine facts. |
| `prescribed configuration` | Every prescribed file that has been changed on this machine, by path.      |
| `dependencies`             | Every package of the base manifest this machine does not have.             |
| `generated output`         | Whether the output is there, and whether it matches what the inputs would produce now. |
| `symbolic links`           | Every link this project made that is gone, that points elsewhere, or whose target is not there. |

Each line carries one of two verdicts. `ok` is a measurement, so it states the
number it measured; `problem` names the fault and the path, and the lines under
it carry the detail.

## The exit status

**It ends non-zero when the report holds a problem.** The status is built from
the number of problems, not from the status of whatever ran last. A doctor that
ended with the status of its last check would end well over a report full of
faults, and a test that only asked whether the command succeeded would never
notice.

## Every check is independent

One check never hides another. A failure inside one of them can neither end the
run nor reach the next, so a report that names five faults in five sections is
a report that really made five checks.

That matters more here than in most commands. A doctor whose first failure
ended the run still prints something that looks like a report, and a reader has
no way to tell a section that found nothing from a section that never ran.

The mechanism is in `lib/doctor.sh`: each check is called as `check || true`.
That is not a swallowed error. The status of a check carries nothing the reader
needs, because every problem it found is already printed and counted before it
returns. As the left operand of an OR list it also suspends `errexit` inside the
check and inside everything the check calls, so a command that fails part way
through one of them cannot end the run.

The cost is that no check may lean on `errexit` for its own correctness. Every
one of them tests what it runs.

## What "stale" means

The issue asked for "stale or missing generated output" and did not define the
word. This is the definition the command implements:

> The generated output is **stale** when a fresh render of the active theme —
> from the templates, the palette, the machine facts and the knobs this machine
> holds right now — does not match the tree the stable path points at, file for
> file and byte for byte.

So the doctor renders the whole tree again into a temporary directory and
compares the two, and it reports every file that differs by name:

```
generated output
  problem   the generated output is stale: 1 missing, 1 different, 0 that no render produces
            missing: ghostty/colors.conf
            differs: waybar/colors.css
```

Three words, because they are three different faults:

| Word                     | What it means                                                       |
| ------------------------ | -------------------------------------------------------------------- |
| `missing`                | A fresh render produces the file and the live output does not hold it. |
| `differs`                | Both hold it and the bytes are not the same.                         |
| `no render produces it`  | The live output holds a file no render produces.                     |

This costs what a theme switch costs, and that is the price of the definition.
It was chosen over two cheaper answers:

- **Comparing modification times** is cheap and wrong in both directions. A
  `git pull` restamps every template, so every pull would read as stale until
  the next render. Worse, a generated file somebody edited by hand gets a
  *newer* time than its inputs and reads as fresh, which is the fault this check
  most needs to catch.
- **Recording a fingerprint of the inputs inside each build** is cheap at check
  time, and it reports nothing at all for a build made before the fingerprint
  existed. It also puts a new file inside the build directory, which is
  `lib/theme.sh`'s to define.

The definition chosen needs no state of its own, works against a build made by
any earlier version of this project, and catches a hand-edited output file as
well as one whose inputs have moved on.

### What this definition cannot detect

The check compares files against files. Stating what that leaves out matters,
because a check whose name promises more than it delivers is worse than no
check at all.

1. **Machine facts that no longer describe the machine.** If a monitor was
   replaced and `xghost machine detect` was never run again, the output still
   matches the facts file and the facts file is what is wrong. The doctor
   reports the output as healthy. It prints the facts summary beside it so a
   reader can see what the render was built from, and that is the whole of the
   help it gives here.
2. **A component still running with the previous configuration.** The files on
   disk can be current while Hyprland, the bar or the notification centre are
   still holding what they read at start. Nothing in this report asks a running
   program what it has in memory.
3. **Which input moved.** The report says a file differs. It does not say
   whether a template, the palette, a machine fact or a knob is the reason.
4. **Anything at all, when the render fails.** A machine whose facts file is
   missing or broken cannot be rendered, so there is nothing to compare against.
   The doctor reports `not checked` with the reason and never reports the
   output as healthy.
5. **A background image that is the same picture in different bytes.** The
   pixels of a PNG travel in a compressed stream, and another version of zlib
   packs the same pixels into slightly different bytes;
   [`docs/backgrounds.md`](backgrounds.md) records that limit. The doctor
   renders on the machine it is reporting on, so both sides use the same zlib
   and this cannot bite within one run. It can bite across a zlib upgrade: an
   output rendered before the upgrade may be reported as differing at
   `hypr/background.png` when the picture is unchanged. Running `xghost theme
   set` clears it.
6. **A theme that is not installed.** If the active theme is no longer in
   `themes/`, there is nothing to render, and the doctor says so rather than
   comparing against nothing.

### One coupling worth knowing about

A switch takes two steps: the renderer builds the tree, and `lib/theme.sh`
writes `hypr/wallpaper.conf` into it, because the path inside that file is the
stable path of the generated output and only that module knows it. The doctor
takes the same two steps, so that a healthy installation is not reported as
holding a file no render produces.

**A third step added to `theme_set_locked` has to be added to
`doctor_generated_body` as well.** Without it every installation would be
reported as stale.

## The version

**This project ships no version number and no release process.** There is
nothing a release would define for the doctor to print.

What is true about a checkout is which commit it is on and whether it carries
work of its own, so that is what the report prints:

```
git describe --tags --always --dirty
```

With no tags in the repository this is the short commit, and `-dirty` when a
tracked file has been changed. A number such as `1.0.0` would be an invention,
and it would tell a reader that releases exist for them to compare their machine
against. If this project ever tags a release, this line starts printing the tag
and nothing here has to change.

Two limits of that line:

- `-dirty` reads tracked files only. A file that is not tracked at all does not
  make a checkout dirty. An untracked file **under the prescribed directory** is
  reported by the prescribed configuration check instead, by path.
- A checkout that is not a git working tree has no version to read, and that is
  reported as a problem rather than filled in with a guess.

## A modified prescribed file

A prescribed file belongs to the project and is symbolically linked out of the
checkout, so "modified" is a question about the working tree of that checkout
and not about the config directory: the file the desktop reads *is* the file git
is tracking. `git status` over the prescribed directory answers it, and it
answers the same way whether the edit was made in the checkout or through the
link.

```
prescribed configuration
  problem   modified: /home/ada/.local/share/xghost/config/ghostty/config
```

The pathspec is the prescribed directory alone. **A change anywhere else in the
checkout is not a prescribed file and is not reported here** — the `-dirty` of
the version line is what says the checkout carries work of its own.

Two states are reported rather than guessed at:

- **The checkout is not a git working tree.** Nothing can be said about a
  modified prescribed file, so the check reports `not checked` and counts it as
  a problem. Reporting that nothing is modified would be the one answer that is
  never safe to give.
- **The checkout is dirty for a reason that is not a prescribed file.** The
  pathspec excludes it, so this check stays `ok`, and the version line still
  says `-dirty`.

## The dependencies

`install/packages/base.txt` is the manifest, and it is read with the same
function the packaging step of the installer reads it with, so the two can never
drift.

`install/packages/aur.txt` beside it is **not** read here. A machine with no AUR
helper finishes its installation without those packages and is told so at the
time, so reporting them as missing would report a state the installer produces
on purpose. If that becomes worth reporting it is a section of its own, with its
own words.

### The query is injected

Asking the package manager directly would make this command untestable: a test
would have to query the real database of whoever runs the suite, which answers
differently on every machine.

`XGHOST_DOCTOR_PACKAGE_QUERY` names a program. It is called with every declared
package name as an argument, it prints the names that are not installed one per
line, and it ends 0 when it answered. With the variable unset, `pacman -T`
answers through `install_missing_packages`.

**A query that could not answer is reported as `not checked`, never as nothing
missing.** A machine with no pacman is a machine that cannot say, and telling a
user their dependencies are in place on such a machine would be a false report.

## The links

`lib/linker.sh` keeps a record of every link this project created, and the
doctor reads it. A link can be wrong in four ways, and they are four different
faults, so each has its own words:

| Word               | What it means                                                             |
| ------------------ | --------------------------------------------------------------------------- |
| `missing`          | Nothing is at the path at all.                                              |
| `not a link`       | Something else is at the path — a regular file, or a directory.             |
| `points elsewhere` | The link is there and points at something other than the prescribed entry.  |
| `the target is gone` | The link is right and the file it points at is not there.                 |
| `not linked`       | A prescribed entry, or the bridge, that the record does not mention at all. |

`not linked` is the one the record cannot answer on its own, because the record
holds what the linker created and not what it should have created. So the
prescribed directory is read beside it, and the bridge to the generated output
is checked by name: no prescribed entry stands behind the bridge, and every
relative include of this project resolves through it, so a check that read the
prescribed directory alone would never look at the one link whose absence makes
every include miss in silence.

## What this command is not

It reports. It repairs nothing. Every problem it names carries the command that
fixes it, and a person runs that command.

It also does not report on the migration state. A migration that has not run is
a system change that has not happened, and it is `xghost system update` that
reports it.
