#!/usr/bin/env bash
#
# linker — deploy the prescribed configuration by symbolic link.
#
# The project owns every file under the prescribed configuration directory.
# This module links each top level entry of that directory into the user's
# config directory. It replaces GNU Stow run by hand.
#
# The module never deletes and never overwrites a file it did not create. A
# path that is in the way is a conflict. A conflict is reported with its exact
# path and with what is in the way, and nothing is changed. The '--backup'
# option moves the path that is in the way into the backup directory instead,
# and reports the exact backup path.
#
# The module also creates one link that no prescribed entry stands behind: the
# bridge to the generated output. See LINKER_BRIDGE_NAME below.
#
# The module records every link it creates, the bridge included. 'unlink'
# removes a path only when the record holds that path and the path is still a
# symbolic link to the recorded target. A symbolic link the user made is not in
# the record, so it is left alone.
#
# The design is documented in docs/linking.md.
#
# Environment:
#   XGHOST_CONFIG_SOURCE  The prescribed configuration directory.
#                         Default: <install location>/config
#   XGHOST_CONFIG_HOME    The user's config directory.
#                         Default: $XDG_CONFIG_HOME, else $HOME/.config
#   XGHOST_STATE_DIR      The directory that holds the link record.
#                         Default: $XDG_STATE_HOME/xghost,
#                         else $HOME/.local/state/xghost
#   XGHOST_BACKUP_DIR     The directory that holds the backups.
#                         Default: <state directory>/backups

# The include sentinel. A library may be sourced more than once, because two
# modules may each need it. The second source returns here, so the declarations
# below run exactly once.
if [ -n "${XGHOST_LINKER_SOURCED:-}" ]; then
	return 0
fi
XGHOST_LINKER_SOURCED=1

# The environment may carry BASHOPTS or SHELLOPTS, and both change how the
# globs in this module behave. Normalise every option the module depends on.
shopt -u dotglob nocaseglob failglob
unset GLOBIGNORE
set +f

LINKER_PROGRAM=xghost

# The bridge to the generated output.
#
# A prescribed file that includes generated output cannot name the state
# directory in full. Ghostty expands no environment variable, and neither does
# most of what this project prescribes, so a path written out in full is wrong
# the moment XDG_STATE_HOME is not the default. The include then misses, and an
# optional include misses in silence.
#
# The bridge gives the generated output one fixed name inside the config
# directory:
#
#   $XGHOST_CONFIG_HOME/xghost-generated -> <state directory>/generated
#
# A prescribed file reaches the generated output by a path relative to its own
# directory, such as '../xghost-generated/ghostty/colors.conf'. Both ends of
# that path move with the environment, so the include is right whatever
# XDG_CONFIG_HOME and XDG_STATE_HOME hold. docs/bundles/ghostty.md records how
# Ghostty resolves such a path.
#
# The bridge is a link this module creates, so it is recorded and removed like
# every other one. It is created beside the prescribed entries and never
# instead of one.
LINKER_BRIDGE_NAME=xghost-generated

# The name of the stable path under the state directory. lib/theme.sh writes
# it, and docs/theming.md documents it as the path applications read.
LINKER_GENERATED_NAME=generated

# Set by linker_resolve_paths.
LINKER_SOURCE_DIR=
LINKER_CONFIG_HOME=
LINKER_STATE_DIR=
LINKER_BACKUP_DIR=
LINKER_RECORD=

# The backup directory of this run, created once by linker_backup, and the
# exact backup path of the last path that linker_backup moved.
LINKER_RUN_BACKUP_DIR=
LINKER_BACKUP_PATH=

# The file descriptor that holds the lock on the state directory. The run
# holds it from end to end, and the kernel drops it when the process ends.
LINKER_LOCK_FD=

linker_say() {
	printf '%s\n' "$*"
}

linker_warn() {
	printf '%s: %s\n' "$LINKER_PROGRAM" "$*" >&2
}

# Print the install location, which is the directory above this module.
linker_root_dir() {
	local source=${BASH_SOURCE[0]}
	local dir
	while [ -L "$source" ]; do
		dir=$(cd -P "$(dirname "$source")" && pwd)
		source=$(readlink "$source")
		if [[ $source != /* ]]; then
			source=$dir/$source
		fi
	done
	dir=$(cd -P "$(dirname "$source")" && pwd)
	(cd -P "$dir/.." && pwd)
}

# Remove every trailing slash from the value of the named variable. The text
# of a link is the identity of that link, so '/src/' and '/src' must not write
# two different texts for one prescribed entry. The root directory keeps its
# single slash.
linker_strip_slashes() {
	local -n path_ref=$1

	while [ "${#path_ref}" -gt 1 ] && [ "${path_ref: -1}" = / ]; do
		path_ref=${path_ref%/}
	done
}

# Resolve every path the module uses, from the environment or from the
# default. Every path comes from here, so a test sets one variable rather than
# a home directory the module reads in several places.
#
# Returns 1 when a path cannot be resolved, is not absolute, holds a control
# character, or aims the module at its own prescribed configuration.
linker_resolve_paths() {
	local home_dir=${HOME:-}
	local name value role quoted

	if [ -n "${XGHOST_CONFIG_SOURCE:-}" ]; then
		LINKER_SOURCE_DIR=$XGHOST_CONFIG_SOURCE
	else
		LINKER_SOURCE_DIR=$(linker_root_dir)/config
	fi

	if [ -n "${XGHOST_CONFIG_HOME:-}" ]; then
		LINKER_CONFIG_HOME=$XGHOST_CONFIG_HOME
	elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
		LINKER_CONFIG_HOME=$XDG_CONFIG_HOME
	elif [ -n "$home_dir" ]; then
		LINKER_CONFIG_HOME=$home_dir/.config
	else
		linker_warn "cannot find the config directory: HOME, XDG_CONFIG_HOME and XGHOST_CONFIG_HOME are all empty"
		return 1
	fi

	if [ -n "${XGHOST_STATE_DIR:-}" ]; then
		LINKER_STATE_DIR=$XGHOST_STATE_DIR
	elif [ -n "${XDG_STATE_HOME:-}" ]; then
		LINKER_STATE_DIR=$XDG_STATE_HOME/$LINKER_PROGRAM
	elif [ -n "$home_dir" ]; then
		LINKER_STATE_DIR=$home_dir/.local/state/$LINKER_PROGRAM
	else
		linker_warn "cannot find the state directory: HOME, XDG_STATE_HOME and XGHOST_STATE_DIR are all empty"
		return 1
	fi

	if [ -n "${XGHOST_BACKUP_DIR:-}" ]; then
		LINKER_BACKUP_DIR=$XGHOST_BACKUP_DIR
	else
		LINKER_BACKUP_DIR=$LINKER_STATE_DIR/backups
	fi

	linker_strip_slashes LINKER_SOURCE_DIR
	linker_strip_slashes LINKER_CONFIG_HOME
	linker_strip_slashes LINKER_STATE_DIR
	linker_strip_slashes LINKER_BACKUP_DIR

	LINKER_RECORD=$LINKER_STATE_DIR/links

	# A relative path would depend on the working directory of the caller,
	# and the link this module writes carries the path as its target.
	for name in LINKER_SOURCE_DIR LINKER_CONFIG_HOME LINKER_STATE_DIR LINKER_BACKUP_DIR; do
		value=${!name}
		if [[ $value != /* ]]; then
			linker_warn "the path '$value' is not absolute; every xghost path override takes an absolute path"
			return 1
		fi
	done

	# The link record is one line per link, with a tab between the two paths.
	# A control character in one of these paths splits one line into two, and
	# 'unlink' would then act on a path this module never wrote. The check
	# covers the resolved path and not only the name of the entry.
	for name in LINKER_SOURCE_DIR LINKER_CONFIG_HOME LINKER_STATE_DIR; do
		value=${!name}
		if [[ $value != *[[:cntrl:]]* ]]; then
			continue
		fi
		case $name in
		LINKER_SOURCE_DIR) role="the prescribed configuration directory" ;;
		LINKER_CONFIG_HOME) role="the config directory" ;;
		*) role="the state directory" ;;
		esac
		printf -v quoted '%q' "$value"
		linker_warn "the path of $role holds a control character, so a link cannot be recorded: $quoted"
		return 1
	done

	# The config directory and the prescribed configuration directory must be
	# two directories. One directory makes every destination its own source,
	# so '--backup' would move the prescribed configuration into the backup
	# and every link would then point at itself. The test is on the file
	# behind each path, because a symbolic link above them reaches the same
	# directory by another name.
	if [ "$LINKER_CONFIG_HOME" -ef "$LINKER_SOURCE_DIR" ]; then
		linker_warn "the config directory $LINKER_CONFIG_HOME and the prescribed configuration directory $LINKER_SOURCE_DIR are the same directory; nothing was changed"
		return 1
	fi
}

# Print what is at one path, in the words the reports use.
linker_describe() {
	local path=$1
	local target

	if [ -L "$path" ]; then
		if ! target=$(readlink -- "$path"); then
			printf 'a symbolic link that cannot be read'
			return 0
		fi
		if [ -e "$path" ]; then
			printf 'a symbolic link to %s' "$target"
		else
			printf 'a broken symbolic link to %s' "$target"
		fi
	elif [ -d "$path" ]; then
		printf 'a directory'
	elif [ -f "$path" ]; then
		printf 'a regular file'
	else
		printf 'neither a regular file nor a directory'
	fi
}

# Return 0 when the path is a symbolic link that points at the given
# prescribed entry.
#
# The first test is on the text of the link, so a link that points at an entry
# which no longer exists still matches. When the text differs, the link still
# matches if it reaches the very file the prescribed path names. A repeated
# slash in an override, or an install location reached through a symbolic
# link, writes a different text for one file, and without this second test
# every such link becomes an orphan that 'unlink' will not remove.
linker_link_matches() {
	local path=$1 want=$2
	local target

	[ -L "$path" ] || return 1
	target=$(readlink -- "$path") || return 1
	[ "$target" = "$want" ] && return 0
	[ -e "$path" ] || return 1
	[ "$path" -ef "$want" ]
}

# Move one path into the backup directory of this run and set
# LINKER_BACKUP_PATH to the exact backup path. The path is moved, never copied
# and never deleted.
#
# The backup directory of the run is created once, and 'mktemp -d' makes it
# unique by construction. Two runs therefore never share one directory, so one
# run can never move its file onto the file of another run. A name that is
# free when it is tested can be taken by the time it is used, so the module
# does not test a name and then act on it.
linker_backup() {
	local path=$1
	local base=${path##*/}
	local stamp target

	LINKER_BACKUP_PATH=

	if [ -z "$LINKER_RUN_BACKUP_DIR" ]; then
		stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
		mkdir -p -- "$LINKER_BACKUP_DIR" || return 1
		LINKER_RUN_BACKUP_DIR=$(mktemp -d "$LINKER_BACKUP_DIR/$stamp.XXXXXX") || return 1
	fi

	LINKER_BACKUP_PATH=$LINKER_RUN_BACKUP_DIR/$base

	# A symbolic link with a relative target is read from the directory that
	# holds it. Inside the backup directory that target reaches another file,
	# or nothing at all. The target is written out in full, so the backup
	# still reaches the file the original link reached.
	if [ -L "$path" ]; then
		target=$(readlink -- "$path") || return 1
		if [[ $target != /* ]]; then
			ln -s -- "${path%/*}/$target" "$LINKER_BACKUP_PATH" || return 1
			rm -- "$path" || return 1
			return 0
		fi
	fi

	mv -n -- "$path" "$LINKER_BACKUP_PATH" || return 1

	# 'mv -n' never overwrites, and it reports success when it did not move.
	# The move is proved rather than assumed, because the caller reports the
	# backup path to the user and then creates a link over the original path.
	if [ -e "$path" ] || [ -L "$path" ]; then
		linker_warn "the backup did not move $path, so the path is still there"
		return 1
	fi
	if [ ! -e "$LINKER_BACKUP_PATH" ] && [ ! -L "$LINKER_BACKUP_PATH" ]; then
		linker_warn "the backup did not arrive at $LINKER_BACKUP_PATH"
		return 1
	fi
}

# Return 0 when the record path is free or is a regular file.
#
# A record path that is a directory takes the write inside it, under the name
# of the temporary file, and the record itself is never written. Every link of
# that run is then a link 'unlink' cannot find and cannot remove, while both
# commands report success. The module refuses the run instead.
linker_check_record_path() {
	local what

	if [ ! -e "$LINKER_RECORD" ] && [ ! -L "$LINKER_RECORD" ]; then
		return 0
	fi
	if [ -f "$LINKER_RECORD" ]; then
		return 0
	fi

	what=$(linker_describe "$LINKER_RECORD")
	linker_warn "the link record $LINKER_RECORD is $what; it must be a regular file. Nothing was changed."
	return 1
}

# Hold an exclusive lock on the state directory for the whole run.
#
# Two runs that read the record together each write back what they read, and
# the run that writes last drops the links of the other one from the record.
# An unrecorded link is a link 'unlink' never removes, so the runs are made to
# follow one another instead.
linker_lock() {
	if ! mkdir -p -- "$LINKER_STATE_DIR"; then
		linker_warn "cannot create the state directory $LINKER_STATE_DIR"
		return 1
	fi
	if ! command -v flock >/dev/null 2>&1; then
		linker_warn "cannot lock the state directory $LINKER_STATE_DIR: the 'flock' command is not on the PATH"
		return 1
	fi
	if ! { exec {LINKER_LOCK_FD}<"$LINKER_STATE_DIR"; } 2>/dev/null; then
		linker_warn "cannot open the state directory $LINKER_STATE_DIR to lock it"
		return 1
	fi
	if ! flock -x "$LINKER_LOCK_FD"; then
		linker_warn "cannot lock the state directory $LINKER_STATE_DIR"
		return 1
	fi
}

# Return 0 when the state directory takes a file this module writes.
#
# The module must know that it can record a link before it creates one,
# because a link it cannot record is a link 'unlink' cannot remove.
linker_probe_state_dir() {
	local probe=$LINKER_RECORD.probe.$$

	if ! { : >"$probe"; } 2>/dev/null; then
		linker_warn "cannot write in the state directory $LINKER_STATE_DIR"
		return 1
	fi
	if ! rm -f -- "$probe"; then
		linker_warn "cannot remove the file $probe from the state directory"
		return 1
	fi
}

# Read the link record into the given array name, one line per element.
#
# The record is opened here rather than by a redirection on a loop, so a
# record that cannot be read is a value this module reports in its own words.
# A failed redirection would end the run where it stands, after part of the
# work, and print nothing but the line number of this file.
#
# Returns 1 when the record exists and cannot be read. A record that is not
# there yet is not a failure.
linker_read_record() {
	local -n record_ref=$1
	local line
	local record_fd

	record_ref=()
	if [ ! -f "$LINKER_RECORD" ]; then
		return 0
	fi
	if ! { exec {record_fd}<"$LINKER_RECORD"; } 2>/dev/null; then
		return 1
	fi
	while IFS= read -r line || [ -n "$line" ]; do
		if [ -n "$line" ]; then
			record_ref+=("$line")
		fi
	done <&"$record_fd"
	exec {record_fd}<&-
}

# Write the link record from the lines held in the given array name. The write
# goes to a temporary file first, so an interrupted write leaves the previous
# record in place.
linker_write_record() {
	local -n lines=$1
	local temp

	linker_check_record_path || return 1
	mkdir -p -- "$LINKER_STATE_DIR" || return 1
	temp=$LINKER_RECORD.$$
	if [ "${#lines[@]}" -gt 0 ]; then
		printf '%s\n' "${lines[@]}" >"$temp" || return 1
	else
		: >"$temp" || return 1
	fi
	mv -- "$temp" "$LINKER_RECORD" || return 1

	# The record is the one thing that makes a link removable, so the write
	# is proved rather than assumed.
	if [ ! -f "$LINKER_RECORD" ]; then
		linker_warn "the link record $LINKER_RECORD is not a regular file after the write"
		return 1
	fi
}

# Link every prescribed entry into the config directory.
#
# Options: --dry-run  report every change and change nothing.
#          --backup   move a path that is in the way into the backup
#                     directory, then link.
linker_link() {
	local dry_run=0 backup=0
	local argument
	local -a names=()
	local -a labels=() sources=() destinations=()
	local -a record_lines=()
	local -a record_existing=()
	local path base name source destination what quoted line index
	local old_destination old_source item seen
	local linked=0 already=0 backed_up=0 conflicts=0 skipped=0 failed=0

	for argument in "$@"; do
		case $argument in
		--dry-run)
			dry_run=1
			;;
		--backup)
			backup=1
			;;
		*)
			linker_warn "unknown option '$argument'. This command takes '--dry-run' and '--backup'."
			return 2
			;;
		esac
	done

	linker_resolve_paths || return 1

	if [ ! -d "$LINKER_SOURCE_DIR" ]; then
		linker_warn "the prescribed configuration directory does not exist: $LINKER_SOURCE_DIR"
		return 1
	fi

	for path in "$LINKER_SOURCE_DIR"/*; do
		# A broken symbolic link fails the -e test. It is an entry of the
		# directory all the same.
		[ -e "$path" ] || [ -L "$path" ] || continue
		base=${path##*/}
		names+=("$base")
	done

	if [ "${#names[@]}" -eq 0 ]; then
		linker_say "no prescribed configuration in $LINKER_SOURCE_DIR; nothing to link"
		return 0
	fi

	if [ -L "$LINKER_CONFIG_HOME" ] && [ ! -e "$LINKER_CONFIG_HOME" ]; then
		linker_warn "the config directory is a broken symbolic link: $LINKER_CONFIG_HOME"
		return 1
	fi
	if [ -e "$LINKER_CONFIG_HOME" ] && [ ! -d "$LINKER_CONFIG_HOME" ]; then
		what=$(linker_describe "$LINKER_CONFIG_HOME")
		linker_warn "the config directory is $what: $LINKER_CONFIG_HOME"
		return 1
	fi

	# Nothing is created before the module knows that it can record what it
	# creates. A link that is not in the record is a link 'unlink' cannot
	# remove, so the record is proved usable first: the state directory takes
	# a file, the record path is a regular file, and the record that is there
	# can be read.
	if [ "$dry_run" -eq 0 ]; then
		linker_lock || return 1
		linker_check_record_path || return 1
		linker_probe_state_dir || return 1
		if ! linker_read_record record_existing; then
			linker_warn "cannot read the link record $LINKER_RECORD; no link was created, because a link this module cannot record is a link 'unlink' cannot remove"
			return 1
		fi
	fi

	if [ "$dry_run" -eq 0 ] && [ ! -d "$LINKER_CONFIG_HOME" ]; then
		if ! mkdir -p -- "$LINKER_CONFIG_HOME"; then
			linker_warn "cannot create the config directory: $LINKER_CONFIG_HOME"
			return 1
		fi
	fi

	# Every link of this run, in the order it is made. The prescribed entries
	# come first, and the bridge to the generated output comes last, so the
	# report reads as the prescribed configuration followed by the one link
	# that serves it.
	#
	# The bridge is created only when there is prescribed configuration to
	# link. Nothing includes the generated output when nothing is prescribed,
	# and the run above has already returned in that case.
	for name in "${names[@]}"; do
		labels+=("$name")
		sources+=("$LINKER_SOURCE_DIR/$name")
		destinations+=("$LINKER_CONFIG_HOME/$name")
	done
	labels+=("$LINKER_BRIDGE_NAME")
	sources+=("$LINKER_STATE_DIR/$LINKER_GENERATED_NAME")
	destinations+=("$LINKER_CONFIG_HOME/$LINKER_BRIDGE_NAME")

	for index in "${!labels[@]}"; do
		name=${labels[index]}
		source=${sources[index]}
		destination=${destinations[index]}

		# The link record is one line per link, with a tab between the two
		# paths. A name that holds a control character cannot be recorded, and
		# a link this module cannot record is a link it cannot remove again.
		if [[ $name == *[[:cntrl:]]* ]]; then
			printf -v quoted '%q' "$name"
			linker_warn "skipped: the name $quoted in $LINKER_SOURCE_DIR holds a control character, so the link cannot be recorded"
			skipped=$((skipped + 1))
			continue
		fi

		if [ -L "$destination" ] && ! readlink -- "$destination" >/dev/null; then
			linker_warn "conflict: $destination is a symbolic link that cannot be read; nothing was changed"
			conflicts=$((conflicts + 1))
			continue
		fi

		if linker_link_matches "$destination" "$source"; then
			linker_say "already linked: $destination"
			already=$((already + 1))
			record_lines+=("$destination"$'\t'"$source")
			continue
		fi

		# The destination and the prescribed entry are one file when the
		# config directory reaches the prescribed configuration directory,
		# by the paths themselves or by a symbolic link above them. Moving
		# the destination aside would move the prescribed configuration into
		# the backup, and the link would then point at itself.
		if [ "$destination" -ef "$source" ]; then
			linker_warn "conflict: $destination and $source are the same file; nothing was changed"
			conflicts=$((conflicts + 1))
			continue
		fi

		if [ -e "$destination" ] || [ -L "$destination" ]; then
			what=$(linker_describe "$destination")
			if [ "$backup" -eq 0 ]; then
				linker_warn "conflict: $destination is $what; nothing was changed. Run the command with '--backup' to move it aside."
				conflicts=$((conflicts + 1))
				continue
			fi
			if [ "$dry_run" -eq 1 ]; then
				linker_say "would move $destination into $LINKER_BACKUP_DIR; it is $what"
				linker_say "would link: $destination -> $source"
				backed_up=$((backed_up + 1))
				linked=$((linked + 1))
				continue
			fi
			if ! linker_backup "$destination"; then
				linker_warn "cannot back up $destination; nothing was changed at that path"
				conflicts=$((conflicts + 1))
				continue
			fi
			# The exact backup path is reported before the link is created.
			linker_say "backup: moved $destination to $LINKER_BACKUP_PATH"
			backed_up=$((backed_up + 1))
		fi

		if [ "$dry_run" -eq 1 ]; then
			linker_say "would link: $destination -> $source"
			linked=$((linked + 1))
			continue
		fi

		# Nothing is in the way at this point, so a link that cannot be
		# created is a failure of this module rather than a conflict with
		# something the user put there.
		if ! ln -s -- "$source" "$destination"; then
			linker_warn "cannot create the symbolic link $destination"
			failed=$((failed + 1))
			continue
		fi
		linker_say "linked: $destination -> $source"
		linked=$((linked + 1))
		record_lines+=("$destination"$'\t'"$source")
	done

	# A link this run did not visit is kept in the record while it is still a
	# link this module created. A prescribed entry that a later release drops
	# is removed by 'unlink' this way.
	for line in ${record_existing[@]+"${record_existing[@]}"}; do
		old_destination=${line%%$'\t'*}
		old_source=${line#*$'\t'}
		[ -n "$old_destination" ] || continue
		# A line without a tab holds no prescribed path.
		[ "$old_source" != "$line" ] || continue
		[ -n "$old_source" ] || continue
		seen=0
		for item in ${record_lines[@]+"${record_lines[@]}"}; do
			if [ "${item%%$'\t'*}" = "$old_destination" ]; then
				seen=1
				break
			fi
		done
		[ "$seen" -eq 0 ] || continue
		if linker_link_matches "$old_destination" "$old_source"; then
			record_lines+=("$old_destination"$'\t'"$old_source")
		fi
	done

	if [ "$dry_run" -eq 0 ]; then
		if [ "${#record_lines[@]}" -gt 0 ] || [ -f "$LINKER_RECORD" ]; then
			if ! linker_write_record record_lines; then
				linker_warn "cannot write the link record $LINKER_RECORD; the links are in place and 'unlink' cannot find them"
				return 1
			fi
		fi
	fi

	if [ "$dry_run" -eq 1 ]; then
		linker_say "dry run: nothing changed. $linked would be linked, $already already linked, $backed_up would be backed up, $conflicts in conflict, $skipped skipped"
	else
		linker_say "summary: $linked linked, $already already linked, $backed_up backed up, $conflicts in conflict, $skipped skipped, $failed failed"
	fi

	if [ "$conflicts" -gt 0 ] || [ "$skipped" -gt 0 ] || [ "$failed" -gt 0 ]; then
		return 1
	fi
}

# Remove the links this module created. Every other path is left alone.
#
# Options: --dry-run  report every change and change nothing.
linker_unlink() {
	local dry_run=0
	local argument
	local -a keep=()
	local -a record_existing=()
	local destination source what line
	local removed=0 left=0 gone=0 failed=0

	for argument in "$@"; do
		case $argument in
		--dry-run)
			dry_run=1
			;;
		*)
			linker_warn "unknown option '$argument'. This command takes '--dry-run'."
			return 2
			;;
		esac
	done

	linker_resolve_paths || return 1

	# The lock makes one run wait for another, so a run that removes links
	# never writes the record over a run that creates them.
	if [ "$dry_run" -eq 0 ] && [ -d "$LINKER_STATE_DIR" ]; then
		linker_lock || return 1
	fi

	if [ ! -e "$LINKER_RECORD" ] && [ ! -L "$LINKER_RECORD" ]; then
		linker_say "no link record at $LINKER_RECORD; nothing to remove"
		return 0
	fi

	# A record path that is there but is not a regular file holds no line
	# this module wrote, and the links it created are still on disk. To
	# report that there is nothing to remove would be a false report.
	linker_check_record_path || return 1

	if ! linker_read_record record_existing; then
		linker_warn "cannot read the link record $LINKER_RECORD; no link was removed"
		return 1
	fi

	for line in ${record_existing[@]+"${record_existing[@]}"}; do
		destination=${line%%$'\t'*}
		source=${line#*$'\t'}
		[ -n "$destination" ] || continue

		if [ "$source" = "$line" ] || [ -z "$source" ]; then
			linker_warn "the link record holds a line with no prescribed path, so the line is dropped: $destination"
			failed=$((failed + 1))
			continue
		fi

		if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
			linker_say "already gone: $destination"
			gone=$((gone + 1))
			continue
		fi

		if ! linker_link_matches "$destination" "$source"; then
			what=$(linker_describe "$destination")
			linker_warn "left alone: $destination is $what; xghost did not create it"
			left=$((left + 1))
			continue
		fi

		if [ "$dry_run" -eq 1 ]; then
			linker_say "would remove: $destination"
			removed=$((removed + 1))
			keep+=("$destination"$'\t'"$source")
			continue
		fi

		# The path is a symbolic link this module recorded, and it still points
		# at the recorded prescribed entry. Removing a symbolic link never
		# touches the file it points at.
		if ! rm -- "$destination"; then
			linker_warn "cannot remove the symbolic link $destination"
			failed=$((failed + 1))
			keep+=("$destination"$'\t'"$source")
			continue
		fi
		linker_say "removed: $destination"
		removed=$((removed + 1))
	done

	if [ "$dry_run" -eq 0 ]; then
		if [ "${#keep[@]}" -eq 0 ]; then
			if ! rm -f -- "$LINKER_RECORD"; then
				linker_warn "cannot remove the link record $LINKER_RECORD"
				failed=$((failed + 1))
			fi
		elif ! linker_write_record keep; then
			linker_warn "cannot write the link record $LINKER_RECORD"
			failed=$((failed + 1))
		fi
	fi

	if [ "$dry_run" -eq 1 ]; then
		linker_say "dry run: nothing changed. $removed would be removed, $left left alone, $gone already gone"
	else
		linker_say "summary: $removed removed, $left left alone, $gone already gone"
	fi

	if [ "$failed" -gt 0 ]; then
		return 1
	fi
}
