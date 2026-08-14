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
# The module records every link it creates. 'unlink' removes a path only when
# the record holds that path and the path is still a symbolic link to the
# recorded prescribed entry. A symbolic link the user made is not in the
# record, so it is left alone.
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

# The environment may carry BASHOPTS or SHELLOPTS, and both change how the
# globs in this module behave. Normalise every option the module depends on.
shopt -u dotglob nocaseglob failglob
unset GLOBIGNORE
set +f

LINKER_PROGRAM=xghost

# Set by linker_resolve_paths.
LINKER_SOURCE_DIR=
LINKER_CONFIG_HOME=
LINKER_STATE_DIR=
LINKER_BACKUP_DIR=
LINKER_RECORD=

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

# Resolve every path the module uses, from the environment or from the
# default. Every path comes from here, so a test sets one variable rather than
# a home directory the module reads in several places.
#
# Returns 1 when a path cannot be resolved or is not absolute.
linker_resolve_paths() {
	local home_dir=${HOME:-}
	local name value

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

# Return 0 when the path is a symbolic link whose target is exactly the given
# prescribed entry. The comparison is on the text of the link, so a link that
# points at an entry which no longer exists still matches.
linker_link_matches() {
	local path=$1 want=$2
	local target

	[ -L "$path" ] || return 1
	target=$(readlink -- "$path") || return 1
	[ "$target" = "$want" ]
}

# Move one path into the backup directory and print the exact backup path.
# The path is moved, never copied and never deleted.
linker_backup() {
	local path=$1
	local base=${path##*/}
	local stamp dir candidate suffix

	stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
	dir=$LINKER_BACKUP_DIR/$stamp
	candidate=$dir
	suffix=1
	while [ -e "$candidate/$base" ] || [ -L "$candidate/$base" ]; do
		suffix=$((suffix + 1))
		candidate=$dir-$suffix
	done

	mkdir -p -- "$candidate" || return 1
	mv -- "$path" "$candidate/$base" || return 1
	printf '%s\n' "$candidate/$base"
}

# Write the link record from the lines held in the given array name. The write
# goes to a temporary file first, so an interrupted write leaves the previous
# record in place.
linker_write_record() {
	local -n lines=$1
	local temp

	mkdir -p -- "$LINKER_STATE_DIR" || return 1
	temp=$LINKER_RECORD.$$
	if [ "${#lines[@]}" -gt 0 ]; then
		printf '%s\n' "${lines[@]}" >"$temp" || return 1
	else
		: >"$temp" || return 1
	fi
	mv -- "$temp" "$LINKER_RECORD" || return 1
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
	local -a record_lines=()
	local path base name source target destination what backup_path
	local old_destination old_source item seen
	local linked=0 already=0 backed_up=0 conflicts=0 skipped=0

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
	if [ "$dry_run" -eq 0 ] && [ ! -d "$LINKER_CONFIG_HOME" ]; then
		if ! mkdir -p -- "$LINKER_CONFIG_HOME"; then
			linker_warn "cannot create the config directory: $LINKER_CONFIG_HOME"
			return 1
		fi
	fi

	for name in "${names[@]}"; do
		source=$LINKER_SOURCE_DIR/$name
		destination=$LINKER_CONFIG_HOME/$name

		# The link record is one line per link, with a tab between the two
		# paths. A name that holds a control character cannot be recorded, and
		# a link this module cannot record is a link it cannot remove again.
		if [[ $name == *[[:cntrl:]]* ]]; then
			linker_warn "skipped: the name of the entry in $LINKER_SOURCE_DIR holds a control character, so the link cannot be recorded"
			skipped=$((skipped + 1))
			continue
		fi

		if [ -L "$destination" ]; then
			if ! target=$(readlink -- "$destination"); then
				linker_warn "conflict: $destination is a symbolic link that cannot be read; nothing was changed"
				conflicts=$((conflicts + 1))
				continue
			fi
			if [ "$target" = "$source" ]; then
				linker_say "already linked: $destination"
				already=$((already + 1))
				record_lines+=("$destination"$'\t'"$source")
				continue
			fi
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
			if ! backup_path=$(linker_backup "$destination"); then
				linker_warn "cannot back up $destination; nothing was changed at that path"
				conflicts=$((conflicts + 1))
				continue
			fi
			# The exact backup path is reported before the link is created.
			linker_say "backup: moved $destination to $backup_path"
			backed_up=$((backed_up + 1))
		fi

		if [ "$dry_run" -eq 1 ]; then
			linker_say "would link: $destination -> $source"
			linked=$((linked + 1))
			continue
		fi

		if ! ln -s -- "$source" "$destination"; then
			linker_warn "cannot create the symbolic link $destination"
			conflicts=$((conflicts + 1))
			continue
		fi
		linker_say "linked: $destination -> $source"
		linked=$((linked + 1))
		record_lines+=("$destination"$'\t'"$source")
	done

	# A link this run did not visit is kept in the record while it is still a
	# link this module created. A prescribed entry that a later release drops
	# is removed by 'unlink' this way.
	if [ -f "$LINKER_RECORD" ]; then
		while IFS=$'\t' read -r old_destination old_source || [ -n "$old_destination" ]; do
			[ -n "$old_destination" ] || continue
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
		done <"$LINKER_RECORD"
	fi

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
		linker_say "summary: $linked linked, $already already linked, $backed_up backed up, $conflicts in conflict, $skipped skipped"
	fi

	if [ "$conflicts" -gt 0 ] || [ "$skipped" -gt 0 ]; then
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
	local destination source what
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

	if [ ! -f "$LINKER_RECORD" ]; then
		linker_say "no link record at $LINKER_RECORD; nothing to remove"
		return 0
	fi

	while IFS=$'\t' read -r destination source || [ -n "$destination" ]; do
		[ -n "$destination" ] || continue

		if [ -z "$source" ]; then
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
	done <"$LINKER_RECORD"

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
