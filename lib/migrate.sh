#!/usr/bin/env bash
#
# The migration runner: which migrations exist, which have run, and what runs
# next.
#
# A migration is one script in migrations/. ADR 0001 restricts it to system
# side effects: it may install a package, drop a package, enable a unit, set a
# desktop key, or remove a stale generated file. It must not edit a
# configuration file of the user, and it must be safe to run twice.
#
# The state lives beside the generated output, under the state directory of the
# user. It is not in the config directory, because the user owns that, and it is
# not in the checkout, because the checkout holds only what git tracks.
#
#   <state>/xghost/migrations/applied   one line per migration that completed
#   <state>/xghost/migrations/skipped   one line per migration that was passed
#                                       over, with the reason
#
# 'applied' is the authority. A migration named there never runs again. A
# migration named in 'skipped' and not in 'applied' is still pending, so the
# next update runs it again: 'skipped' is a record of what happened, not a
# decision that lasts.
#
# The order of a run is deliberate. The side effect happens first and the state
# is written after it, so a process that dies between the two leaves the
# migration pending and the next update runs it again. That is what "safe to run
# twice" is for. The other order would mark a migration applied whose side
# effect never happened, and nothing would ever run it.
#
# Environment:
#   XGHOST_MIGRATIONS_DIR   The directory of migration scripts. The tests use
#                           this.
#   XDG_STATE_HOME          The state directory, resolved by lib/theme.sh.

# The include sentinel. A second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_MIGRATE_SOURCED:-}" ]; then
	return 0
fi
XGHOST_MIGRATE_SOURCED=1

# The environment may carry BASHOPTS or SHELLOPTS, and both change how the
# globs in this file behave. Normalise every option this file depends on.
shopt -u dotglob nocaseglob failglob
unset GLOBIGNORE
set +f

XGHOST_MIGRATE_LIB_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# theme.sh resolves the state directory of the user, and it is the one place
# that does. The runner puts its state beside the generated output, so it reads
# the same resolution rather than repeating it.
# shellcheck source=lib/theme.sh
. "$XGHOST_MIGRATE_LIB_DIR/theme.sh"

# A migration file is four digits, a hyphen, a name, and '.sh'. The digits are
# what orders the run, and they are wide enough that the order never depends on
# how many migrations the project has written.
readonly MIGRATE_FILE_PATTERN='^[0-9][0-9][0-9][0-9]-[a-z0-9-]+\.sh$'

# The effects a migration may declare. They are the five the migration policy of
# ADR 0001 permits, one word each. A migration that declares anything else is
# refused before it runs.
readonly MIGRATE_EFFECT_VALUES=(
	install-package
	drop-package
	enable-unit
	set-desktop-key
	remove-generated-file
)

# The paths of the state files, set by migrate_state_paths.
MIGRATE_STATE_DIR=
MIGRATE_APPLIED_FILE=
MIGRATE_SKIPPED_FILE=

# Set by migrate_parse.
MIGRATE_SUMMARY=
MIGRATE_EFFECTS=()
MIGRATE_ERRORS=()

# Set by the functions below when they return non-zero.
MIGRATE_PROBLEM=

# The terminal migrate_ask reads the answer from. The tests point it at a file
# of their own, which is what lets a test drive the question without a terminal.
XGHOST_MIGRATE_TTY=${XGHOST_MIGRATE_TTY:-/dev/tty}

# Set by migrate_run_pending: what this run did, for the report of the caller.
MIGRATE_APPLIED_NOW=()
MIGRATE_SKIPPED_NOW=()
MIGRATE_STOPPED_AT=

migrate_say() {
	printf '%s\n' "$*"
}

migrate_warn() {
	printf '%s: %s\n' "$XGHOST_PROGRAM" "$*" >&2
}

# The directory the migration scripts live in.
migrate_dir() {
	theme_repo_paths
	printf '%s\n' "${XGHOST_MIGRATIONS_DIR:-$XGHOST_ROOT/migrations}"
}

# Resolve the state paths. Returns 1 and sets MIGRATE_PROBLEM when the state
# directory has no home.
migrate_state_paths() {
	MIGRATE_PROBLEM=

	if ! theme_state_paths; then
		MIGRATE_PROBLEM=$THEME_PROBLEM
		return 1
	fi

	MIGRATE_STATE_DIR=$XGHOST_STATE_DIR/migrations
	MIGRATE_APPLIED_FILE=$MIGRATE_STATE_DIR/applied
	MIGRATE_SKIPPED_FILE=$MIGRATE_STATE_DIR/skipped
}

# Create the state directory. Returns 1 and sets MIGRATE_PROBLEM when it cannot.
migrate_prepare_state() {
	if ! migrate_state_paths; then
		return 1
	fi
	if [ -d "$MIGRATE_STATE_DIR" ]; then
		return 0
	fi
	if ! mkdir -p "$MIGRATE_STATE_DIR" 2>/dev/null; then
		MIGRATE_PROBLEM="cannot create the migration state directory: $MIGRATE_STATE_DIR"
		return 1
	fi
}

# The time a record carries. It is written in one form everywhere, so two
# records are compared by string.
migrate_now() {
	date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Print the identifier of every migration in the directory, in the order they
# run.
#
# The identifier is the file name. Renaming a migration therefore produces a
# migration nobody has run, so a name that shipped is never changed.
#
# An entry that is not a migration is reported by name and the function returns
# 1. It is never passed over in silence: a file in that directory is there
# because somebody put it there, and the reader is the one who knows which of
# the two it is. Files whose name starts with a dot, such as .gitkeep, are not
# entries.
migrate_list() {
	local dir path base
	local -a names=()
	local status=0

	MIGRATE_PROBLEM=
	dir=$(migrate_dir)

	if [ ! -d "$dir" ]; then
		MIGRATE_PROBLEM="the migration directory does not exist: $dir"
		return 1
	fi

	for path in "$dir"/*; do
		# A broken symbolic link fails the -e test, and it is an entry of the
		# directory all the same.
		[ -e "$path" ] || [ -L "$path" ] || continue
		base=${path##*/}

		if [ -L "$path" ] && [ ! -e "$path" ]; then
			migrate_warn "$base: a broken symbolic link; it points at a target that does not exist"
			status=1
			continue
		fi
		if [ ! -f "$path" ]; then
			migrate_warn "$base: not a regular file; the migration directory is flat"
			status=1
			continue
		fi
		if [[ ! $base =~ $MIGRATE_FILE_PATTERN ]]; then
			migrate_warn "$base: not a migration; a migration is named NNNN-name.sh, in lower case letters, digits and hyphens"
			status=1
			continue
		fi
		names+=("$base")
	done

	if [ "$status" -ne 0 ]; then
		MIGRATE_PROBLEM="the migration directory holds an entry that is not a migration"
		return 1
	fi

	if [ "${#names[@]}" -gt 0 ]; then
		printf '%s\n' "${names[@]}" | LC_ALL=C sort
	fi
}

# Read the metadata block of one migration.
#
#   migrate_parse FILE
#
# The block states what the migration does and which of the five permitted
# effects it has:
#
#   # @xghost-migration
#   # summary: Drop the package the shell no longer reads.
#   # effect: drop-package
#   # @end-xghost-migration
#
# Sets MIGRATE_SUMMARY, MIGRATE_EFFECTS and MIGRATE_ERRORS. Returns 1 when the
# block has at least one problem. Every problem lands in MIGRATE_ERRORS, so one
# reading reports them all.
migrate_parse() {
	local file=$1
	local line key value effect known
	local lineno=0
	local in_block=0 block_count=0 summary_count=0

	MIGRATE_SUMMARY=
	MIGRATE_EFFECTS=()
	MIGRATE_ERRORS=()

	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))

		if [ "$in_block" -eq 0 ]; then
			if [[ $line =~ ^#[[:space:]]*@xghost-migration[[:space:]]*$ ]]; then
				in_block=1
				block_count=$((block_count + 1))
				if [ "$block_count" -gt 1 ]; then
					MIGRATE_ERRORS+=("line $lineno: a second metadata block starts here; a migration has exactly one")
				fi
			fi
			continue
		fi

		if [[ $line =~ ^#[[:space:]]*@end-xghost-migration[[:space:]]*$ ]]; then
			in_block=0
			continue
		fi

		if [[ ! $line =~ ^# ]]; then
			MIGRATE_ERRORS+=("line $lineno: the metadata block holds a line that is not a comment")
			continue
		fi

		if [[ $line =~ ^#[[:space:]]*$ ]]; then
			continue
		fi

		if [[ $line =~ ^#[[:space:]]*([a-z][a-z-]*):[[:space:]]*(.*)$ ]]; then
			key=${BASH_REMATCH[1]}
			value=${BASH_REMATCH[2]}
		else
			MIGRATE_ERRORS+=("line $lineno: expected '# <key>: <value>', found '$line'")
			continue
		fi

		value=${value%"${value##*[![:space:]]}"}

		case $key in
		summary)
			summary_count=$((summary_count + 1))
			if [ "$summary_count" -gt 1 ]; then
				MIGRATE_ERRORS+=("line $lineno: 'summary' is given more than once")
			elif [ -z "$value" ]; then
				MIGRATE_ERRORS+=("line $lineno: 'summary' has no value")
			elif [[ $value == *[[:cntrl:]]* ]]; then
				MIGRATE_ERRORS+=("line $lineno: 'summary' holds a control character; it takes printable characters and spaces only")
			else
				MIGRATE_SUMMARY=$value
			fi
			;;
		effect)
			known=0
			for effect in "${MIGRATE_EFFECT_VALUES[@]}"; do
				if [ "$value" = "$effect" ]; then
					known=1
					break
				fi
			done
			if [ "$known" -eq 0 ]; then
				MIGRATE_ERRORS+=("line $lineno: '$value' is not a permitted effect; ADR 0001 permits ${MIGRATE_EFFECT_VALUES[*]}")
			else
				MIGRATE_EFFECTS+=("$value")
			fi
			;;
		*)
			MIGRATE_ERRORS+=("line $lineno: unknown key '$key'")
			;;
		esac
	done <"$file"

	if [ "$in_block" -eq 1 ]; then
		MIGRATE_ERRORS+=("the metadata block is not closed with '# @end-xghost-migration'")
	fi

	if [ "$block_count" -eq 0 ]; then
		MIGRATE_ERRORS+=("no metadata block; a migration needs a '# @xghost-migration' block that states its summary and its effects")
	else
		if [ "$summary_count" -eq 0 ]; then
			MIGRATE_ERRORS+=("the metadata block has no 'summary' key")
		fi
		if [ "${#MIGRATE_EFFECTS[@]}" -eq 0 ]; then
			MIGRATE_ERRORS+=("the metadata block declares no permitted 'effect'; a migration that has no system side effect is out of the policy of ADR 0001")
		fi
	fi

	[ "${#MIGRATE_ERRORS[@]}" -eq 0 ]
}

# Print the identifier of every applied migration, one per line.
#
# The caller has resolved the state paths. An empty path is a caller that has
# not, and it is refused rather than read as a machine that has applied nothing:
# the second would run every migration again.
migrate_applied() {
	if [ -z "$MIGRATE_APPLIED_FILE" ]; then
		MIGRATE_PROBLEM="the migration state paths are not resolved"
		return 1
	fi
	if [ ! -f "$MIGRATE_APPLIED_FILE" ]; then
		return 0
	fi
	cut -f1 <"$MIGRATE_APPLIED_FILE"
}

# Whether one migration has been applied.
migrate_is_applied() {
	local id=$1
	migrate_applied | grep -qxF -- "$id"
}

# Print the identifier of every migration that is still pending, in the order
# they run.
#
# A migration named in 'skipped' and not in 'applied' is pending. Skipping is
# not applying: the reason a migration was passed over may be gone by the next
# update, so it is offered again.
migrate_pending() {
	local list id

	if ! migrate_state_paths; then
		return 1
	fi

	# The list is captured rather than piped, so a directory that cannot be read
	# fails here. A pipeline would leave the loop with no line to read, and a
	# directory the runner could not read would then look exactly like a
	# directory with nothing left to run.
	if ! list=$(migrate_list); then
		return 1
	fi

	while IFS= read -r id; do
		[ -n "$id" ] || continue
		if ! migrate_is_applied "$id"; then
			printf '%s\n' "$id"
		fi
	done <<<"$list"
}

# Record one migration as applied.
#
# The line is written by one printf, so a reader never sees half of it.
migrate_record_applied() {
	local id=$1
	if ! printf '%s\t%s\n' "$id" "$(migrate_now)" >>"$MIGRATE_APPLIED_FILE"; then
		MIGRATE_PROBLEM="cannot record the applied migration $id in $MIGRATE_APPLIED_FILE"
		return 1
	fi
}

# Record one migration as skipped, with the reason it was passed over.
migrate_record_skipped() {
	local id=$1 reason=$2
	if ! printf '%s\t%s\t%s\n' "$id" "$(migrate_now)" "$reason" >>"$MIGRATE_SKIPPED_FILE"; then
		MIGRATE_PROBLEM="cannot record the skipped migration $id in $MIGRATE_SKIPPED_FILE"
		return 1
	fi
}

# Run one migration and return its status.
#
#   migrate_run_one PATH
#
# The migration runs in a bash of its own rather than in a subshell, and the
# reason is 'set -e'. A subshell that is part of a '||' list runs with -e
# ignored, and bash ignores it for every command inside that subshell, including
# a 'set -e' the subshell runs itself. A migration whose command failed would
# then carry on to its next line and report success. A separate process has its
# own -e, so a migration that fails a command it did not guard stops there.
migrate_run_one() {
	local path=$1
	local status=0

	XGHOST_ROOT=$XGHOST_ROOT \
		XGHOST_STATE_DIR=$XGHOST_STATE_DIR \
		"${BASH:-bash}" -euo pipefail "$path" || status=$?

	return "$status"
}

# Ask the reader whether to skip one failed migration or stop the update.
#
# Returns 0 for skip and 1 for stop. It reads the terminal rather than standard
# input, because an update may be run with its input redirected and the question
# is for the person at the keyboard. The caller has already decided that there
# is a terminal to ask.
migrate_ask() {
	local answer fd status=1

	# The terminal is opened once for the whole question. Opening it inside the
	# loop would read the first answer again after every answer that is neither
	# of the two, and the loop would never end.
	if ! { exec {fd}<"$XGHOST_MIGRATE_TTY"; } 2>/dev/null; then
		migrate_warn "there is no terminal to ask at, so the update stops"
		return 1
	fi

	while true; do
		printf 'skip this migration and carry on, or stop the update? [skip/stop] ' >&2
		if ! IFS= read -r answer <&"$fd"; then
			# The terminal gave end of file. Nobody answered, so the answer is
			# the safe one.
			printf '\n' >&2
			migrate_warn "no answer, so the update stops"
			break
		fi
		case $answer in
		skip | s)
			status=0
			break
			;;
		stop | q)
			status=1
			break
			;;
		*)
			migrate_warn "answer 'skip' or 'stop'"
			;;
		esac
	done

	{ exec {fd}<&-; } 2>/dev/null
	return "$status"
}

# Report one migration that will not run, and why.
migrate_report_refusal() {
	local id=$1
	local error
	migrate_warn "the migration $id is refused: its metadata block has a problem, and the runner will not run a migration that has not declared what it does"
	for error in "${MIGRATE_ERRORS[@]}"; do
		migrate_warn "  $id: $error"
	done
}

# Run every pending migration.
#
#   migrate_run_pending MODE
#
# MODE is what happens when a migration fails: 'ask' puts the question to the
# reader, 'skip' records the failure and carries on, 'stop' ends the run. The
# caller resolves 'ask' to 'stop' when there is no terminal to ask at.
#
# Sets MIGRATE_APPLIED_NOW, MIGRATE_SKIPPED_NOW and MIGRATE_STOPPED_AT.
# Returns 1 when the run stopped or when at least one migration was skipped,
# because neither of those is an update that did what it was asked.
migrate_run_pending() {
	local mode=$1
	local dir id path status reason
	local -a pending=()

	MIGRATE_APPLIED_NOW=()
	MIGRATE_SKIPPED_NOW=()
	MIGRATE_STOPPED_AT=
	MIGRATE_PROBLEM=

	if ! migrate_prepare_state; then
		return 1
	fi

	dir=$(migrate_dir)

	local list
	if ! list=$(migrate_pending); then
		MIGRATE_PROBLEM=${MIGRATE_PROBLEM:-"the migration directory cannot be read, so no migration ran"}
		return 1
	fi

	while IFS= read -r id; do
		[ -n "$id" ] || continue
		pending+=("$id")
	done <<<"$list"

	if [ "${#pending[@]}" -eq 0 ]; then
		return 0
	fi

	for id in "${pending[@]}"; do
		path=$dir/$id

		# The metadata is what the failure report reads from, and it is what
		# says the migration is inside the policy. A migration that has not
		# declared its effect does not run at all.
		if ! migrate_parse "$path"; then
			migrate_report_refusal "$id"
			MIGRATE_STOPPED_AT=$id
			MIGRATE_PROBLEM="the migration $id is not well formed, so the run stopped before it"
			return 1
		fi

		migrate_say "-- $id: $MIGRATE_SUMMARY"

		status=0
		migrate_run_one "$path" || status=$?

		if [ "$status" -eq 0 ]; then
			if ! migrate_record_applied "$id"; then
				return 1
			fi
			MIGRATE_APPLIED_NOW+=("$id")
			continue
		fi

		# The report names the migration, what it was doing, and the effects it
		# declared, because "a migration failed" sends the reader to the
		# directory and nowhere else.
		migrate_warn "the migration $id failed with status $status"
		migrate_warn "  what it was doing: $MIGRATE_SUMMARY"
		migrate_warn "  what it declared: ${MIGRATE_EFFECTS[*]}"
		migrate_warn "  the file: $path"

		reason="failed with status $status"

		case $mode in
		skip) ;;
		ask)
			if ! migrate_ask; then
				MIGRATE_STOPPED_AT=$id
				MIGRATE_PROBLEM="the migration $id failed and the update stopped at it"
				return 1
			fi
			reason="failed with status $status, and it was skipped by hand"
			;;
		*)
			MIGRATE_STOPPED_AT=$id
			MIGRATE_PROBLEM="the migration $id failed and the update stopped at it"
			return 1
			;;
		esac

		if ! migrate_record_skipped "$id" "$reason"; then
			return 1
		fi
		MIGRATE_SKIPPED_NOW+=("$id")
		migrate_warn "$id was skipped. It is still pending, so the next update runs it again."
	done

	if [ "${#MIGRATE_SKIPPED_NOW[@]}" -gt 0 ]; then
		MIGRATE_PROBLEM="${#MIGRATE_SKIPPED_NOW[@]} migrations were skipped"
		return 1
	fi
}

# Mark every migration applied without running one, for a fresh installation.
#
# A new user replays nothing. The prescribed configuration they just checked out
# is already the current one, and every historical migration was written to move
# a machine from a state this one was never in.
#
# It runs on a fresh installation and on no other. The test is the state
# directory: an installation that finds one has been installed before, and
# marking its pending migrations applied would take a fix away from that machine
# in silence. So a second run of the installer changes nothing here.
#
# Returns 1 and sets MIGRATE_PROBLEM when the state cannot be written.
migrate_mark_fresh_install() {
	local id
	local -a ids=()

	MIGRATE_PROBLEM=

	if ! migrate_state_paths; then
		return 1
	fi

	if [ -d "$MIGRATE_STATE_DIR" ]; then
		migrate_say "the migration state is already recorded in $MIGRATE_STATE_DIR, so this installation is not a first one and nothing was marked"
		return 0
	fi

	local list
	if ! list=$(migrate_list); then
		MIGRATE_PROBLEM="the migration directory cannot be read, so nothing was marked"
		return 1
	fi

	while IFS= read -r id; do
		[ -n "$id" ] || continue
		ids+=("$id")
	done <<<"$list"

	if ! migrate_prepare_state; then
		return 1
	fi

	# The file is created even when there is no migration to record, because its
	# absence is what says "this machine has never been installed".
	if ! : >>"$MIGRATE_APPLIED_FILE"; then
		MIGRATE_PROBLEM="cannot create $MIGRATE_APPLIED_FILE"
		return 1
	fi

	for id in "${ids[@]:-}"; do
		[ -n "$id" ] || continue
		if ! migrate_record_applied "$id"; then
			return 1
		fi
	done

	migrate_say "marked ${#ids[@]} migrations applied without running one, because this is a first installation"
}
