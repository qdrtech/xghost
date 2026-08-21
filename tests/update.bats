#!/usr/bin/env bats
#
# Tests for the update path: lib/update.sh and the command that runs it.
#
# Nothing here reaches the machine that runs the suite.
#
#   the pull       Runs for real, against two throwaway repositories inside the
#                  temporary directory of the test. No test pulls the
#                  repository this project is developed in.
#   the packages   A stub AUR helper and a stub pacman, first on the PATH. The
#                  stub pacman answers 'pacman -Q' from a file the test writes,
#                  so the report of what changed is read from a database the
#                  test controls.
#   the components A stub pgrep, pkill, hyprctl and swaync-client, first on the
#                  PATH. Hyprland, the bar, the notification centre and the
#                  terminal are the live session of whoever runs this suite, and
#                  no test may reload or signal any of them. The stub pgrep is
#                  what says which of them is running, so the answer is a fact
#                  of the test rather than of the machine.
#
# tests/setup_suite.bash switches the reload off for every suite of this
# project. This is one of the two files that switch it back on, and it does that
# in the same setup() that installs the stubs.
#   the migrations Fixture migrations under tests/fixtures/migrations/. None of
#                  them touches anything outside the temporary directory.
#
# assert_stubs_are_first is what makes the second and third of those a fact
# rather than an intention. It runs in setup, before any test body, and a PATH
# that does not resolve to the stub fails the test there instead of reaching the
# live session.
#
# The generated output, the link record, the machine facts and the knobs all
# live under a home directory inside the temporary directory of the test.
bats_require_minimum_version 1.5.0

# Build the repository the tests pull from, once for the file.
#
# It is the checkout of this project with its git directory left out, committed
# fresh. A test clones it twice: once into an upstream it may commit into, and
# once into the checkout the update runs against.
setup_file() {
	local root
	root=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	FILE_ORIGIN="$BATS_FILE_TMPDIR/origin"
	export FILE_ORIGIN

	mkdir -p "$FILE_ORIGIN"
	tar -C "$root" --exclude=./.git --exclude=./.claude -cf - . |
		tar -C "$FILE_ORIGIN" -xf -

	git -C "$FILE_ORIGIN" init --quiet -b main
	git -C "$FILE_ORIGIN" add -A
	git -C "$FILE_ORIGIN" \
		-c user.name=xghost -c user.email=xghost@example.invalid \
		commit --quiet -m 'the project before the update'
}

setup() {
	ROOT_DIR="$BATS_TEST_DIRNAME/.."
	FIXTURES="$BATS_TEST_DIRNAME/fixtures"

	# Every path this suite reads or writes comes from here.
	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR
	unset XGHOST_CONFIG_SOURCE
	unset XGHOST_ROOT
	unset XGHOST_THEMES_DIR
	unset XGHOST_TEMPLATE_DIR
	unset XGHOST_KNOBS_SCHEMA
	unset XGHOST_KNOBS_FILE
	unset XGHOST_MACHINE_FACTS
	unset XGHOST_MIGRATIONS_DIR
	unset BASH_ENV

	# HOME is set first, and each XDG variable in a statement of its own. One
	# 'export HOME=... XDG_CONFIG_HOME=$HOME/.config' would read the old HOME
	# and point the linker at the real config directory of whoever runs this.
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/home/.config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/home/.local/state"
	mkdir -p "$XDG_CONFIG_HOME/xghost" "$XDG_STATE_HOME"

	GENERATED="$XDG_STATE_HOME/xghost/generated"
	FACTS="$XDG_CONFIG_HOME/xghost/machine.conf"
	KNOBS="$XDG_CONFIG_HOME/xghost/knobs.conf"
	MIGRATION_STATE="$XDG_STATE_HOME/xghost/migrations"

	# git needs an identity for the commits the tests make upstream, and HOME
	# above holds no configuration file to take one from.
	export GIT_AUTHOR_NAME=xghost
	export GIT_AUTHOR_EMAIL=xghost@example.invalid
	export GIT_COMMITTER_NAME=xghost
	export GIT_COMMITTER_EMAIL=xghost@example.invalid

	# No test has a terminal to be asked at unless it says so.
	export XGHOST_MIGRATE_TTY="$BATS_TEST_TMPDIR/no-terminal"

	UPSTREAM="$BATS_TEST_TMPDIR/upstream"
	CHECKOUT="$BATS_TEST_TMPDIR/checkout"
	git clone --quiet --local "$FILE_ORIGIN" "$UPSTREAM"
	git clone --quiet --local "$UPSTREAM" "$CHECKOUT"

	export XGHOST_ROOT="$CHECKOUT"
	XGHOST="$CHECKOUT/bin/xghost"

	# The migration directory of the checkout holds no migration, which is the
	# state of the project today. A test that wants one points this at a
	# fixture.
	export XGHOST_MIGRATIONS_DIR="$CHECKOUT/migrations"
	export MIGRATION_LOG="$BATS_TEST_TMPDIR/migration.log"
	export MIGRATION_PACKAGES="$BATS_TEST_TMPDIR/packages"
	: >"$MIGRATION_LOG"
	: >"$MIGRATION_PACKAGES"

	stub_programs

	# The whole suite has the reload off, and this is a suite of the step that
	# reloads. The line is here, after stub_programs, because the order is the
	# safety: the switch is only ever on with the stubs already first on the
	# PATH.
	export XGHOST_RELOAD=yes

	assert_stubs_are_first
}

# Put a stub of every program that reaches outside this project first on the
# PATH.
#
# The AUR helper lookup is pinned to the one name that is shadowed, because its
# default names paru as well, and a person who exports XGHOST_UPDATE_HELPERS
# would otherwise have their own helper run.
stub_programs() {
	STUB_DIR="$BATS_TEST_TMPDIR/stub"
	mkdir -p "$STUB_DIR"
	export STUB_DIR
	export XGHOST_UPDATE_HELPERS=yay

	: >"$STUB_DIR/log"

	# The package database of this machine, as 'pacman -Q' prints it.
	printf 'hyprland 0.41.0\nwaybar 0.10.0\n' >"$STUB_DIR/packages"

	cat >"$STUB_DIR/pacman" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		if [ "${1:-}" = -Q ]; then
			cat "$STUB_DIR/packages"
			exit 0
		fi
		printf 'the stub pacman was called with an unexpected verb: %s\n' "$*" >&2
		exit 99
	STUB

	cat >"$STUB_DIR/sudo" <<-'STUB'
		#!/usr/bin/env bash
		exec "$@"
	STUB

	# The stub helper records the call and applies whatever the test asked the
	# update to do to the package database, so the report of what changed is
	# read from a database that really changed.
	cat >"$STUB_DIR/yay" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'yay %s\n' "$*" >>"$STUB_DIR/log"
		if [ -f "$STUB_DIR/packages.after" ]; then
			cp "$STUB_DIR/packages.after" "$STUB_DIR/packages"
		fi
		exit "${YAY_STATUS:-0}"
	STUB

	# The processes this machine is running, one name per line, as the stub
	# pgrep reads them. Every component of the reload table is running unless a
	# test rewrites this file.
	printf 'Hyprland\nwaybar\nswaync\nghostty\n' >"$STUB_DIR/running"

	# The probe lib/reload.sh asks before it signals anything. It answers from
	# the file above, with the exit statuses the real pgrep uses: 0 for a match
	# and 1 for none.
	cat >"$STUB_DIR/pgrep" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'pgrep %s\n' "$*" >>"$STUB_DIR/log"
		# PGREP_STATUS is for the one test that runs on a PATH holding almost
		# nothing, where 'grep' is not reachable. Without it that stub would
		# fail to run and the test would prove the branch for a probe that
		# broke rather than the branch it is aimed at.
		if [ -n "${PGREP_STATUS:-}" ]; then
			exit "$PGREP_STATUS"
		fi
		grep -qxF -- "${!#}" "$STUB_DIR/running"
	STUB

	cat >"$STUB_DIR/hyprctl" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'hyprctl %s\n' "$*" >>"$STUB_DIR/log"
		exit "${HYPRCTL_STATUS:-0}"
	STUB

	cat >"$STUB_DIR/pkill" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'pkill %s\n' "$*" >>"$STUB_DIR/log"
		exit "${PKILL_STATUS:-0}"
	STUB

	cat >"$STUB_DIR/swaync-client" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'swaync-client %s\n' "$*" >>"$STUB_DIR/log"
		exit "${SWAYNC_STATUS:-0}"
	STUB

	chmod +x "$STUB_DIR/pacman" "$STUB_DIR/sudo" "$STUB_DIR/yay" \
		"$STUB_DIR/hyprctl" "$STUB_DIR/pgrep" "$STUB_DIR/pkill" \
		"$STUB_DIR/swaync-client"
	PATH="$STUB_DIR:$PATH"
	export PATH
}

# Fail the test here rather than in the live session.
#
# 'hyprctl reload' and 'pkill -SIGUSR2 waybar' both reach the session of whoever
# runs this suite. A PATH that does not resolve to the stub is the one fault that
# turns a test of this file into a change to that session, so it is checked
# before any test body runs.
#
# 'pgrep' is on the list for a different reason. It signals nothing, so the real
# one is harmless; but it is what decides whether anything is signalled at all,
# and a real pgrep on the machine this desktop runs on answers yes for every
# component. A test that reached it would be a test whose stubs then ran.
assert_stubs_are_first() {
	local name
	for name in pacman sudo yay hyprctl pgrep pkill swaync-client; do
		[ "$(command -v "$name")" = "$STUB_DIR/$name" ] || {
			printf 'the stub %s is not first on the PATH; refusing to run\n' "$name" >&2
			return 1
		}
	done
}

# Give this machine the fixed machine facts and one knob the user has set.
#
# Both files belong to the user. They are here so that a render succeeds, and so
# that the test which asserts an update leaves them alone has something to read.
give_user_files() {
	cp "$FIXTURES/machine/golden.conf" "$FACTS"
	cat >"$KNOBS" <<-'KNOBS'
		# The knobs this machine has set by hand.
		KNOB_GAP_SIZE=20
	KNOBS
}

# Commit one change upstream, so the next pull has something to bring in.
commit_upstream() {
	local message=$1
	git -C "$UPSTREAM" add -A
	git -C "$UPSTREAM" commit --quiet -m "$message"
}

# Run the update.
update() {
	run "$XGHOST" system update "$@"
}

# --- the command --------------------------------------------------------------

@test "the update is a verb of the group 'system'" {
	run -0 "$XGHOST"
	[[ $output == *system* ]]
	[[ $output == *"update"* ]]

	run -0 "$XGHOST" system update --help
	[[ $output == *"Usage: xghost system update"* ]]
}

@test "an option the update does not take is refused" {
	update --no-such-option
	[ "$status" -eq 2 ]
	[[ $output == *"unknown option '--no-such-option'"* ]]

	# Nothing ran.
	[ ! -s "$STUB_DIR/log" ]
}

@test "'--on-failure' refuses a mode that is not one of the three" {
	update --on-failure maybe
	[ "$status" -eq 2 ]
	[[ $output == *"'ask', 'skip' or 'stop'"* ]]
	[ ! -s "$STUB_DIR/log" ]
}

# --- the pull -----------------------------------------------------------------

@test "the update pulls the checkout and reports the commits it brought in" {
	local before after
	before=$(git -C "$CHECKOUT" rev-parse HEAD)

	printf '# a change made upstream\n' >>"$UPSTREAM/README.md"
	commit_upstream 'change the readme'
	after=$(git -C "$UPSTREAM" rev-parse HEAD)

	update

	[ "$(git -C "$CHECKOUT" rev-parse HEAD)" = "$after" ]
	[[ $output == *"project:     ${before:0:7}..${after:0:7}, 1 commits"* ]]
}

@test "an update with nothing to pull says so rather than reporting a change" {
	local head
	head=$(git -C "$CHECKOUT" rev-parse HEAD)

	update

	[[ $output == *"project:     already up to date at ${head:0:7}"* ]]
}

@test "a prescribed file changed upstream reaches the config directory through the pull, with no migration" {
	update
	[ -L "$XDG_CONFIG_HOME/hypr" ] || [ -L "$XDG_CONFIG_HOME/hypr/hyprland.conf" ] ||
		[ -e "$XDG_CONFIG_HOME/hypr" ]

	# One prescribed file gains a line upstream.
	printf '\n# a line the update must deliver\n' >>"$UPSTREAM/config/hypr/hyprland.conf"
	commit_upstream 'add a line to the prescribed hyprland configuration'

	update

	# The line is in the config directory of the user, and no migration was
	# needed to put it there.
	run -0 grep -rqF 'a line the update must deliver' "$XDG_CONFIG_HOME/hypr/"
	[[ $output != *"migrations:  1 applied"* ]]
	[ "$(wc -l <"$MIGRATION_LOG")" -eq 0 ]
}

@test "a prescribed file added upstream is linked by the update" {
	update

	mkdir -p "$UPSTREAM/config/anewapp"
	printf 'the prescribed file of a bundle added upstream\n' \
		>"$UPSTREAM/config/anewapp/anewapp.conf"
	commit_upstream 'add a bundle'

	update

	[ -L "$XDG_CONFIG_HOME/anewapp" ] || [ -L "$XDG_CONFIG_HOME/anewapp/anewapp.conf" ]
	run -0 grep -qF 'added upstream' "$XDG_CONFIG_HOME/anewapp/anewapp.conf"
}

@test "a pull that cannot fast forward stops the update before anything else runs" {
	# Work of the reader's own on the checkout, and a commit upstream that is
	# not its ancestor.
	printf 'local work\n' >>"$CHECKOUT/README.md"
	git -C "$CHECKOUT" add -A
	git -C "$CHECKOUT" commit --quiet -m 'work made on this machine'
	printf 'upstream work\n' >>"$UPSTREAM/README.md"
	commit_upstream 'work made upstream'

	export XGHOST_MIGRATIONS_DIR="$FIXTURES/migrations/pair"

	update

	[ "$status" -eq 1 ]
	[[ $output == *"the pull failed"* ]]

	# No package manager was called, no migration ran, and no component was
	# told anything.
	[ ! -s "$STUB_DIR/log" ]
	[ "$(wc -l <"$MIGRATION_LOG")" -eq 0 ]
	[ ! -e "$MIGRATION_STATE" ]
}

@test "a checkout that git does not know is reported and nothing else runs" {
	rm -rf "$CHECKOUT/.git"

	update

	[ "$status" -eq 1 ]
	[[ $output == *"is not a git working tree"* ]]
	[ ! -s "$STUB_DIR/log" ]
}

# --- what an update never touches ---------------------------------------------

@test "an update leaves the machine facts and the knobs unchanged, byte for byte" {
	give_user_files
	local facts_before knobs_before
	facts_before=$(cksum <"$FACTS")
	knobs_before=$(cksum <"$KNOBS")

	# A real update: a commit to pull, a package to update, and a migration to
	# run.
	printf '\n# a change made upstream\n' >>"$UPSTREAM/config/hypr/hyprland.conf"
	commit_upstream 'change a prescribed file'
	printf 'hyprland 0.42.0\nwaybar 0.10.0\n' >"$STUB_DIR/packages.after"
	export XGHOST_MIGRATIONS_DIR="$FIXTURES/migrations/pair"

	update
	[ "$status" -eq 0 ]

	[ "$(cksum <"$FACTS")" = "$facts_before" ]
	[ "$(cksum <"$KNOBS")" = "$knobs_before" ]

	# And it left no copy of either beside them.
	[ ! -e "$FACTS.previous" ]
	[ ! -e "$KNOBS.previous" ]
}

# --- the packages -------------------------------------------------------------

@test "the update runs the AUR helper and reports what the package database gained" {
	printf 'hyprland 0.42.0\nwaybar 0.10.0\nanewpackage 1.0\n' >"$STUB_DIR/packages.after"

	update

	# One package arrived and one changed version. A report that always said
	# "updated" would say this whatever the database did. The assertion reads
	# the output of the update, so it comes before the next 'run', which
	# replaces it.
	[[ $output == *"packages:    1 installed, 1 upgraded or downgraded, 0 removed"* ]]
	[[ $output != *"pacman -Syu"* ]]

	run -0 grep -qxF 'yay -Syu' "$STUB_DIR/log"
}

@test "the report names a package the update removed" {
	printf 'hyprland 0.41.0\n' >"$STUB_DIR/packages.after"

	update

	[[ ${lines[*]} == *"0 installed, 0 upgraded or downgraded, 1 removed"* ]]
}

@test "a package database that did not change is reported as unchanged" {
	update

	[[ ${lines[*]} == *"0 installed, 0 upgraded or downgraded, 0 removed"* ]]
}

@test "a package manager that fails is reported and the update ends non-zero" {
	export YAY_STATUS=1

	update

	[ "$status" -eq 1 ]
	[[ $output == *"ended with status 1"* ]]

	# The rest of the update still ran: the render and the restart are what put
	# the pulled files in front of the reader.
	run -0 grep -qF 'hyprctl reload' "$STUB_DIR/log"
}

# --- the migrations -----------------------------------------------------------

@test "the pending migrations run during an update and are recorded" {
	export XGHOST_MIGRATIONS_DIR="$FIXTURES/migrations/pair"

	update
	[ "$status" -eq 0 ]

	[ "$(wc -l <"$MIGRATION_LOG")" -eq 2 ]
	[[ $output == *"migrations:  2 applied"* ]]
	[[ $output == *0001-record-a-package.sh* ]]

	# A second update runs neither of them again.
	update
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$MIGRATION_LOG")" -eq 2 ]
	[[ $output == *"migrations:  0 applied, 0 skipped"* ]]
}

@test "a failed migration with no terminal to ask at stops the update" {
	export XGHOST_MIGRATIONS_DIR="$FIXTURES/migrations/failing"
	[ ! -e "$XGHOST_MIGRATE_TTY" ]

	update

	[ "$status" -eq 1 ]
	[[ $output == *"0002-fails.sh failed with status 7"* ]]
	[[ $output == *"the update stopped at the migration 0002-fails.sh"* ]]

	# The migration after the failure did not run, nothing was rendered, and no
	# component was told to read its configuration again.
	[ "$(wc -l <"$MIGRATION_LOG")" -eq 2 ]
	run -1 grep -qF 'hyprctl' "$STUB_DIR/log"
	[[ $output != *"components:"*"reloaded"* ]]
}

@test "'--on-failure skip' carries on past the failure and the update still ends non-zero" {
	export XGHOST_MIGRATIONS_DIR="$FIXTURES/migrations/failing"

	update --on-failure skip

	[ "$status" -eq 1 ]
	[ "$(wc -l <"$MIGRATION_LOG")" -eq 3 ]
	[[ $output == *"migrations:  2 applied"*"1 skipped"* ]]
	[[ $output == *"skipped: 0002-fails.sh"* ]]

	# It carried on to the end.
	run -0 grep -qF 'hyprctl reload' "$STUB_DIR/log"
}

@test "a migration outside the policy stops the update and never runs" {
	export XGHOST_MIGRATIONS_DIR="$FIXTURES/migrations/bad-effect"

	update

	[ "$status" -eq 1 ]
	[[ $output == *"is not a permitted effect"* ]]
	[ "$(wc -l <"$MIGRATION_LOG")" -eq 0 ]
	run -1 grep -qF 'hyprctl' "$STUB_DIR/log"
}

# --- the render ---------------------------------------------------------------

@test "the update renders the active theme again and says whether the output changed" {
	give_user_files
	run -0 "$XGHOST" theme set macos-dark

	# Nothing upstream changed, so the render produces what is already there.
	update
	[ "$status" -eq 0 ]
	[[ $output == *"rendered 'macos-dark'; the output is unchanged"* ]]

	# A template changes upstream, and the same report now says the output
	# changed. This is the pair that makes the line a measurement.
	printf '\n/* a change made upstream */\n' >>"$UPSTREAM/templates/waybar/style.css"
	commit_upstream 'change a template'

	update
	[ "$status" -eq 0 ]
	[[ $output == *"rendered 'macos-dark'; the output changed"* ]]
	run -0 grep -rqF 'a change made upstream' "$GENERATED/waybar/style.css"
}

@test "a machine with no theme yet is told so and the update still ends well" {
	update

	[ "$status" -eq 0 ]
	[[ $output == *"no theme is active"* ]]
}

@test "a generated output that is broken is reported and the update ends non-zero" {
	# The stable path is there and points at nothing. The exit status of
	# 'theme current' is 1 for this and for a machine that has never set a
	# theme, and the two must not be read as the same thing.
	mkdir -p "$XDG_STATE_HOME/xghost"
	ln -s "$BATS_TEST_TMPDIR/a-build-that-is-not-there" "$GENERATED"

	update

	[ "$status" -eq 1 ]
	[[ $output == *"the generated output is broken"* ]]
	[[ $output != *"no theme is active"* ]]
}

# --- the components -----------------------------------------------------------

@test "the update tells every component to read its configuration again" {
	update

	run -0 grep -qxF 'hyprctl reload' "$STUB_DIR/log"
	run -0 grep -qxF "pkill -SIGUSR2 -x -u $EUID waybar" "$STUB_DIR/log"
	run -0 grep -qxF 'swaync-client -rs' "$STUB_DIR/log"
	run -0 grep -qxF "pkill -SIGUSR2 -x -u $EUID ghostty" "$STUB_DIR/log"
}

@test "the reload runs after the render, because it is what shows the render" {
	update

	# The order is the contract of this file. A reload before the render tells
	# the desktop to read the output of the previous one.
	run -0 grep -n 'hyprctl reload' "$STUB_DIR/log"
	local reload=${output%%:*}
	[[ $output == *"hyprctl reload"* ]]

	# The AUR helper is the last thing the update runs before the migrations and
	# the render, so the reload has to come after it.
	run -0 grep -n '^yay ' "$STUB_DIR/log"
	[ "${output%%:*}" -lt "$reload" ]
}

@test "a component that is not running is skipped, and the update still ends well" {
	# The stub probe answers from this file, so this is the machine saying the
	# bar and the notification centre are not running.
	printf 'Hyprland\nghostty\n' >"$STUB_DIR/running"

	update

	[ "$status" -eq 0 ]
	[[ $output == *"waybar: not running"* ]]
	[[ $output == *"swaync: not running"* ]]
	[[ $output == *"hyprland: reloaded"* ]]

	# Neither was signalled. 'swaync-client' is the one that matters: it reaches
	# an activatable D-Bus name, so a call with no daemon running starts one.
	run -1 grep -q 'swaync-client' "$STUB_DIR/log"
	run -1 grep -q 'pkill -SIGUSR2 -x -u '"$EUID"' waybar' "$STUB_DIR/log"
}

@test "a component that is running and failed to reload is reported, and the update ends non-zero" {
	export HYPRCTL_STATUS=1

	update

	# This is the case the table this replaced could not express. It ran
	# 'hyprctl reload', read any non-zero status as "not running", and ended
	# well. A compositor that is there and refused the reload is the one outcome
	# worth acting on, and it was the one outcome that could not be reported.
	[ "$status" -eq 1 ]
	[[ $output == *"hyprland: failed"* ]]
	[[ $output != *"hyprland: not running"* ]]
}

@test "one component that failed does not stop the components after it" {
	export HYPRCTL_STATUS=1

	update

	# The compositor is first in the table and it failed, and all three
	# components after it were still reloaded.
	run -0 grep -qxF "pkill -SIGUSR2 -x -u $EUID waybar" "$STUB_DIR/log"
	run -0 grep -qxF 'swaync-client -rs' "$STUB_DIR/log"
	run -0 grep -qxF "pkill -SIGUSR2 -x -u $EUID ghostty" "$STUB_DIR/log"
}

@test "a component whose program is not installed is reported as such" {
	# This one asks the module rather than running an update, and it asks it
	# with a PATH that reaches none of the programs that signal a component.
	#
	# The reason is a safety rule. Removing a stub does not make a program
	# absent: it reveals the real one, and hyprctl, pkill and swaync-client all
	# reach the live session of whoever runs this suite. A PATH built from
	# nothing is the only way to ask this question that cannot reach a running
	# component. The modules resolve their own directory when they are sourced,
	# and that needs 'dirname', so 'dirname' and the shell itself are what this
	# PATH holds, with a stub probe that answers without reading anything.
	local safe="$BATS_TEST_TMPDIR/safe-path"
	local shell name
	mkdir -p "$safe"
	shell=$(command -v bash)
	ln -s "$(command -v dirname)" "$safe/dirname"
	ln -s "$STUB_DIR/pgrep" "$safe/pgrep"
	ln -s "$shell" "$safe/bash"

	# The assertion that makes the rest of this test safe to run.
	for name in swaync-client hyprctl pkill waybar swaync ghostty Hyprland; do
		run -1 env PATH="$safe" "$shell" -c "command -v $name"
	done

	for name in hyprland waybar swaync ghostty; do
		run -1 env PATH="$safe" STUB_DIR="$STUB_DIR" PGREP_STATUS=0 \
			XGHOST_RELOAD=yes "$shell" -c '
				. "'"$CHECKOUT"'/lib/reload.sh"
				reload_one '"$name"'
				status=$?
				printf "%s\n" "$RELOAD_RESULT"
				exit "$status"
			'
		[ "$output" = "no command" ]
	done
}

@test "the update reports what every component answered" {
	printf 'Hyprland\nwaybar\n' >"$STUB_DIR/running"

	update

	[[ $output == *"components:  hyprland reloaded,waybar reloaded,swaync not running,ghostty not running"* ]]
}

# --- the report ---------------------------------------------------------------

@test "the report names every part of the update" {
	update

	[[ $output == *"what changed:"* ]]
	[[ $output == *"project:"* ]]
	[[ $output == *"links:"* ]]
	[[ $output == *"packages:"* ]]
	[[ $output == *"migrations:"* ]]
	[[ $output == *"generated:"* ]]
	[[ $output == *"components:"* ]]
}
