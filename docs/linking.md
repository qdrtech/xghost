# Linking the prescribed configuration

The project owns every file under `config/`, the prescribed configuration
directory of
[ADR 0001](adr/0001-prescribed-config-architecture.md). The linker deploys that
directory by symbolic link. It replaces GNU Stow run by hand.

```
xghost config link      # link the prescribed configuration into place
xghost config unlink    # remove the links that xghost created
```

The dispatcher routes a command by its group and its verb, so the commands are
`config link` and `config unlink`.

## What is linked

The linker links every top level entry of the prescribed configuration
directory. A directory and a regular file are both linked. An entry whose name
starts with a dot, such as `.gitkeep`, is not a prescribed entry, and the
linker passes over it.

`config/hypr` becomes the link `~/.config/hypr`, and that link points at
`config/hypr` in the install location. An update reaches the desktop the moment
the pull completes, and a user edit to a prescribed file dirties the checkout.
Both are the intent of the ADR.

## The paths, and how to override each one

Every path comes from one place, so a test sets one variable rather than a home
directory the linker reads in several places.

| Path                            | Variable               | Default                                                       |
| ------------------------------- | ---------------------- | ------------------------------------------------------------- |
| The prescribed configuration    | `XGHOST_CONFIG_SOURCE` | `<install location>/config`                                   |
| The user's config directory     | `XGHOST_CONFIG_HOME`   | `$XDG_CONFIG_HOME`, and `$HOME/.config` when that is not set  |
| The state directory             | `XGHOST_STATE_DIR`     | `$XDG_STATE_HOME/xghost`, and `$HOME/.local/state/xghost` when that is not set |
| The backup directory            | `XGHOST_BACKUP_DIR`    | `<state directory>/backups`                                   |

Every override takes an absolute path. The linker reports a relative path and
stops, because the text of a link is the path it points at.

## The linker never destroys anything

A path that is already at a link target is a conflict. The linker reports the
exact path, states what is in the way, leaves the path as it is, and moves on to
the next entry. It exits 1 when it met at least one conflict.

```
xghost: conflict: /home/ada/.config/hypr is a regular file; nothing was changed. Run the command with '--backup' to move it aside.
```

`--backup` handles a conflict instead of reporting it. The linker **moves** the
path that is in the way into the backup directory, prints the exact backup
path, and then creates the link. The path is moved, never copied and never
deleted, so the backup is the original file.

```
backup: moved /home/ada/.config/hypr to /home/ada/.local/state/xghost/backups/20260814T151726Z/hypr
linked: /home/ada/.config/hypr -> /home/ada/.local/share/xghost/config/hypr
```

One backup directory holds one run. Its name is the time of the run, in UTC. A
second run in the same second takes the next free name, so a backup never
overwrites a backup.

`--dry-run` reports every change and changes nothing. It creates no link, no
config directory, no state directory and no backup.

## How the linker knows its own link

`unlink` removes a path only when all three of these hold:

1. The link record holds that path.
2. The path is a symbolic link today.
3. The text of that symbolic link is exactly the prescribed path the record
   holds for it.

The link record is the file `links` in the state directory. It holds one line
per link: the link path, a tab, then the prescribed path. `link` writes it, and
`unlink` reads it.

The record is the part that makes the test precise. A symbolic link the user
made by hand is not in the record, so `unlink` never sees it, even when it
points at the same prescribed entry. The target test is the second half: a
recorded path that now points somewhere else is a path the user has taken over,
so `unlink` reports it and leaves it alone.

```
xghost: left alone: /home/ada/.config/hypr is a symbolic link to /home/ada/dotfiles/hypr; xghost did not create it
```

`link` adopts a link that already points at the prescribed entry: it reports
`already linked` and records the path. A second run therefore changes nothing
and reports no error.

A link that the record holds is kept in the record while it is still a link the
linker created, even when the prescribed entry behind it is gone. A release
that drops a bundle leaves a link that `unlink` still removes.

`unlink` removes symbolic links only. Removing a symbolic link never touches
the file it points at.

## Exit codes

| Code | Meaning                                                          |
| ---- | ---------------------------------------------------------------- |
| 0    | Success. Nothing to do is a success.                             |
| 1    | At least one conflict, or an entry the linker could not handle.  |
| 2    | Unknown option.                                                  |

A path that `unlink` left alone is a report rather than a failure, so it does
not change the exit code.
