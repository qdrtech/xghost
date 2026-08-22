# Adding a command

A command is one executable script in `commands/`. The dispatcher, `bin/xghost`,
reads a metadata comment block from every script in that directory and builds
routing, grouped help, and shell completion from it.

Adding a command means adding one file. There is no registry and no list to
update.

## The file name

The file name is `<group>-<verb>`. The directory is flat, so `commands/theme-set`
is correct and `commands/theme/set` is not.

Lower case letters, digits, and hyphens are the only characters allowed. The
group is the text before the first hyphen. The verb is the rest, so
`commands/theme-reload-cache` is the verb `reload-cache` in the group `theme`.

The file must be executable.

## The metadata block

The block starts at a line that reads `# @xghost-meta` and ends at a line that
reads `# @end-xghost-meta`. Every line between the two must be a comment. Each
one carries one key and one value:

```bash
#!/usr/bin/env bash
# @xghost-meta
# summary: Set the active theme.
# arg: NAME  The theme to activate.
# example: xghost theme set nord
# elevated: no
# internal: no
# @end-xghost-meta
```

Place the block anywhere in the file. Directly under the shebang line is the
convention.

## The keys

| Key        | Times     | Value                                                        |
| ---------- | --------- | ------------------------------------------------------------ |
| `summary`  | Exactly 1 | One sentence for the help output. Required.                   |
| `arg`      | 0 or more | An argument name, white space, then a description.            |
| `example`  | 0 or more | One complete command line.                                    |
| `elevated` | 0 or 1    | `yes` when the command needs root. Default `no`.              |
| `internal` | 0 or 1    | `yes` to hide the command from help. Default `no`.            |

A summary holds printable characters and spaces only. A control character, such
as a tab, is a metadata problem, because the dispatcher carries the summary
through a tab separated list into help and completion. Every other character is
allowed. The dispatcher escapes a colon itself when it writes the completion
list, so a summary may hold one.

The dispatcher drops the white space at the end of every value.

The dispatcher builds the usage line from the `arg` keys, in the order they
appear. The example above produces:

```
Usage: xghost theme set NAME
```

`elevated: yes` adds `(needs root)` beside the summary in the grouped help, and
adds a line to the detailed help of that command. It does not raise privileges
by itself. The command does that.

`internal: yes` hides the command from the grouped help and from shell
completion. The command still runs when a user names it, so another script may
call it.

## When the block is not well formed

Each case below is a metadata problem. The dispatcher reports it and `xghost
--lint` exits non-zero.

- **A repeated key.** `summary`, `elevated`, and `internal` are allowed once
  each. The dispatcher reports the second one with its line number and keeps
  the value of the first one. `arg` and `example` repeat by design, and the
  dispatcher keeps them in the order they appear.
- **A second `# @xghost-meta` block.** A command has exactly one block. The
  dispatcher reports the second one at the line where it starts. It reads the
  keys of that block as though they continued the first block, so a key that
  appears in both blocks is reported as a repeated key.
- **A line inside the block that is not a comment.** The dispatcher reports the
  line and keeps reading. The block ends at `# @end-xghost-meta` and nowhere
  else, so every key below such a line is still checked and still reported. The
  dispatcher reports only the first line of this kind in a file, because a block
  that carries no end marker would otherwise produce one report for every line
  of the script.
- **A block that carries no `# @end-xghost-meta` line.** The dispatcher reports
  it after it reads the last line of the file.

## How the metadata is used

| Command                        | Output                                          |
| ------------------------------ | ----------------------------------------------- |
| `xghost`                       | Every visible command, grouped, with summaries. |
| `xghost <group>`               | The verbs of one group, with summaries.         |
| `xghost <group> --help`        | The verbs of one group, with summaries.         |
| `xghost <group> <verb> --help` | Summary, usage, arguments, and examples.        |
| `xghost <group> <verb> [...]`  | Runs the script with the arguments unchanged.   |

The exit status of the script reaches the caller unchanged.

## The dispatcher owns `-h` and `--help` in two positions

`-h` and `--help` mean the same thing, and the dispatcher answers both in two
positions:

- **The verb position.** `xghost theme --help` and `xghost theme -h` print the
  verbs of the group `theme`, which is what `xghost theme` prints.
- **The first argument position.** `xghost theme set --help` and
  `xghost theme set -h` print the detail of that one command.

A command never receives `-h` or `--help` in those two positions. In every later
position the dispatcher passes the word through unchanged, so
`xghost theme set nord --help` runs the script with `nord --help`, and the
script decides what that means. Write a command that takes an argument of its
own with this in mind.

## A metadata problem is always reported

The dispatcher never drops a metadata problem in silence. It reports one in two
ways:

- **A warning on standard error.** Help, completion, and routing each print one
  warning line per problem, in the form `xghost: <file>: <problem>`. A command
  with a metadata problem is left out of help and completion, because there is
  no sound summary to print. Routing still runs it, so a typo in a comment never
  takes a working command away from a user.
- **A non-zero exit from `xghost --lint`.** The lint pass checks every entry of
  the command directory, prints every problem, and exits 1 when it finds any.
  Continuous integration runs it on every push.

A lint pass that inspected no file has proved nothing, so it is not a pass. The
lint pass exits 3 when the command directory holds no command file.

An entry the dispatcher cannot inspect carries a message of its own: a broken
symbolic link, a file the dispatcher may not read, and an entry that is not a
regular file. The dispatcher names each one rather than passing over it, because
these are the states a user is least able to see.

The one case that stops a command is a file that cannot be run. The dispatcher
exits 126 and reports it.

Files whose name starts with a dot, such as `.gitkeep`, are not commands. The
dispatcher skips them.

## Exit codes of the dispatcher

| Code | Meaning                                                                     |
| ---- | --------------------------------------------------------------------------- |
| 0    | Success.                                                                    |
| 1    | The lint pass found a problem, the command directory is missing, or the dispatcher cannot describe a command whose metadata has a problem. |
| 2    | The dispatcher was called with an unknown option or with an empty group name. |
| 3    | The command directory holds no command file.                                |
| 126  | The command file is not an executable file.                                 |
| 127  | The group or the verb does not exist.                                       |

The dispatcher returns one of these codes only when it stops before it runs a
command. Once a command runs, the exit status of that command reaches the caller
unchanged, and that status may hold any value, including the values above.

## Shell completion

`completions/_xghost` completes groups and verbs in zsh. It asks the dispatcher
for the words, so a new command completes as soon as its file exists. Two
options carry the data:

```
xghost --complete-groups          one group per line
xghost --complete-verbs <group>   one 'verb:summary' per line
```

## The README carries the same list

A command a user runs is in the table of commands of `README.md`, with the
summary of its metadata block. That table is the grouped help under another
layout, so a command added, renamed or resummarised has to reach it as well.

`tests/docs.bats` reads both and compares them, so the page cannot drift: a
summary that differs fails, a command the README does not list fails, and a
command the README lists and the dispatcher does not fails too. A command with
`internal: yes` is in neither, because the dispatcher leaves it out of the help.

## Checking your work

```
xghost --lint          # report every metadata problem
xghost                 # confirm the command appears under its group
xghost <group> <verb> --help
bats tests             # run the dispatcher tests
```

Then add the command to the table in `README.md`.
