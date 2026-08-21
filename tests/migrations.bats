#!/usr/bin/env bats
#
# Tests for the migration runner in lib/migrate.sh.
#
# Nothing here runs a migration of this project. Every test points
# XGHOST_MIGRATIONS_DIR at a fixture directory under tests/fixtures/migrations/,
# and every fixture migration writes into a file of the test and nowhere else. A
# fixture that shipped in migrations/ would be a migration every user runs, so
# none of them lives there.
#
# The state directory is inside the temporary directory of the test, so the
# state of the person running the suite is never read and never written.
#
# What this suite proves, and what each proof rests on:
#
#   - A migration that has been applied does not run again. The fixture records
#     every invocation in a log, so the proof is a count and not a report.
#   - A migration is safe to run twice. The fixture makes its side effect once
#     however often it runs, and the assertion compares the end state of two
#     runs against the end state of one.
#   - An interrupted update is resumed. The fixture is run by hand first, which
#     is the machine a process that died between the side effect and the state
#     write leaves behind, and the runner is then asked to finish.
#   - A failed migration is named, with what it was doing.
#   - A fresh installation replays nothing, and a second installation marks
#     nothing.
bats_require_minimum_version 1.5.0

setup() {
	ROOT_DIR="$BATS_TEST_DIRNAME/.."
	FIXTURES="$BATS_TEST_DIRNAME/fixtures/migrations"
	MIGRATE_LIB="$ROOT_DIR/lib/migrate.sh"

	# Every path this suite writes to comes from here.
	unset XGHOST_STATE_DIR
	unset XGHOST_CONFIG_HOME
	unset XGHOST_ROOT
	unset XGHOST_MIGRATIONS_DIR
	unset BASH_ENV

	# HOME is set first and the XDG variables in statements of their own. A
	# single 'export HOME=... XDG_STATE_HOME=$HOME/...' would read the old HOME,
	# and the new value would be the state directory of the person running the
	# suite.
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/home/.config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/home/.local/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	STATE_DIR="$XDG_STATE_HOME/xghost/migrations"
	APPLIED="$STATE_DIR/applied"
	SKIPPED="$STATE_DIR/skipped"

	# The fixture migrations write here, and a test reads these two files rather
	# than the report of the runner.
	export MIGRATION_LOG="$BATS_TEST_TMPDIR/migration.log"
	export MIGRATION_PACKAGES="$BATS_TEST_TMPDIR/packages"
	: >"$MIGRATION_LOG"
	: >"$MIGRATION_PACKAGES"

	# No test has a terminal to be asked at unless it says so.
	export XGHOST_MIGRATE_TTY="$BATS_TEST_TMPDIR/no-terminal"
}

# Point the runner at one fixture directory.
use_fixture() {
	export XGHOST_MIGRATIONS_DIR="$FIXTURES/$1"
}

# Run one function of the module in a shell of its own.
#
#   in_module 'migrate_run_pending stop'
#
# The module is a library, so it is sourced rather than run. Each call is a
# separate process, which is what keeps the state one call wrote out of the
# variables of the next one.
in_module() {
	bash -c ". '$MIGRATE_LIB'; $1"
}

# The number of times the fixture migrations have been invoked.
invocations() {
	wc -l <"$MIGRATION_LOG"
}

# Print every line of a directory of migrations that names the configuration
# directory of the user, or one of the two files the user owns.
#
# This is the policy check, and its whole reach is stated here: it reads the
# text of a migration for the names a migration has no business writing. A
# migration that builds the same path out of two variables passes it, and so
# does one that calls a program which writes there. It catches the careless
# case, which is the commoner one, and it is not a sandbox. docs/updating.md
# says the same in prose.
policy_offences() {
	local dir=$1
	grep -rnE 'XDG_CONFIG_HOME|\$HOME/\.config|~/\.config|machine\.conf|knobs\.conf' \
		"$dir" 2>/dev/null || true
}

# --- where the state lives ----------------------------------------------------

@test "the migration state lives beside the generated output and not in the config directory" {
	use_fixture pair

	run -0 in_module 'migrate_state_paths; printf "%s\n" "$MIGRATE_STATE_DIR" "$MIGRATE_APPLIED_FILE" "$MIGRATE_SKIPPED_FILE"'

	[ "${lines[0]}" = "$XDG_STATE_HOME/xghost/migrations" ]
	[ "${lines[1]}" = "$XDG_STATE_HOME/xghost/migrations/applied" ]
	[ "${lines[2]}" = "$XDG_STATE_HOME/xghost/migrations/skipped" ]

	# Neither the config directory of the user nor the checkout holds it.
	[[ ${lines[0]} != "$XDG_CONFIG_HOME"* ]]
	[[ ${lines[0]} != "$ROOT_DIR"* ]]
}

@test "a machine with neither XDG_STATE_HOME nor HOME is told the state has no home" {
	use_fixture pair

	run -1 env -u HOME -u XDG_STATE_HOME XGHOST_MIGRATIONS_DIR="$XGHOST_MIGRATIONS_DIR" \
		bash -c ". '$MIGRATE_LIB'; migrate_state_paths || { printf '%s\n' \"\$MIGRATE_PROBLEM\"; exit 1; }"

	[[ $output == *"has no home"* ]]
}

# --- running the pending migrations -------------------------------------------

@test "every pending migration runs once, in the order of its number" {
	use_fixture pair

	run -0 in_module 'migrate_run_pending stop'

	[ "$(invocations)" -eq 2 ]
	[ "$(sed -n 1p "$MIGRATION_LOG")" = 0001 ]
	[ "$(sed -n 2p "$MIGRATION_LOG")" = 0002 ]

	# Both are recorded, in the order they ran.
	[ "$(cut -f1 <"$APPLIED" | sed -n 1p)" = 0001-record-a-package.sh ]
	[ "$(cut -f1 <"$APPLIED" | sed -n 2p)" = 0002-drop-a-package.sh ]
}

@test "a migration that has already run is not run again" {
	use_fixture pair

	run -0 in_module 'migrate_run_pending stop'
	[ "$(invocations)" -eq 2 ]

	run -0 in_module 'migrate_run_pending stop'

	# The second run invoked nothing. A runner that ran them again would leave
	# four lines here.
	[ "$(invocations)" -eq 2 ]
	[ "$(wc -l <"$APPLIED")" -eq 2 ]

	run -0 in_module 'migrate_pending'
	[ -z "$output" ]
}

@test "a migration is safe to run twice: two runs leave the state one run leaves" {
	use_fixture pair

	# The state the machine was in before the migration: it holds the package
	# 0002 drops and not the one 0001 records.
	printf 'the-old-package\n' >"$MIGRATION_PACKAGES"

	run -0 in_module 'migrate_run_pending stop'
	local after_one
	after_one=$(cat "$MIGRATION_PACKAGES")

	# The record is cleared, so the runner offers both again. This is the second
	# run of the migrations themselves, not of the runner over an empty list.
	rm -f "$APPLIED"
	run -0 in_module 'migrate_run_pending stop'

	[ "$(invocations)" -eq 4 ]
	[ "$(cat "$MIGRATION_PACKAGES")" = "$after_one" ]
	[ "$(cat "$MIGRATION_PACKAGES")" = "the-bar-package" ]
}

@test "a migration interrupted between its side effect and its state write runs again and changes nothing more" {
	use_fixture pair

	# The machine a process that died between the two leaves behind: the side
	# effect of 0001 has happened and nothing is recorded.
	bash "$FIXTURES/pair/0001-record-a-package.sh"
	[ "$(invocations)" -eq 1 ]
	[ "$(cat "$MIGRATION_PACKAGES")" = "the-bar-package" ]
	[ ! -f "$APPLIED" ]

	run -0 in_module 'migrate_run_pending stop'

	# It ran again, which is what an unrecorded migration must do.
	[ "$(invocations)" -eq 3 ]
	[ "$(sed -n 2p "$MIGRATION_LOG")" = 0001 ]

	# And it left the machine where the first, interrupted run left it. A
	# migration that appended a second time would leave two lines here.
	[ "$(cat "$MIGRATION_PACKAGES")" = "the-bar-package" ]
	[ "$(wc -l <"$MIGRATION_PACKAGES")" -eq 1 ]

	# The state now records it, so the next update passes over it.
	run -0 grep -qxF 0001-record-a-package.sh <(cut -f1 <"$APPLIED")
}

# --- a migration that fails ---------------------------------------------------

@test "a failed migration is named, with what it was doing and what it declared" {
	use_fixture failing

	run -1 in_module 'migrate_run_pending stop'

	[[ $output == *"0002-fails.sh failed with status 7"* ]]
	[[ $output == *"what it was doing: Enable the unit of the notification centre."* ]]
	[[ $output == *"what it declared: enable-unit"* ]]
	[[ $output == *"$FIXTURES/failing/0002-fails.sh"* ]]
}

@test "the run stops at a failed migration and the migrations after it do not run" {
	use_fixture failing

	run -1 in_module 'migrate_run_pending stop'

	# 0001 ran and 0002 ran and failed. 0003 did not run at all.
	[ "$(invocations)" -eq 2 ]
	run -1 grep -qxF 0003 "$MIGRATION_LOG"

	# The one that succeeded is recorded, so it is not run again. The one that
	# failed is not.
	[ "$(cut -f1 <"$APPLIED")" = 0001-works.sh ]
	[ ! -f "$SKIPPED" ]
}

@test "'skip' records the failure with its reason and carries on to the next migration" {
	use_fixture failing

	run -1 in_module 'migrate_run_pending skip'

	[ "$(invocations)" -eq 3 ]
	[ "$(sed -n 3p "$MIGRATION_LOG")" = 0003 ]

	[ "$(cut -f1 <"$SKIPPED")" = 0002-fails.sh ]
	[[ $(cut -f3 <"$SKIPPED") == *"failed with status 7"* ]]

	# Skipping is not applying.
	run -1 grep -qxF 0002-fails.sh <(cut -f1 <"$APPLIED")
}

@test "a run that skipped a migration ends non-zero, so a caller cannot read it as a clean update" {
	use_fixture failing

	run in_module 'migrate_run_pending skip'
	[ "$status" -eq 1 ]
}

@test "a skipped migration is pending again on the next run" {
	use_fixture failing

	run -1 in_module 'migrate_run_pending skip'

	run -0 in_module 'migrate_pending'
	[ "$output" = 0002-fails.sh ]

	# And it is offered again rather than passed over.
	run -1 in_module 'migrate_run_pending skip'
	[ "$(invocations)" -eq 4 ]
	[ "$(sed -n 4p "$MIGRATION_LOG")" = 0002 ]
	[ "$(wc -l <"$SKIPPED")" -eq 2 ]
}

@test "'ask' takes the answer from the terminal and skips on 'skip'" {
	use_fixture failing
	printf 'skip\n' >"$XGHOST_MIGRATE_TTY"

	run -1 in_module 'migrate_run_pending ask'

	[[ $output == *"skip this migration and carry on, or stop the update?"* ]]
	[ "$(invocations)" -eq 3 ]
	[[ $(cut -f3 <"$SKIPPED") == *"skipped by hand"* ]]
}

@test "'ask' stops on 'stop', and the migrations after the failure do not run" {
	use_fixture failing
	printf 'stop\n' >"$XGHOST_MIGRATE_TTY"

	run -1 in_module 'migrate_run_pending ask'

	[ "$(invocations)" -eq 2 ]
	[ ! -f "$SKIPPED" ]
}

@test "'ask' asks again when the answer is neither, and reads the second answer" {
	use_fixture failing
	printf 'maybe\nskip\n' >"$XGHOST_MIGRATE_TTY"

	run -1 in_module 'migrate_run_pending ask'

	[[ $output == *"answer 'skip' or 'stop'"* ]]
	[ "$(invocations)" -eq 3 ]
}

@test "'ask' with no terminal to ask at stops rather than skipping" {
	use_fixture failing
	# XGHOST_MIGRATE_TTY names a path that holds nothing, so the open fails the
	# way it fails in a timer with no controlling terminal.
	[ ! -e "$XGHOST_MIGRATE_TTY" ]

	run -1 in_module 'migrate_run_pending ask'

	[[ $output == *"no terminal to ask at"* ]]
	[ "$(invocations)" -eq 2 ]
	[ ! -f "$SKIPPED" ]
}

# --- the policy the runner enforces -------------------------------------------

@test "a migration with no metadata block is refused and does not run" {
	use_fixture no-metadata

	run -1 in_module 'migrate_run_pending stop'

	[[ $output == *"is refused"* ]]
	[[ $output == *"no metadata block"* ]]
	[ "$(invocations)" -eq 0 ]
	[ ! -f "$APPLIED" ]
}

@test "a migration that declares an effect outside the policy is refused and does not run" {
	use_fixture bad-effect

	run -1 in_module 'migrate_run_pending stop'

	[[ $output == *"'edit-config-file' is not a permitted effect"* ]]
	[[ $output == *install-package* ]]
	[ "$(invocations)" -eq 0 ]
}

@test "a migration that declares no effect at all is refused" {
	local dir="$BATS_TEST_TMPDIR/no-effect"
	mkdir -p "$dir"
	cat >"$dir/0001-nothing.sh" <<-'M'
		# @xghost-migration
		# summary: A migration that never says what it does.
		# @end-xghost-migration
		printf '0001\n' >>"$MIGRATION_LOG"
	M
	export XGHOST_MIGRATIONS_DIR="$dir"

	run -1 in_module 'migrate_run_pending stop'

	[[ $output == *"declares no permitted 'effect'"* ]]
	[ "$(invocations)" -eq 0 ]
}

@test "an entry of the migration directory that is not a migration is named" {
	local dir="$BATS_TEST_TMPDIR/strange"
	mkdir -p "$dir"
	printf 'notes\n' >"$dir/README"

	run -1 env XGHOST_MIGRATIONS_DIR="$dir" bash -c ". '$MIGRATE_LIB'; migrate_list"
	[[ $output == *"README: not a migration"* ]]

	run -1 env XGHOST_MIGRATIONS_DIR="$dir" bash -c ". '$MIGRATE_LIB'; migrate_run_pending stop"
	[[ $output == *README* ]]
}

@test "no shipped migration names the configuration directory of the user" {
	run -0 bash -c "$(declare -f policy_offences); policy_offences '$ROOT_DIR/migrations'"
	[ -z "$output" ]
}

@test "the policy check reports a migration that writes into the configuration of the user" {
	# The check above is only worth reading if it can report something. This is
	# the same check over a fixture that names the config directory.
	run -0 bash -c "$(declare -f policy_offences); policy_offences '$FIXTURES/writes-config'"
	[[ $output == *0001-edits-a-config-file.sh* ]]
	[[ $output == *XDG_CONFIG_HOME* ]]
}

@test "the shipped migration directory holds no entry that is not a migration" {
	run -0 env XGHOST_MIGRATIONS_DIR="$ROOT_DIR/migrations" \
		bash -c ". '$MIGRATE_LIB'; migrate_list"

	# Every line it printed is a migration file name, and every one of them
	# parses. The directory holds none today, and this is what reads the ones a
	# later slice adds.
	local id
	while IFS= read -r id; do
		[ -n "$id" ] || continue
		run -0 env XGHOST_MIGRATIONS_DIR="$ROOT_DIR/migrations" \
			bash -c ". '$MIGRATE_LIB'; migrate_parse '$ROOT_DIR/migrations/$id'"
	done <<<"$output"
}

# --- a fresh installation -----------------------------------------------------

@test "a fresh installation marks every migration applied and runs none of them" {
	use_fixture pair

	run -0 in_module 'migrate_mark_fresh_install'

	[[ $output == *"marked 2 migrations applied"* ]]
	[ "$(invocations)" -eq 0 ]
	[ "$(wc -l <"$APPLIED")" -eq 2 ]

	# A user who installs today replays nothing.
	run -0 in_module 'migrate_pending'
	[ -z "$output" ]
}

@test "an installation that is not the first one marks nothing" {
	use_fixture pair

	# A machine installed before the second migration was written: it has run
	# the first one and not the second.
	mkdir -p "$STATE_DIR"
	printf '0001-record-a-package.sh\t2026-01-01T00:00:00Z\n' >"$APPLIED"

	run -0 in_module 'migrate_mark_fresh_install'

	[[ $output == *"not a first one"* ]]
	[ "$(wc -l <"$APPLIED")" -eq 1 ]

	# The migration that machine has not run is still pending. Marking it here
	# would take the fix away from that machine in silence.
	run -0 in_module 'migrate_pending'
	[ "$output" = 0002-drop-a-package.sh ]
}

@test "a fresh installation with no migration at all still records that it happened" {
	local dir="$BATS_TEST_TMPDIR/empty"
	mkdir -p "$dir"
	export XGHOST_MIGRATIONS_DIR="$dir"

	run -0 in_module 'migrate_mark_fresh_install'

	# The file is what says this machine has been installed, so the next run of
	# the installer is not read as a first one.
	[ -f "$APPLIED" ]
	[ ! -s "$APPLIED" ]

	run -0 in_module 'migrate_mark_fresh_install'
	[[ $output == *"not a first one"* ]]
}
