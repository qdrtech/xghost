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
| `docs/`        | The documentation, with the architecture decision records under `docs/adr/`.      |
| `install/`     | The installer: its steps and its package manifests. See below.                    |
| `lib/`         | The shared shell modules the commands and the installer source.                   |
| `migrations/`  | One script per migration, restricted by policy to system side effects.            |
| `templates/`   | The templates the renderer reads to produce themed configuration.                 |
| `tests/`       | The bats test suite, with its fixture command directories under `tests/fixtures/`. |
| `themes/`      | One directory per theme: its palette, its background, and any hand-written file.  |

## Inside `install/`

| Directory                | What it holds                                                             |
| ------------------------ | ------------------------------------------------------------------------- |
| `install/packages/`      | The package manifests, one package per line, comments permitted.          |
| `install/steps/preflight/`    | The checks that run before anything changes: hardware, network, existing files. |
| `install/steps/packaging/`    | The steps that install the packages the manifests declare.           |
| `install/steps/config/`       | The steps that place the prescribed configuration and run detection. |
| `install/steps/post-install/` | The steps that run once the desktop is in place, such as enabling units. |

Every step is idempotent, so a failed installation is resumed by running it
again.

## What is not tracked

Generated output is the fourth file category of
[ADR 0001](adr/0001-prescribed-config-architecture.md). The renderer writes it
to `generated/`, rebuilds it on demand, and nobody edits it. `.gitignore` keeps
that directory out of the checkout.

## A directory that holds only `.gitkeep`

Several directories are empty today, because their content arrives with a later
slice. The `.gitkeep` file holds the directory in git until then. The line above
states what each one will hold.
