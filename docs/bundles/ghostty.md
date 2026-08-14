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
`scripts/theme-switch.sh`. The colour slots are unchanged apart from slot 8.
What changed, and why, is recorded below.

## How the two files meet

`xghost config link` creates two links, and `xghost theme set` writes the
colours:

```
xghost config link     $XDG_CONFIG_HOME/ghostty          -> <install location>/config/ghostty
                       $XDG_CONFIG_HOME/xghost-generated -> $XDG_STATE_HOME/xghost/generated
xghost theme set NAME  $XDG_STATE_HOME/xghost/generated/ghostty/colors.conf
```

The second link is the **bridge**. It gives the generated output one fixed name
inside the config directory. The prescribed file includes the generated one
through it:

```
config-file = ?../xghost-generated/ghostty/colors.conf
```

Ghostty applies an included file after the file that includes it, so the
colours of the theme win over anything the prescribed file sets.

## The include path

Ghostty resolves a `config-file` path in one of three ways, and the choice
matters because the prescribed file lives in the checkout while the generated
file lives under the state directory of the user.

| Form                                       | What Ghostty does                                     |
| ------------------------------------------ | ----------------------------------------------------- |
| `../xghost-generated/...`                   | Resolves against the directory of the including file. **Chosen.** |
| `~/.local/state/xghost/generated/...`       | Expands `~` to `$HOME`.                               |
| `$XDG_STATE_HOME/xghost/generated/...`      | Nothing. Ghostty expands no environment variable.     |

The environment form is out, because Ghostty reads the text as a literal path
and the include is then never found.

The home form is out too, and this is the point the first draft of this bundle
got wrong. It writes the state directory out in full, so it is right only while
`XDG_STATE_HOME` holds its default. The renderer follows that variable, so a
user who moves the state directory gets a renderer writing to one path and a
Ghostty reading another. The `?` makes the include optional, so the miss is
reported nowhere and the terminal simply comes up unthemed. It also breaks the
promise of [theming](../theming.md), which names `$XDG_STATE_HOME/xghost/generated`
as the stable path applications read.

The relative form has neither end written out in full. The directory it starts
from moves with `XDG_CONFIG_HOME`, and the bridge moves with `XDG_STATE_HOME`,
so the include is right for every value of both.

### How Ghostty resolves the relative path

This is the rule the next bundles depend on, so it is written out.

The prescribed file is opened as `$XDG_CONFIG_HOME/ghostty/config`, and that
path holds a symbolic link: `ghostty` points into the checkout. A relative
`config-file` therefore has two possible bases.

| Base                     | Path                                       |
| ------------------------ | ------------------------------------------ |
| The path as opened       | `$XDG_CONFIG_HOME/ghostty`                 |
| The real path            | `<install location>/config/ghostty`        |

**Ghostty tries both, and the real path wins.** When the file exists under the
real path, that is the one Ghostty reads, whether or not a file also exists
under the path as opened. Only when the real path finds nothing does Ghostty
fall back to the path as opened.

Verified against Ghostty 1.3.1-arch2. `ghostty +show-config` prints the
`config-file` value it resolved, so the base it chose is visible:

```
config-file = ?/home/ada/.config/xghost-generated/ghostty/colors.conf
```

The bridge lives under the path as opened, and the checkout holds no
`config/xghost-generated`, so the fallback is the branch this bundle takes.
That yields one rule for every bundle that comes after:

> **The checkout must never hold `config/xghost-generated`.** Such a directory
> would sit under the real path, so Ghostty would read it in place of the
> bridge, and the terminal would carry the colours of the checkout rather than
> those of the active theme.

The bridge is created by `xghost config link`, recorded in the link record like
every other link, and removed by `xghost config unlink`. It is not prescribed
configuration: no file in `config/` stands behind it. See
[linking](../linking.md).

## The optional include

The `?` at the front of the path makes the include optional. Before the first
`xghost theme set` the generated file does not exist, and a required include
would stop Ghostty from starting at all. A terminal that refuses to open on a
fresh installation is a bad first impression, so the include stays optional.

`ghostty +validate-config` exits zero on a fresh installation for the same
reason. It exits zero on a terminal that found none of its colours, too, so it
answers "is this configuration well formed" and never "is this terminal
themed". `ghostty +show-config` answers the second question: it prints the
settings Ghostty holds after it has read every file, so a `background` line is
the proof. The tests assert on `+show-config` for that reason.

## The colour slots

The palette of a theme names ten colours and the terminal has sixteen slots, so
the two halves of the terminal palette carry the same colours. Slot 8 is the
exception.

Slot 8 is bright black, and a scheme that maps its comments to bright black
draws them in it. So do `zsh-autosuggestions` by default, the hints of `fzf`,
and the line numbers of `bat` and `delta`. The slot therefore has to stay
readable on the background.

The first draft of this bundle set slot 8 to the surface colour, which is the
background under another name. The result was invisible text everywhere the
slot is used:

| Theme        | Slot 8 was  | On background | Contrast | Slot 8 is now | Contrast |
| ------------ | ----------- | ------------- | -------- | ------------- | -------- |
| `tokyonight` | `#1F2335`   | `#1A1B26`     | 1.10:1   | `#A9B1D6`     | 8.10:1   |
| `macos-dark` | `#1c1f26`   | `#0f1115`     | 1.15:1   | `#a1a1aa`     | 7.37:1   |

The slot now carries `TEXT_MUTED`, which is the colour a palette declares for
text that recedes without disappearing. Every other slot is 5.18:1 or better.

Slots 5 and 6, magenta and cyan, carry the same colour. That is faithful to the
ten-colour palette and to the upstream dotfiles, and it is deliberate.

## Two settings that name themselves badly

`background-blur-radius` is an undocumented compatibility alias. Ghostty 1.3.1
rewrites it to `background-blur` and reports nothing, and the name appears in no
`ghostty +show-config --default --docs` output. A name that is documented
nowhere can be dropped without a deprecation, and the loss would be silent. The
bundle names `background-blur = 20`, which is the same behaviour under the name
Ghostty documents.

`gtk-titlebar = true` is already the default of Ghostty 1.3.1, so the line
changes nothing today. It is **kept**: the title bar is a deliberate choice of
this bundle, and a release that changes the default must not change the window.
The cost is one line that does nothing; the alternative is a window that changes
without a commit.

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

The package is declared in `install/packages/base.txt`, with `ghostty` itself.
[Installing](../installing.md) records the manifest.

## What the tests prove

- `tests/ghostty.bats` proves the shape of the bundle: the prescribed file is
  linked by `xghost config link`, the include reaches the file the renderer
  wrote, the macOS font is gone, and every colour of every theme reaches the
  slot the template names for it. One case renders under a non-default
  `XDG_STATE_HOME`, which is the divergence that breaks a terminal.
- `tests/linker.bats` proves the bridge: it is created, it is recorded, it is
  removed by `xghost config unlink`, and it never clobbers a path the user put
  at that name.
- `tests/golden.bats` compares the rendered colours of every theme with the
  expected output under `tests/golden/<theme>/ghostty/colors.conf`.

The tests that need Ghostty run it and skip cleanly when it is absent, because
continuous integration has no Ghostty. They assert on
`ghostty +show-config`, never on the exit code of `ghostty +validate-config`,
which is zero on an unthemed terminal.

## What this bundle does not do

A running Ghostty keeps the colours it started with. A theme switch writes the
new file and stops there. Picking the change up without a restart is
[issue #24](https://github.com/qdrtech/xghost/issues/24), which covers every
styling component with one reload function.
