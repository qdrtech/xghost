# 0001. Prescribed config architecture

- Status: accepted
- Date: 2026-08-12

## Context and problem statement

xghost installs a complete Hyprland desktop on a user's machine. That
installation is a set of files on disk. Every one of those files has an owner,
and the owner decides how the file is allowed to change. If the project and the
user both own a file, the project has to patch text it does not control every
time that file has to change.

The question this ADR answers: which categories of file exist in a running
installation, who owns each category, and how does each category change?

The project draws its evidence from a study of `basecamp/omarchy`, which solves
the same problem with a copy-and-seed model and has run in production for over
a year. That study is recorded in "More information" below. It shows the cost of
shared ownership as a measured number rather than an opinion.

## Decision drivers

- One maintainer has to be able to support every installation.
- The maintainer has to be able to change any prescribed config file without
  writing a migration.
- Detection has to be able to overwrite its own output completely.
- A user's machine facts and knobs have to survive a project update untouched.
- The strictness of the model has to stay reversible.

## Considered options

1. **Copy and seed.** Copy the project's config into `~/.config` at install
   time. The user owns the copy from that point. This is the omarchy model.
2. **Prescribed ownership with symlinks.** The project owns all real
   configuration and symlinks it into place. The user owns two files: machine
   facts and knobs.
3. **Framework with a free-form override surface.** The project ships defaults
   and the user overrides any of them at any depth.

## Decision outcome

Chosen option: **prescribed ownership with symlinks**.

Option 1 gives the user a copy the project later has to patch, which is the
cost the omarchy study measures. Option 3 turns an installation into a state
space, which one maintainer cannot test or diagnose. Option 2 is the only option
under which the project never writes to a file it does not own.

The decision splits every file in a running installation into four categories.
A file belongs to exactly one category, and the category fixes its owner and its
update mechanism.

### The file categories

| Category         | Owner                                    | Update mechanism                                                                      |
| ---------------- | ---------------------------------------- | ------------------------------------------------------------------------------------- |
| Prescribed       | The project                              | Pull. Symlinked into `~/.config`. Users do not edit.                                  |
| Machine facts    | The user, written by detection           | Detection overwrites the file wholesale. The user may edit it to correct a detection. |
| Knobs            | The user, against a project-owned schema | The user edits the file. The project validates it.                                    |
| Generated output | No one (produced by the renderer)        | Rebuilt on demand. Never tracked. Never edited.                                       |

Prescribed files hold all real configuration.

Machine facts are one file: the monitor layout, the keyboard layout, input
device quirks, the timezone, the display scale, the default browser and
terminal. Detection writes the whole file. The file is never patched and never
merged.

A user edit to this file is expected as the way to correct a wrong detection,
and re-running detection discards that edit.

Knobs are one file: the preferences the project supports, such as bar position,
animations, gap sizes, and font. The project owns the schema and rejects an
invalid value.

Generated output is the fourth category. It is disposable.

Machine facts and knobs are two files rather than one, because their lifecycles
differ. Detection has to overwrite its output completely. If knobs shared that
file, detection would have to edit around text a human wrote, which is the
surgical patching this architecture exists to avoid.

### Symlink rather than copy

The product installs to a fixed location under the user's data directory and
symlinks its config directory into `~/.config`.

Symlinking is chosen over copying for two reasons:

- An update reaches the user's desktop the moment the pull completes.
- A user edit to a prescribed file is loud. It dirties the checkout and it
  conflicts on the next pull. A copy diverges silently instead.

### One renderer with three inputs

One module generates all themed and knob-dependent configuration. It takes three
inputs — the active theme palette, machine facts, and knobs — plus a directory
of templates. It emits a directory of finished config files. Applications
reference that output directory at a stable path, so a theme switch or a knob
change never rewrites an application's own config file.

The renderer uses two substitution mechanisms:

- **Scalar values** are substituted into templates by name. Derived forms cover
  values that need a different representation, such as a colour without its
  leading hash.
- **Structural choices** select between alternative prescribed fragments. A
  block, such as animations on or off, is a choice between fragments rather than
  a template. This keeps the project out of the business of building a template
  language.

A theme may ship a hand-written file for any application. The renderer leaves
that file alone and generates the remainder.

Theme switching is atomic. The renderer builds a complete new output directory
and moves it into place, so an interrupted switch leaves the previous theme
intact.

### Migrations are restricted to system side effects

A migration runner tracks applied and skipped migrations and runs pending ones
during an update. Migrations are restricted by policy to system side effects
only.

A migration **may**:

- install a package,
- drop a package,
- enable a unit,
- set a desktop key,
- remove a stale generated file.

A migration **must not** edit a user's configuration file.

A migration **must** be safe to run twice, so that an interrupted update is
resumed by running the pending migrations again.

Contributors apply the rule as follows. Find the category of the file the change
targets. A prescribed file is delivered by the pull, so it needs no migration.
Machine facts and knobs belong to the user, so a migration must not touch them.
Generated output is rebuilt by the renderer, so a migration may only delete a
stale file. Any migration that still needs to write configuration text is out of
policy, because the architecture is designed so that no such migration is
needed.

A fresh installation marks all existing migrations as applied, so a new user
never replays historical fixes.

### No override surface, and its reversibility

The project ships no free-form override surface. A preference is served by a
knob, and anything a knob does not cover is a request for a new knob or a fork.

This decision is reversible, and the direction of the reversal matters. Adding
an override surface later is a one-line change per config file. Removing an
override surface after users depend on it is not. Starting strict is therefore
the safe direction, and this ADR can be superseded once the cost of the
strictness is known.

## Consequences

What becomes easier:

- The maintainer changes any prescribed config file freely, with no migration.
- The maintainer adds a new prescribed config file without a migration for
  existing users.
- An update never touches machine facts or knobs.
- An installation has one state rather than a state space, which makes both
  testing and diagnosis tractable.

What becomes harder:

- A user who edits a prescribed file gets a conflict on the next pull. This is
  the intended behaviour of the symlink decision.
- A preference the knob schema does not cover requires a new knob, with schema
  and validation work, or a fork.
- Every generated file depends on the renderer, so a renderer defect reaches
  every theme at once.

## Confirmation

- The doctor command reports a modified prescribed file, a missing dependency,
  and a stale generated file.
- The renderer is covered by golden-file tests: every theme against every
  template, with fixed machine facts and knobs, compared against committed
  expected output.
- The linker is covered by unit tests for idempotency and for refusal to
  clobber an existing regular file.
- A reviewer checks every proposed migration against the side-effects-only rule
  above.

## More information

The migration policy rests on the `basecamp/omarchy` study:

- omarchy wrote 330 migrations in 386 days. That is six per week, sustained, and
  none of them can ever be deleted.
- A random sample of 45 of those migrations found that 38% existed solely to
  patch a configuration file that was copied into the user's home directory and
  later had to change. That is the dominant cost of the copy-and-seed model.
- Of six migrations examined in detail, four would not exist under this
  architecture, because the files they patch would be project-owned and
  delivered by a pull. The two that remain are system side effects.

The requirements this ADR serves are recorded in
[issue #1](https://github.com/qdrtech/xghost/issues/1).
