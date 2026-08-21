# Machine facts

Machine facts are what is physically true about one computer: its monitors,
its keyboard layout, its timezone, its display scale, its input devices, and
its default browser and terminal.

They are one file. Detection writes it, you own it, and the renderer reads it
beside the theme palette. That file is what keeps a monitor name out of the
prescribed configuration, so the same prescribed files fit every machine.

```
xghost machine detect      # read this computer and write the file
```

Machine facts are the second file category of
[ADR 0001](adr/0001-prescribed-config-architecture.md).

## Where the file lives

```
$XDG_CONFIG_HOME/xghost/machine.conf
```

`XDG_CONFIG_HOME` defaults to `~/.config`, so the usual path is
`~/.config/xghost/machine.conf`.

The file is in your config directory, not in the checkout. An update replaces
the checkout and never writes to your config directory, so your machine facts
survive every update untouched.

Three variables move the path, and the first one that is set wins:

| Variable               | What it names                               |
| ---------------------- | ------------------------------------------- |
| `XGHOST_MACHINE_FACTS` | The file itself. The tests use this.        |
| `XGHOST_CONFIG_HOME`   | Your config directory.                      |
| `XDG_CONFIG_HOME`      | The same directory, per the XDG base directory specification. |

## Detection replaces the file, and you may still edit it

Two rules pull against each other, and ADR 0001 states both:

- Detection **replaces the whole file**. It never patches it and never merges
  into it.
- You **correct a wrong detection by editing that file**.

The resolution is an order of precedence, and the file states it in its own
header, so a reader of the file never has to find this page:

1. Your edit survives every `xghost system update`. An update writes to the
   checkout, and the checkout is not where this file is.
2. Your edit does **not** survive the next `xghost machine detect`. That run
   writes the whole file again from what it reads on the machine.
3. Before it replaces the file, that run copies the file to
   `machine.conf.previous`. A correction you lose that way is still on disk,
   and the command prints the path of the copy.

The copy is not a merge. Detection still writes every line. The copy exists so
that replacing a hand-written correction is reversible.

## A fact whose source did not answer keeps its value

Detection reads exactly one thing from the file it is about to replace: the
value of a fact that this run could not read at all.

`hyprctl` answers only inside a running Hyprland session. The same computer
therefore answers with two monitors during a session and with nothing over ssh,
and a run that recorded `unknown` there would replace a monitor layout that was
read correctly with the fallback one. The copy at `machine.conf.previous` would
then be the only record of the layout, and the next run would overwrite that
copy in turn.

The rule that prevents it:

> A fact whose source did not answer this run keeps the value the previous run
> wrote for it. A fact whose source did answer is written from that answer,
> always.

What follows from it:

- A run over ssh, at a virtual console, or from a session that has just crashed
  keeps the monitors, the input devices and the compositor of the last run that
  could read them.
- Every fact that was kept is named on standard error, in one line. Nothing is
  kept in silence.
- A run that keeps every fact writes the file it was already holding, byte for
  byte, so it makes no `machine.conf.previous` copy at all. The undo of your own
  edit stays the undo of your own edit.
- A value that carries forward may be one you edited by hand, because this file
  is the only record of what was last true. The next run whose source does
  answer replaces it.
- Nothing carries forward from a file the reader does not accept, such as one
  that declares another format version. The run says so and records `unknown`.
- A machine that has never been read has nothing to carry forward, so a first
  detection records `unknown` exactly as it always did.

A run that writes exactly the file that is already there makes no copy, and
prints no copy. Such a copy would carry nothing, and it would replace one that
carries your correction. Without that rule, a detection you run twice with no
edit between the two runs would leave a backup of the auto-detected file, and
your correction would be gone.

The consequence to keep in mind: run `xghost machine detect` after you change
your hardware, and expect to make your corrections again.

## The format

The file is a data file, not a script. The reader reads it line by line and
never sources it, so a machine facts file can never run code.

```
# A comment starts with a hash. An empty line is allowed.

MACHINE_FACTS_VERSION=1
MACHINE_MONITOR_1_NAME=DP-2
MACHINE_MONITOR_1_DESCRIPTION=LG Electronics LG ULTRAGEAR+ 304NTNH6H847
```

The rules:

- One `KEY=value` pair per line.
- Every key starts with `MACHINE_`, and then holds upper case letters, digits
  and underscores. The prefix is what keeps a machine fact and a theme colour
  in two namespaces.
- A key may be given once.
- A value is never empty. Write `none` or `unknown` instead, and read the next
  section for the difference.
- A value may carry one pair of quotation marks, single or double, which the
  reader drops. Quote a value that starts or ends with a space.
- The white space at both ends of a name and of a value is dropped.
- A value holds no control character. It is one line of plain text, so a tab
  inside a value is named as a problem rather than passed on to the renderer.
- A value is text. The reader never expands a variable and never runs a command
  in it.
- `MACHINE_FACTS_VERSION` is required, and this version of xghost reads
  version `1`. A file that declares another version is named rather than read
  as though it were this one.

The reader reports every problem of one file, not only the first.

## The two values that are not facts

| Value     | What it means                                                     |
| --------- | ------------------------------------------------------------------ |
| `unknown` | Detection could not read the source of this fact.                  |
| `none`    | The source answered, and its answer was that nothing is set.       |

Detection never invents a plausible value. A machine with no Hyprland running
and no monitor ever read records `MACHINE_MONITOR_COUNT=unknown` and no monitor
block, because a wrong monitor layout presented as fact is worse than an absent
one. A machine whose monitors were read by an earlier run keeps what that run
read, and the section above states that rule in full. A machine whose keyboard
has no variant records `MACHINE_KEYBOARD_VARIANT=none`, because the system
answered and its answer was "nothing".

The renderer never writes `unknown` into a configuration file. A template that
names a fact of that value fails the render and reports the file and the name,
so the word cannot reach a `monitor =` line as though it were a mode. That
holds however the value got there, including your own edit of this file. A
structural choice still selects on it, because selecting a whole prescribed
fragment is what `default` is for.

A source that answers with the JSON value `null` has answered that the member
has no value, so that fact is `unknown` and the run reports it. The word is
never written into the file: `MACHINE_MONITOR_1_NAME=null` would reach a
rendered `monitor =` line as though the compositor had reported a monitor of
that name. A monitor whose name really is the string `"null"` is a name, and it
is recorded as one.

Every key keeps its place whatever the machine can answer, so the file is well
formed on a machine with no Hyprland, no systemd and no `xdg-utils`.

## The keys

### The file itself

| Key                     | Value                                      |
| ----------------------- | ------------------------------------------ |
| `MACHINE_FACTS_VERSION` | The version of this format. `1` today.     |

### Displays

| Key                       | Value                                                 |
| ------------------------- | ----------------------------------------------------- |
| `MACHINE_COMPOSITOR`      | `hyprland`, or `unknown` when no compositor answered. |
| `MACHINE_MONITOR_COUNT`   | The number of monitors.                               |
| `MACHINE_PRIMARY_MONITOR` | The name of the focused monitor, and of the first monitor when none is focused. |
| `MACHINE_PRIMARY_SCALE`   | The display scale of that monitor.                    |

Then one block per monitor, numbered from 1 in the order the compositor reports
them. `N` is the number of the monitor.

| Key                            | Value                                          |
| ------------------------------ | ---------------------------------------------- |
| `MACHINE_MONITOR_N_NAME`        | The connector name, such as `DP-2`.           |
| `MACHINE_MONITOR_N_DESCRIPTION` | The make, the model and the serial number.    |
| `MACHINE_MONITOR_N_WIDTH`       | The width in pixels.                          |
| `MACHINE_MONITOR_N_HEIGHT`      | The height in pixels.                         |
| `MACHINE_MONITOR_N_REFRESH`     | The refresh rate in hertz.                    |
| `MACHINE_MONITOR_N_X`           | The x position of the monitor in the layout.  |
| `MACHINE_MONITOR_N_Y`           | The y position of the monitor in the layout.  |
| `MACHINE_MONITOR_N_SCALE`       | The display scale.                            |
| `MACHINE_MONITOR_N_TRANSFORM`   | The rotation, as Hyprland numbers it.         |
| `MACHINE_MONITOR_N_FOCUSED`     | `yes` or `no`.                                |
| `MACHINE_MONITOR_N_MODE`        | `WIDTHxHEIGHT@REFRESH`, the mode a Hyprland monitor line takes. |
| `MACHINE_MONITOR_N_POSITION`    | `XxY`, the position a Hyprland monitor line takes. |

`MODE` and `POSITION` are the same facts in the form a `monitor =` line needs,
so a template writes one placeholder rather than joining three.

### Time and keyboard

| Key                             | Value                                                  |
| ------------------------------- | ------------------------------------------------------ |
| `MACHINE_TIMEZONE`              | The timezone, such as `US/Pacific`.                    |
| `MACHINE_KEYBOARD_LAYOUT`       | The keyboard layout of the system, such as `us`.       |
| `MACHINE_KEYBOARD_VARIANT`      | The layout variant of the system.                      |
| `MACHINE_KEYBOARD_MODEL`        | The keyboard model of the system.                      |
| `MACHINE_KEYBOARD_OPTIONS`      | The xkb options of the system.                         |
| `MACHINE_COMPOSITOR_KB_LAYOUT`  | The layout Hyprland is using now.                      |
| `MACHINE_COMPOSITOR_KB_VARIANT` | The variant Hyprland is using now.                     |

The layout of the system and the layout of the compositor are two facts,
because a session started by hand may use a layout the system does not declare.
`MACHINE_KEYBOARD_LAYOUT` reads the X11 layout of `localectl`, then its console
keymap, then the layout of the compositor. It is `unknown` only when no source
answered.

### Input devices

| Key                             | Value                                                  |
| ------------------------------- | ------------------------------------------------------ |
| `MACHINE_KEYBOARD_DEVICE_COUNT` | The number of keyboards.                               |
| `MACHINE_KEYBOARD_DEVICE_MAIN`  | The name of the main keyboard.                         |
| `MACHINE_KEYBOARD_DEVICE_N_NAME`   | The name of one keyboard.                           |
| `MACHINE_KEYBOARD_DEVICE_N_LAYOUT` | The layout of that keyboard.                        |
| `MACHINE_POINTER_COUNT`         | The number of pointers.                                |
| `MACHINE_POINTER_N_NAME`        | The name of one pointer.                               |
| `MACHINE_TOUCHPAD_COUNT`        | The number of touchpads.                               |
| `MACHINE_TOUCHPAD_N_NAME`       | The name of one touchpad.                              |
| `MACHINE_TOUCHSCREEN_COUNT`     | The number of touch screens.                           |
| `MACHINE_TABLET_COUNT`          | The number of graphics tablets.                        |
| `MACHINE_SWITCH_COUNT`          | The number of switches, such as a laptop lid.          |
| `MACHINE_SWITCH_N_NAME`         | The name of one switch.                                |

The name of a device is the name a per-device Hyprland input rule is written
against, so a template can name one touchpad exactly.

Hyprland lists every pointer under `mice`, so a pointer whose name holds
`touchpad` or `trackpad` is counted as a touchpad. That is the same name a
Hyprland `device` block uses for one.

### Default applications

| Key                | Value                                                   |
| ------------------ | -------------------------------------------------------- |
| `MACHINE_BROWSER`  | The desktop entry of the default browser.                |
| `MACHINE_TERMINAL` | The default terminal.                                    |

## Where each fact comes from

| Fact                       | Source                              | Program        |
| -------------------------- | ----------------------------------- | -------------- |
| Monitors and display scale | `hyprctl monitors -j`               | Hyprland       |
| Input devices              | `hyprctl devices -j`                | Hyprland       |
| Keyboard of the compositor | `hyprctl getoption input:kb_layout -j` | Hyprland    |
| Keyboard of the system     | `localectl status`                  | systemd        |
| Timezone                   | `timedatectl show -p Timezone --value`, then the link `/etc/localtime` | systemd, the C library |
| Default browser            | `xdg-settings get default-web-browser` | xdg-utils   |
| Default terminal           | `TERMINAL`, then `xdg-terminals.list` | the environment |

Every program is already required by xghost. Detection adds no dependency, and
it reads a JSON answer with a reader written in bash, so it needs no `jq`.

Detection reads only. It changes no system setting, it needs no root, and it
runs the same way twice.

`TERM` is not a source for the terminal. It names the terminal the run is
printing to, which during an installation is a virtual console rather than the
terminal the desktop will use.

## When a source is missing

The run does not fail. It records `unknown` for every fact of that source,
keeps the file well formed, and names on standard error each source it could
not read. Each missing program is named once.

```
$ xghost machine detect
xghost: the 'hyprctl' program is not installed, so the monitor layout is not known
the machine facts are at /home/ada/.config/xghost/machine.conf
edit that file to correct a detection. The next detection replaces it.
```

A template that names a fact detection could not read fails the render and
names the value it wanted. That is the intended behaviour: the desktop reports
a missing fact rather than coming up with a monitor layout that was guessed.
A fact that is present with the value `unknown` fails the same way, and for the
same reason.

| Exit code | Meaning                                                       |
| --------- | -------------------------------------------------------------- |
| 0         | The file was written. A source that is missing is still a 0.  |
| 1         | The file has no home, or it could not be written.             |
| 2         | The command was given an argument.                            |

## How the renderer reads the file

The renderer takes three inputs: the theme palette, the machine facts, and the
knobs. It reads the machine facts file as a second table of values, so a
template names a fact the same way it names a colour:

```
monitor = @MACHINE_MONITOR_1_NAME@,@MACHINE_MONITOR_1_MODE@,@MACHINE_MONITOR_1_POSITION@,@MACHINE_MONITOR_1_SCALE@
```

A fact also picks between whole files. A directory named
`<file>.choice.<NAME>` holds one prescribed fragment per value of `NAME`, and
the renderer writes the one the fact selects. That is how the Hyprland monitor
layout carries one line per monitor without the renderer growing a loop:

```
templates/hypr/monitors.conf.choice.MACHINE_MONITOR_COUNT/
  1  2  3  default
```

[Theming](theming.md) documents the rules, and
[the Hyprland bundle](bundles/hyprland.md) documents the case.

`xghost theme set` passes the file when it exists. A machine that has not run
detection renders with the palette alone, and a template that names a fact
fails the render by name. A structural choice fails the same way, so
`xghost machine detect` has to run before the first `xghost theme set`.

A name the palette and the machine facts both declare is a problem the renderer
reports. The two files have two owners, so preferring either one quietly would
make the output depend on a rule nobody wrote down. The same answer covers the
third input: a knob starts with `KNOB_`, so a knob and a machine fact can never
collide, and a palette that declares either name is refused. Read
[Knobs](knobs.md) for that file, and [Theming](theming.md) for the rest of the
renderer.

## Detection during an installation

The installer runs detection twice, and [Installing](installing.md) records the
order it chose. This is the contract it is wired up to.

An installation step runs one command:

```
xghost machine detect
```

What the step may rely on:

- **It needs no root.** It writes one file in the user's config directory. Run
  it as the user who will use the desktop, never under `sudo`.
- **It is idempotent.** Running it twice writes the same file, so a failed
  installation is resumed by running the step again.
- **It reads only.** It changes no system setting.
- **A missing source is not a failure.** It exits 0 and records `unknown`, so
  the step does not stop an installation on a machine it cannot fully read.
  It exits 1 only when it cannot write the file.
- **It reports on standard error.** Every source it could not read is one line.

One ordering rule matters, and it is the reason a monitor layout can still be
wrong at first login:

> `hyprctl` answers only inside a running Hyprland session. A step that runs
> before the session starts records `MACHINE_MONITOR_COUNT=unknown`, unless a
> run inside a session read the monitors already.

[Repository layout](repository-layout.md) puts detection in
`install/steps/config/`, and that step is correct for every fact except the
monitors. To make the monitors correct, the installer has to run detection again
**inside a Hyprland session**.

The installer runs it at the start of the session itself: the prescribed
autostart carries `exec-once = xghost machine refresh`, which runs detection
again and renders the active theme from what it read. A step under
`install/steps/post-install/` was the other candidate and cannot work, because
the installer finishes before any session exists. The cost is that the
prescribed monitor layout is in place from the second login, and
[Installing](installing.md) records it.

Running detection twice is safe, because the second run writes the same file
from a machine it can now read fully. It is safe to run at every login as well:
a run that changes nothing makes no copy, so `machine.conf.previous` still
holds the file that was replaced the last time something did change.

It is safe in the other direction too, and that is the whole of the safety
claim rather than half of it. A `machine refresh` that runs when `hyprctl` is
not answering — the compositor is still starting, or the installation is being
run again from a terminal — keeps the monitors of the last run that could read
them. Nothing about this order depends on every run reading the machine fully.

The facts that need no compositor — the timezone, the keyboard layout of the
system, the default browser — are correct whenever the step runs.

## The tests

`tests/machine.bats` covers detection, and `tests/json.bats` and
`tests/facts.bats` cover the two pure modules behind it.

Detection reads the machine it runs on, so it gets smoke tests: enough to prove
that it runs, that it writes the file, and that the file is well formed.
Testing it more deeply would mean standing a fake Hyprland up, and a test of a
fake proves the fake.

The parsing is another matter. Every function that turns the answer of a source
into facts is pure, and each one is tested against fixture text under
`tests/fixtures/detect`. No test depends on the hardware of the machine that
runs it, and one test proves that a machine with none of the four programs
still gets a well-formed file.
