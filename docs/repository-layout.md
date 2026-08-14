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

## Inside `themes/` and `templates/`

| Directory                      | What it holds                                                           |
| ------------------------------ | ----------------------------------------------------------------------- |
| `themes/<name>/palette.conf`   | The named colours of one theme. This file makes the directory a theme.  |
| `themes/<name>/files/`         | The files that theme ships by hand, at the path they take in the output. |
| `templates/`                   | The templates, at the relative path each one takes in the output.       |

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

## A directory that holds only `.gitkeep`

Several directories are empty today, because their content arrives with a later
slice. The `.gitkeep` file holds the directory in git until then. The line above
states what each one will hold.
