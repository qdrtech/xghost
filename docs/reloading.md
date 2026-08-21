# Reloading

A theme switch and a knob change both end by writing a whole new tree of
configuration files and moving it into place. Nothing has read any of them. The
reload is the step that asks the running desktop to.

`lib/reload.sh` owns it. One table, one driver, three callers.

## Ask whether it is running, then tell it

Every component is reloaded in two steps, and the order of the two is the whole
design:

1. Ask whether a process of that name belongs to this user. `pgrep` answers, and
   it changes nothing.
2. Only then run the command that tells that process to read its configuration
   again.

Asking first is not a tidiness. Three faults follow from telling first, and this
project met all three.

**It cannot tell a component that is absent from one that refused.** The table
this replaced ran `hyprctl reload` and read any non-zero status as
`not running`:

```bash
if hyprctl reload >/dev/null 2>&1; then
    printf 'reloaded\n'
else
    printf 'not running\n'
fi
```

A compositor that **is** running and whose reload was **refused** is the one
outcome worth acting on, and it was the one outcome that code could not report.

**It can start a daemon nobody started.** The `swaync` package ships
`/usr/share/dbus-1/services/org.erikreider.swaync.cc.service`, which names
`Exec=/usr/bin/swaync`. That D-Bus name is activatable, so `swaync-client -rs`
on a session with no notification daemon does not fail: the bus starts one. A
reload that installs a daemon is not a reload.

**It can hang.** `swaync-client` waits for the daemon by default. The option
that turns the wait off is `-sw`, and it cannot be combined with `-rs`:
`swaync-client` takes one option per run, which its usage line (`<OPTION>`,
singular) says and which the unit the package ships confirms, because that unit
runs `--reload-config` and `--reload-css` as two separate commands. The probe is
what keeps the wait from ever starting.

## The four answers

| Answer | What it means | A problem? |
| ------------- | ---------------------------------------------------------- | --- |
| `reloaded` | The process was there and the command succeeded. | No |
| `not running` | No process of that name belongs to this user. | No |
| `no command` | The process **is** there and the program that reloads it is not installed. | Yes |
| `failed` | The process is there, the command ran, and it returned non-zero. | Yes |

`not running` is not a problem, because a desktop that is not running cannot be
shown anything. That is acceptance criterion 7 of
[issue #24](https://github.com/qdrtech/xghost/issues/24).

`no command` **is** a problem, and that is a change. The old code returned
success for it, on the reasoning that a component this machine does not have is
not a failed update. With the probe, that reading no longer holds: the branch is
only ever reached for a component that is **running**, so it means the change
will not be seen and nothing else would say so.

`failed` carries the exit status and the first line of the standard error of the
command, so the report names the cause rather than the fact.

### The race between the two steps

A component can go away between the probe and the signal. `pkill` then ends with
1, which means "matched nothing", and reading that as a refusal would be wrong.
So a command that failed is followed by a **second** probe: a process that is
gone is `not running`, and a process that is still there is `failed`.

This is why `pkill` needs no rule of its own, and why the two mechanisms do not
need to be told apart by hand. The distinction is the same for every component,
and it is made by the probe rather than by the exit code of whatever was run.

## Every component is independent

`reload_all` runs each component as the left operand of an OR list. As in
[the doctor](doctor.md), that is a design rather than a swallowed error:

- Errexit is suspended inside `reload_one` and inside everything it calls, so a
  component that fails cannot end the run and cannot stop the components after
  it.
- `RELOAD_PROBLEMS` is what the exit status is built from, not the status of the
  last thing that ran.

That is acceptance criterion 8: one failure does not stop the rest.

## The components

| Component | Process | Program | Command | What it reloads |
| --------- | ---------- | --------------- | ---------------------------- | ---------------- |
| `hyprland` | `Hyprland` | `hyprctl` | `hyprctl reload` | The configuration and the monitors. |
| `waybar` | `waybar` | `pkill` | `pkill -SIGUSR2 -x -u <uid> waybar` | Every bar of the process: the configuration and the style sheet. |
| `swaync` | `swaync` | `swaync-client` | `swaync-client -rs` | The style sheet. |
| `ghostty` | `ghostty` | `pkill` | `pkill -SIGUSR2 -x -u <uid> ghostty` | The configuration, in every window. |

The compositor is first because its reload is the one that can change the
geometry every other surface is drawn into. The order of the rest does not
matter, and it is fixed so that two runs produce the same report.

`-u <uid>` is on the probe **and** on the signal for one reason: the two have to
ask about the same set of processes. Without it the probe finds the bar of this
user and `pkill` reaches the bar of every user on the machine, so the answer
would describe one thing and the action would reach another.

`pgrep` and `pkill` both ship in `procps-ng`, which is a dependency of the Arch
`base` package. No manifest of this project declares it, and none needs to.

### Waybar: `SIGUSR2`, and not `SIGRTMIN+8`

Both are signals Waybar accepts. They do not mean the same thing, and `waybar(5)`
says which is which:

- **`SIGUSR2`** runs the action of `on-sigusr2`, whose default is `reload`, which
  "reloads all waybars of current waybar process (basically equivalent to
  restarting with updated config)". That is the configuration and the style sheet
  together, which is what a theme change and a knob change both write.
- **`SIGRTMIN+N`** refreshes the one module whose `signal` key is `N`. In
  `config/waybar/config` the only such module is `custom/pacman`, with
  `"signal": 8`, and its `exec` is `checkupdates`, which runs a package database
  synchronisation over the network. Sending it after a theme switch would reach
  the Arch mirrors and change no colour at all.

`config/waybar/config` does not set `on-sigusr2`, so the default applies.

### SwayNC: the style sheet, and not the configuration

`swaync-client -rs` reloads the CSS. That is the whole of what a theme change and
a knob change need, and the reason is in
[the SwayNC bundle](bundles/swaync.md): `config.json` is a **prescribed** file,
and no key of it follows a palette, a knob or a machine fact. The two settings
that would follow an input are pinned by hand, and that page records why.

So `swaync-client -R` is not sent. A change to the prescribed `config.json`
arrives by a `git pull` rather than by a render, and the daemon reads that file
when it starts. That is a gap, it is small, and it is written down here rather
than closed by a second call whose only job would be to look thorough.

### Ghostty: `SIGUSR2`

Read out of the program rather than out of anybody's memory. Ghostty 1.3.1 has
this in the binary the `ghostty` package installs:

```
info(gtk_ghostty_application): received SIGUSR2, reloading configuration
```

`ghostty(5)` names exactly one setting that cannot be reloaded at run time, and
it is the interface language. Nothing this project generates is on that list:
`templates/ghostty/colors.conf` writes `background`, `foreground`,
`cursor-color`, the two selection colours and the sixteen palette slots, and
`templates/ghostty/font.conf` writes `font-family`, which that page describes
being picked up "on reload".

## The three that need no signal

A component that needs nothing is a legitimate answer, and inventing a signal
that does nothing is not. Each of these was checked rather than assumed.

**Rofi needs nothing.** The launcher is started per invocation. `rofi -show drun`
is what `SUPER + space` runs, and it reads its theme when it starts, so the next
launcher after a theme switch is already the new one. There is no running
process to tell. [The Rofi bundle](bundles/rofi.md) records how the theme
reaches it.

**The shell prompt needs nothing, and this was measured.** The prompt is Starship,
and `config/zsh/.zshrc` exports `STARSHIP_CONFIG` at the bridge, so the path is
stable across a switch. Starship is a program the shell runs for **every prompt**,
and it reads that file every time. Measured on Starship 1.26.0, in one process,
with the file swapped underneath it and nothing signalled:

```
starship prompt  ->  AAA
(the config file is replaced)
starship prompt  ->  BBB
```

So a shell that was already open picks up a theme change at its next prompt.
Acceptance criterion 5 allows this to be a documented limitation; it turns out
not to be one.

**GTK applications need something this project cannot send.** A GTK application
reads its style sheet when it starts. The two GTK surfaces of this desktop that
**can** be told otherwise are the bar and the notification centre, and both are
in the table above with a signal of their own. Everything else, which is every
ordinary GTK 3 and libadwaita window, shows the new colours the next time it
starts. [The supporting bundle](bundles/supporting.md) records the mechanism, and
there is no general one: GTK offers no signal, and a per-application route would
be a per-application design.

### hyprpaper is not in the table, and that needs an issue

[The Hyprland bundle](bundles/hyprland.md) sets `ipc = on` in `hyprpaper.conf`
for this issue, so that a theme switch could reload the wallpaper of the running
daemon. **The request that would do it does not exist in the version this project
installs.**

`hyprctl` 0.56.2 offers exactly one hyprpaper request, and its own usage text is
the evidence:

```
usage: hyprctl [flags] hyprpaper <request>
requests:
    wallpaper       Issue a wallpaper to call a config wallpaper dynamically.
                    Arguments are [mon],[path],[fit_mode].
```

There is no `reload`. This is the same version fault that page already found for
`preload`: the verbs it was written against are hyprpaper 0.7 verbs, and the
installed hyprpaper is 0.8.4.

The one request that does exist cannot be used as a reload without work this
issue does not own. The wallpaper of every theme is written to the **same**
stable path, so `wallpaper ,<path>` names a path that did not change, and whether
the daemon reads the file again or returns without doing anything was not
measured here: measuring it means changing the wallpaper of a live session.
Sending it anyway would be inventing a signal that may do nothing, which is the
thing this page refuses to do for Rofi.

So the wallpaper of a running session does not follow a theme switch today. It
follows on the next login. **This needs its own issue**, and that issue owns two
questions: whether `hyprctl hyprpaper wallpaper` reloads a path that is
unchanged, and where the `fit_mode` comes from, which today is a key of the
generated `hypr/wallpaper.conf` and would have to be parsed back out of it.

## Where the reload is called from

It is **automatic**. A theme change that needs a second command is a theme change
nobody sees, and that is acceptance criteria 1 and 2.

| Caller | When | What its exit status is |
| ------------------------ | ------------------------------------ | ---------------------- |
| `xghost theme set` | After the new tree is moved into place | The theme switch |
| `xghost settings set` | After the render that follows the knob | The knob and the render |
| `xghost system update` | Step 6, after the render | The whole update |
| `xghost system reload` | Immediately | The reload |

The reload never runs when the render did not succeed. A failed render leaves
the previous theme in place, whole, so telling the desktop to read its
configuration again would show the theme it is already showing and report a
reload of a change that never happened.

### Why a failed reload does not fail `xghost theme set`

The theme **is** set. The generated output **is** in place, and every program
started after that point reads it. A component that did not take the message is
named on standard error, and it does not turn a switch that worked into a
command that failed.

`xghost system reload` is the command whose exit status **is** the reload, and it
is the one to run again once the cause is fixed. `xghost system update` counts a
failed reload like any other step that reported a problem, which is the
convention that file already had.

## The switch

`XGHOST_RELOAD=no` turns the reload off. It is reported on the line where the
components would have been, so a run with it set never reads like a run that
found nothing to do.

Only `yes` and `no` are values. Any other value is reported and the reload does
**not** run, which is the conservative half: a value nobody meant to write stops
a signal rather than sending one.

It exists for two reasons, and the second one is the load-bearing one.

- **A run that renders for a session other than the one it is in.** Provisioning
  a machine over ssh, for instance.
- **The test suite.** Every suite of this project renders a theme, and the reload
  is now what a render ends with, so without a switch the suite of a machine that
  runs this desktop would reload that desktop, once per test.
  `tests/setup_suite.bash` sets it for the whole suite, and the two suites that
  mean to exercise the reload turn it back on **after** putting a stub of every
  program it can reach first on the PATH.

## Adding a component

One row of `RELOAD_COMPONENTS` in `lib/reload.sh`, and one row of the table
above. There is no second list, no `case` statement and no per-component
function.

```bash
"fictional|fictionald|fictionalctl|fictionalctl reload"
```

The fields are the name the report uses, the process name exactly as the kernel
holds it, the program that must be installed, and the command.

Three rules the fields keep, each one measured rather than assumed:

- **No field may be empty.** `pgrep` with no pattern at all matches every process
  of the user, so an empty process field would report every component as running
  and the matching `pkill` would signal the whole session. Such a row is refused
  by name rather than run.
- **A process name is at most 15 characters.** That is the length the kernel
  keeps, and `pgrep -x` on a longer one matches nothing and says so on standard
  error. Such a row is refused here instead.
- **No argument of the command may hold a space.** The command is split on white
  space. No component needs one today.

`tests/reload.bats` proves the one-file claim rather than asserting it: it copies
the checkout, adds one row for a fictional component, reloads it, and then runs
`diff -r` between the checkout and the copy and requires the list of files that
differ to be exactly `lib/reload.sh`. That is acceptance criterion 9.

## What the tests prove

- `tests/reload.bats` proves the module and the three commands that call it,
  against a stub `pgrep`, `pkill`, `hyprctl` and `swaync-client`. The stub
  `pgrep` is what makes "the bar is running" a fact of the test rather than of
  the machine. `assert_stubs_are_first` runs in `setup`, before any test body, so
  a PATH that does not resolve to the stub fails the test there instead of
  reaching a live session.
- `tests/update.bats` proves the reload as step 6 of an update: that it runs
  after the render, that a component which is not running is skipped and the
  update still ends well, that a component which is running and refused makes the
  update end non-zero, and that the three components after a failed one are
  still reloaded.
- `tests/negative-control` breaks each guard on purpose and requires a named test
  to fail: the probe removed, the second probe removed, the exact status of the
  probe replaced by a plain test of success, the row check removed, the switch
  removed, the backstop behind the switch removed, the run stopped at the first
  failure, the bar sent `SIGRTMIN+8`, the compositor moved out of first place, a
  failed render reloading anyway, and a failed reload left uncounted by the
  update.

## What has never been observed

**No component of a running desktop has ever been seen picking a change up.**
The machine this was written on runs a live Hyprland, a live bar, a live
notification centre and a live terminal, and every one of them is the session of
the person writing it. Reloading any of them to watch it work is the one thing
this module may not do while it is being built.

What that leaves proved, and how:

| Claim | How it is known |
| ------------------------------------------------ | ------------------ |
| The right signal goes to the right process name, in the right order | Observed, against stubs |
| A component that is not running is never signalled | Observed, against stubs |
| A running component that refused is told apart from an absent one | Observed, against stubs |
| One failure does not stop the rest | Observed, against stubs |
| The shell prompt follows a theme switch | Measured, on Starship itself |
| `SIGUSR2` is what Ghostty reloads on | Read out of the Ghostty binary |
| `SIGUSR2` reloads the bar and `SIGRTMIN+8` does not | Read out of `waybar(5)` |
| `swaync-client -rs` reloads the style sheet | Read out of `swaync-client(1)` |
| A theme change is **visible** on a running desktop | **Reasoned, not observed** |
| A knob change is **visible** on a running desktop | **Reasoned, not observed** |
| The bar and the notification centre **draw** the new styling | **Reasoned, not observed** |
| A running Ghostty **draws** the new colours | **Reasoned, not observed** |

The last four are the same claim four times: that a component which accepted the
signal then redraws. Each rests on the documentation of the program that was
signalled, and on the generated file being where that program reads it, which
every bundle page proves separately. None of the four rests on a desktop anybody
watched change.

A first theme switch on a running session is therefore the first test of them.
