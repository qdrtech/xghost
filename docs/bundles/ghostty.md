# The Ghostty bundle

Ghostty is the terminal of xghost. It is the first bundle, and it is the first
application that reads the generated output of the renderer.

The bundle is two files:

| File                        | Category         | What it holds                              |
| --------------------------- | ---------------- | ------------------------------------------ |
| `config/ghostty/config`      | Prescribed       | Every setting except the colours.          |
| `templates/ghostty/colors.conf` | Template      | The colours, from the palette of the theme. |

The two file categories are those of
[ADR 0001](../adr/0001-prescribed-config-architecture.md).

Both files are carried over from `qdrtech/dotfiles`, path
`ghostty/.config/ghostty/config` and the Ghostty section of
`scripts/theme-switch.sh`. The settings and the colour slots are unchanged. Two
things did change, and each one is recorded below.

## How the two files meet

```
xghost config link        ~/.config/ghostty -> <install location>/config/ghostty
xghost theme set NAME     ~/.local/state/xghost/generated/ghostty/colors.conf
```

The prescribed file includes the generated one:

```
config-file = ?~/.local/state/xghost/generated/ghostty/colors.conf
```

Ghostty applies an included file after the file that includes it, so the
colours of the theme win over anything the prescribed file sets.

## The include path

Ghostty resolves a `config-file` path in one of three ways, and the choice
matters because the prescribed file lives in the checkout while the generated
file lives under the state directory of the user.

| Form                                          | What Ghostty does                                       |
| --------------------------------------------- | ------------------------------------------------------- |
| `~/.local/state/xghost/generated/...`          | Expands `~` to `$HOME`. **Chosen.**                     |
| `../../.local/state/xghost/generated/...`      | Resolves against the directory of the including file.   |
| `$XDG_STATE_HOME/xghost/generated/...`         | Nothing. Ghostty expands no environment variable.       |

The environment form is out, because Ghostty reads the text as a literal path
and the include is then never found.

The relative form works. Ghostty resolves it against the path it opened, which
is `~/.config/ghostty`, and it does so through the symbolic link the linker
creates. It carries two assumptions all the same: that `XDG_CONFIG_HOME` is
`~/.config`, and that `XDG_STATE_HOME` is `~/.local/state`. A wrong value for
either one aims the path at nothing.

The home form carries one assumption instead of two, and it does not depend on
where the prescribed file sits. It is the chosen form.

The assumption that remains: a user who sets `XDG_STATE_HOME` to a path other
than `~/.local/state` gets a Ghostty with no theme, because the include names
the default path in full. The renderer follows the same variable, so the
generated file is written where that variable points and the include misses it.
Ghostty offers no way to name the path from the environment, so the limitation
is Ghostty's rather than a choice of this project.

## The optional include

The `?` at the front of the path makes the include optional. Before the first
`xghost theme set` the generated file does not exist, and a required include
would stop Ghostty from starting at all. A terminal that refuses to open on a
fresh installation is a bad first impression, so the include stays optional.

`ghostty +validate-config` exits zero on a fresh installation for the same
reason.

## The font

`.SF NS Mono` is the macOS system font and exists on no Arch machine. The
bundle uses `JetBrainsMono Nerd Font` instead.

| Property     | Value                                     |
| ------------ | ----------------------------------------- |
| Family name  | `JetBrainsMono Nerd Font`                 |
| Arch package | `ttf-jetbrains-mono-nerd`                 |
| Repository   | `extra`                                   |

Two reasons for this family. It carries the contextual alternates and the
ligatures that the `font-feature` lines of the prescribed file switch on. It
also carries the Nerd Font glyphs that the bar and the shell prompt need, so
one font serves the whole desktop.

The package belongs in the package manifest, which
[issue #7](https://github.com/qdrtech/xghost/issues/7) builds. Until that
manifest exists, the font is a dependency this document records and the
installer does not yet place.

## What the tests prove

- `tests/ghostty.bats` proves the shape of the bundle: the prescribed file is
  linked by `xghost config link`, the include names the generated path, the
  macOS font is gone, and every colour of every theme reaches the output.
- `tests/golden.bats` compares the rendered colours of every theme with the
  expected output under `tests/golden/<theme>/ghostty/colors.conf`.

Neither test runs Ghostty, because continuous integration has no Ghostty. The
`ghostty +validate-config` check is run by hand on a machine that has it.

## What this bundle does not do

A running Ghostty keeps the colours it started with. A theme switch writes the
new file and stops there. Picking the change up without a restart is
[issue #24](https://github.com/qdrtech/xghost/issues/24), which covers every
styling component with one reload function.
