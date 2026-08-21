# Updating

One command updates this desktop:

```
xghost system update
```

It pulls the project, links the prescribed files the pull added, updates the
system packages, runs the pending migrations, renders the active theme again,
tells the running components to read their configuration again, and reports what
changed.

## Why the command is `xghost system update`

The dispatcher routes `<group> <verb>`, and a command file is named
`<group>-<verb>`. A single-word top-level command therefore has no file name, so
`xghost update` cannot be routed as the project stands.

Three ways out were weighed.

| Option                              | Cost                                                                                                                                                                                                              |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Extend the dispatcher               | A change to a merged, well-tested component. Routing, `split_command_name`, `check_entry`, grouped help, `--complete-groups`, `--complete-verbs`, `completions/_xghost` and the exit-code table all have to follow, and a new rule is needed for a top-level command and a group that carry the same name. |
| **Name it `xghost system update`**  | A user-facing name the issue did not write.                                                                                                                                                                       |
| Ship both                           | Two routes to one behaviour, which drift apart as soon as one of them gains an option.                                                                                                                            |

The second was chosen. The dispatcher is not changed at all, and the group
`system` has room for the verbs an update path grows later. The cost is one
word on a command line, paid once. The cost of the first option is paid by
everybody who reads the dispatcher afterwards, and it buys nothing a user can
see.

## What one update does, in order

| Step       | What it does                                                                            |
| ---------- | ---------------------------------------------------------------------------------------- |
| pull       | `git pull --ff-only` in the checkout.                                                    |
| link       | Link the prescribed files the pull added. A file that was already linked needs nothing.  |
| packages   | Run the AUR helper, or `sudo pacman -Syu` on a machine with no helper.                   |
| migrations | Run the migrations this machine has not applied.                                         |
| render     | Render the active theme again, from the templates the pull brought in.                   |
| reload     | Tell the running components to read their configuration again. [Reloading](reloading.md) owns the set and the mechanism of each one. |

The order is the contract. The packages come after the pull because a migration
may need a package the pull declared. The reload is last because it is what
shows the render, and there is nothing to show until the render has moved into
place. The render comes after the migrations
because a migration may remove a stale generated file.

**A failed pull stops the update.** Every step after it acts on the checkout the
pull brings in, so an update that ran them against the old checkout would report
work it did not do. A checkout that carries work of its own is not fast
forwarded, and the update says so and changes nothing else.

**Prescribed configuration arrives through the pull and needs no migration.**
The linker points the config directory of the user at the files of the checkout,
so a pull that changes a prescribed file changes what the desktop reads.

**Machine facts and knobs are never written by an update.** They belong to the
user, they live in the config directory, and every step above writes either the
checkout or the state directory.

## What the report compares

A report that always says "updated" is not a report. Each line is a comparison
of a state before the update against the state after it.

| Line         | What is compared                                                                     |
| ------------ | -------------------------------------------------------------------------------------- |
| `project`    | `git rev-parse HEAD` before against after, and the number of commits between the two. |
| `links`      | The summary line of the linker: how many were linked, adopted, backed up or in conflict. |
| `packages`   | `pacman -Q` before against after, counted as installed, upgraded or downgraded, and removed. |
| `migrations` | The migrations this run applied and the ones it skipped, by name.                     |
| `generated`  | A fingerprint of the generated output before against after: every file name, every file content, and every link target. Each build lands in a directory of its own, so the path always differs and the content is what is read. |
| `components` | What each component answered: `reloaded`, `not running`, `no command` or `failed`. [Reloading](reloading.md) records what each answer means and which two are problems. |

## The exit status

The update ends non-zero when any step reported a problem, and that **includes a
migration that was skipped**. A skipped migration is a system change that did not
happen, so an update that ended well over one would report success it did not
have.

## Writing a migration

A migration is one script in `migrations/`, named `NNNN-name.sh`. The four
digits order the run. **The file name is the identity of the migration**, so a
name that has shipped is never changed: renaming one produces a migration nobody
has applied, and every machine runs it again.

Every migration carries a metadata block:

```bash
# @xghost-migration
# summary: Drop the package the shell no longer reads.
# effect: drop-package
# @end-xghost-migration

if pacman -Qq the-package >/dev/null 2>&1; then
	sudo pacman -R --noconfirm the-package
fi
```

`summary` is required once. It is what the runner prints while the migration
runs, and what the failure report names, so it says what the migration is doing
rather than what release it belongs to.

`effect` is required at least once, and it takes one of the five effects
[ADR 0001](adr/0001-prescribed-config-architecture.md) permits:

- `install-package`
- `drop-package`
- `enable-unit`
- `set-desktop-key`
- `remove-generated-file`

**A migration must not edit a configuration file of the user.** The architecture
is built so that no such migration is needed: a prescribed file arrives through
the pull, machine facts and knobs belong to the user, and generated output is
rebuilt by the renderer. A change that still seems to need one is a change in
the wrong category.

**A migration must be safe to run twice.** The example above tests before it
acts, which is the shape every migration takes.

## How far the policy is enforced

The policy has two checks behind it, and neither is a sandbox.

**The runner refuses a migration whose metadata block is missing, malformed, or
declares an effect outside the five.** That refusal stops the whole run before
the migration is executed. It catches a migration that never said what it does,
and it is what makes the failure report able to name what the migration was
doing.

**The test suite reads the text of every shipped migration** for the names of
the config directory of the user and of the two files the user owns:
`XDG_CONFIG_HOME`, `$HOME/.config`, `~/.config`, `machine.conf` and
`knobs.conf`.

Both are cheap and both are side-stepped by anybody who wants to. A migration
that builds the same path out of two variables passes the text check, and a
migration that calls a program which writes into the config directory passes
both. They catch the careless case, which is the commoner one. A reviewer is
still what stands behind the rule.

## The state, and what "skipped" means

The runner keeps two files beside the generated output, under the state
directory of the user:

```
$XDG_STATE_HOME/xghost/migrations/applied
$XDG_STATE_HOME/xghost/migrations/skipped
```

The state is not in the config directory, because the user owns that, and it is
not in the checkout, because the checkout holds only what git tracks.

**`applied` is the authority.** A migration named there never runs again.

**`skipped` is a record, not a decision.** It holds one line per migration that
was passed over, with the time and the reason. A migration named in `skipped`
and not in `applied` is still pending, so **the next update runs it again**. That
is what makes a skipped migration run later, and nothing else has to happen: the
reason it was passed over may be gone by then, and a package that could not be
installed because the network was down installs on the next try.

A migration that fails every time is therefore offered every time. That is
deliberate. The one thing that produces a skip is a failure, and a failure that
will never succeed is a broken migration to fix in the repository, not a state
file to grow a permanent exemption in.

## A migration that fails

The runner reports which migration failed, what it was doing, what it declared,
and where the file is. Then it offers the choice:

```
skip this migration and carry on, or stop the update? [skip/stop]
```

`--on-failure` names the answer in advance:

| Value  | What happens                                                     |
| ------ | ------------------------------------------------------------------ |
| `ask`  | Put the question to the reader. The default at a terminal.        |
| `skip` | Record the failure with its reason and carry on.                  |
| `stop` | End the update at that migration. The default with no terminal.   |

**With no terminal the default is `stop`.** An update runs from `install.sh`,
from a timer and over a pipe as well as from a keyboard, and a question nobody
can answer is not a choice. Stopping is the safe half of the two: it changes
nothing more and the update is run again, while skipping would carry a failed
system change past the render and the reload and end the run well.

A run that stopped at a migration does not render and reloads nothing, because
the machine is part way through a change.

## An update that is interrupted

The side effect happens first, and the state is written after it. A process that
dies between the two leaves the migration pending, so the next update runs it
again — and every migration is safe to run twice, which is what covers the gap.

The other order would be worse. A runner that recorded a migration before
running it would mark one applied whose side effect never happened, and nothing
would ever run it.

## A fresh installation replays nothing

The last group of the installer records every existing migration as applied
without running one. A machine installed today was never in the state a
historical migration exists to move a machine out of.

That happens on a first installation and on no other. The test is the migration
state directory: an installation that finds one has been installed before, and
marking its pending migrations applied would take a fix away from that machine
in silence.
