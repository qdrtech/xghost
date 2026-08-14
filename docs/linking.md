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
stops, because the text of a link is the path it points at. A trailing slash is
removed, so `/src` and `/src/` write one text.

The linker also stops when a path holds a control character, because the link
record holds one line per link and a control character splits that line in two.
A record line the linker did not write is a line `unlink` must not act on.

The config directory and the prescribed configuration directory must be two
directories. When both names reach one directory, every entry is its own
source. The linker reports that and stops.

```
xghost: the config directory /home/ada/.config and the prescribed configuration directory /home/ada/.config are the same directory; nothing was changed
```

## The linker never destroys anything

A path that is already at a link target is a conflict. The linker reports the
exact path, states what is in the way, leaves the path as it is, and moves on to
the next entry. It exits 1 when it met at least one conflict.

```
xghost: conflict: /home/ada/.config/hypr is a regular file; nothing was changed. Run the command with '--backup' to move it aside.
```

A path that is the very file the linker would link to is a conflict as well.
The linker reports it and stops at that entry, with `--backup` as with a plain
run. To move that path aside would move the prescribed configuration itself,
and the link would then point at itself.

```
xghost: conflict: /home/ada/.config/hypr and /home/ada/.local/share/xghost/config/hypr are the same file; nothing was changed
```

`--backup` handles a conflict instead of reporting it. The linker **moves** the
path that is in the way into the backup directory, prints the exact backup
path, and then creates the link. The path is moved, never copied and never
deleted, so the backup is the original file.

A symbolic link with a relative target is the one path the linker changes as it
moves it: the target is written out in full. A relative target is read from the
directory that holds the link, so inside the backup directory it would reach
another file, or nothing at all. The full target keeps the backup on the file
the original link reached.

```
backup: moved /home/ada/.config/hypr to /home/ada/.local/state/xghost/backups/20260814T151726Z.a7Kq2M/hypr
linked: /home/ada/.config/hypr -> /home/ada/.local/share/xghost/config/hypr
```

One backup directory holds one run. Its name is the time of the run in UTC and
a suffix that makes the name unique. The linker creates that directory once per
run, and no run can name the directory of another run, so a backup never
overwrites a backup. Two runs at one moment therefore keep both backups.

A conflict is something the user put in the way. A link the linker could not
create, with nothing in the way, is a failure of the linker itself. The summary
counts the two apart, and either one exits 1.

```
xghost: cannot create the symbolic link /home/ada/.config/hypr
summary: 0 linked, 0 already linked, 0 backed up, 0 in conflict, 0 skipped, 1 failed
```

`--dry-run` reports every change and changes nothing. It creates no link, no
config directory, no state directory and no backup.

## How the linker knows its own link

`unlink` removes a path only when all three of these hold:

1. The link record holds that path.
2. The path is a symbolic link today.
3. That symbolic link points at the prescribed path the record holds for it.
   The text of the link is the first test. When the text differs, the link
   still counts when it reaches that very file, which is what happens when the
   install location is reached through a symbolic link.

The link record is the file `links` in the state directory. It holds one line
per link: the link path, a tab, then the prescribed path. `link` writes it, and
`unlink` reads it. The record must be a regular file. The linker reports any
other kind of path there and stops, because a record it cannot write is a link
it cannot remove again.

The linker proves that it can record a link before it creates one. It holds an
exclusive lock on the state directory for the whole run, so two runs at one
moment follow one another rather than write the record over each other.

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
