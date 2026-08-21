# Repository layout

One line for each directory, so that you can find the file that controls a given
behaviour without reading the tree.

## Top level

| Directory      | What it holds                                                                     |
| -------------- | --------------------------------------------------------------------------------- |
| `bin/`         | The `xghost` dispatcher, which is the only entry point a user runs.               |
| `commands/`    | One executable script per command, named `<group>-<verb>`. The dispatcher scans it. |
| `completions/` | The shell completion functions, one file per shell.                               |
| `config/`      | The prescribed configuration the project owns and symlinks into `~/.config`.      |
| `docs/`        | The documentation, with the architecture decision records under `docs/adr/` and one page per bundle under `docs/bundles/`. |
| `install/`     | The installer: its steps and its package manifests. See below.                    |
| `lib/`         | The shared shell modules the commands and the installer source, and `background.py`, the one program of this repository that is not shell. [Backgrounds](backgrounds.md) records why it exists. |
| `migrations/`  | One script per migration, named `NNNN-name.sh` and restricted by policy to system side effects. [Updating](updating.md) records the format, the state the runner keeps, and how far the policy is enforced. |
| `schema/`      | The schemas the project owns. `schema/knobs.conf` names every knob, the values it takes, and its default. |
| `templates/`   | The templates the renderer reads to produce themed configuration.                 |
| `tests/`       | The bats test suite, with its fixtures under `tests/fixtures/` and the helpers more than one suite needs in `tests/helpers.bash`. `tests/setup_suite.bash` runs once per run and holds what has to be true of every suite, which today is that no suite reloads a running desktop. [Reloading](reloading.md) records why that guard exists. |
| `themes/`      | One directory per theme: its palette, and any file it ships by hand. The background is drawn from the palette rather than shipped: see [Backgrounds](backgrounds.md). |

Two files sit at the top level beside those directories. `install.sh` is the
front end of the installer: it sources `lib/install.sh` and runs the steps
below. `boot.sh` is the entry point a fresh machine reaches over `curl`: it
installs git, clones this repository to the install location, and hands off to
`install.sh`. [Installing](installing.md) records both, and what each group of
steps does.

## Inside `install/`

| Directory                | What it holds                                                             |
| ------------------------ | ------------------------------------------------------------------------- |
| `install/packages/`      | The package manifests, one package per line, comments permitted. `base.txt` is what pacman installs, and `aur.txt` is what an AUR helper installs. |
| `install/steps/preflight/`    | The checks that run before anything changes: hardware, network, existing files. |
| `install/steps/packaging/`    | The steps that install the packages the manifests declare.           |
| `install/steps/config/`       | The steps that place the prescribed configuration and run detection. |
| `install/steps/post-install/` | The steps that run once the desktop is in place, such as enabling units. |

Every step is idempotent, so a failed installation is resumed by running it
again.

## Inside `themes/` and `templates/`

| Directory                      | What it holds                                                           |
| ------------------------------ | ----------------------------------------------------------------------- |
| `themes/<name>/palette.conf`   | The named colours of one theme. This file makes the directory a theme.  |
| `themes/<name>/files/`         | The files that theme ships by hand, at the path they take in the output. |
| `templates/`                   | The templates, at the relative path each one takes in the output.       |
| `templates/<file>.choice.<NAME>/` | One structural choice: one fragment per value of NAME, of which the renderer writes one to `<file>`. |

[Theming](theming.md) documents the palette format, the templates, and the
commands that drive the renderer.

## Where the generated output goes

Generated output is the fourth file category of
[ADR 0001](adr/0001-prescribed-config-architecture.md). It never lands in the
checkout, because the checkout holds only the files git tracks, and generated
output is tracked by nobody.

The renderer writes it to `$XDG_STATE_HOME/xghost/generated`, which is usually
`~/.local/state/xghost/generated`. Applications read that path. The renderer
rebuilds it on demand and nobody edits it. [Theming](theming.md) records why the
state directory holds it.

The background image of the theme is generated output as well, at
`hypr/background.png` under that path. No image is committed to this
repository, which is what keeps a `curl` install a quick clone.

## Where the machine facts go

Machine facts are the second file category of
[ADR 0001](adr/0001-prescribed-config-architecture.md). They belong to the
user, so they never land in the checkout either.

`xghost machine detect` writes them to `$XDG_CONFIG_HOME/xghost/machine.conf`,
which is usually `~/.config/xghost/machine.conf`. An update replaces the
checkout and never writes to your config directory, so the file survives every
update untouched. [Machine facts](machine-facts.md) documents the file.

## Where the knobs go

Knobs are the third file category of
[ADR 0001](adr/0001-prescribed-config-architecture.md), and they are two files
with two owners.

`schema/knobs.conf` is in the checkout, because the project owns it and
validates against it. `xghost settings set` writes your values to
`$XDG_CONFIG_HOME/xghost/knobs.conf`, beside the machine facts and for the same
reason. [Knobs](knobs.md) documents both files.

## A directory that holds only `.gitkeep`

Several directories are empty today, because their content arrives with a later
slice. The `.gitkeep` file holds the directory in git until then. The line above
states what each one will hold.
