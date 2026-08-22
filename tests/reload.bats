#!/usr/bin/env bats
#
# Tests for lib/reload.sh, the command that runs it, and the two commands that
# call it after a render.
#
# Nothing here reaches the machine that runs the suite. Every program the module
# can reach is a stub in a directory first on the PATH:
#
#   pgrep          Answers from a file this suite writes, so "the bar is
#                  running" is a fact of the test rather than of the machine.
#   pkill          Records the call. It never signals anything.
#   hyprctl        Records the call, and records its arguments one per line as
#                  well. The wallpaper request carries a path, a path may hold
#                  a space, and a line of the log cannot tell one argument that
#                  holds a space from two that do not.
#   swaync-client  Records the call.
#
# assert_stubs_are_first runs in setup, before any test body, and a PATH that
# does not resolve to the stub fails the test there instead of reaching
# Hyprland, the bar, the notification centre or the terminal of whoever runs
# this.
#
# The suite as a whole has the reload switched off by tests/setup_suite.bash.
# This file is one of the two that turn it back on, and it does that in the same
# setup() that installs the stubs.
#
# docs/reloading.md records what each component reloads and why.
bats_require_minimum_version 1.5.0

setup() {
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)
	XGHOST="$ROOT_DIR/bin/xghost"
	MODULE="$ROOT_DIR/lib/reload.sh"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	unset XGHOST_ROOT
	unset XGHOST_THEMES_DIR
	unset XGHOST_TEMPLATE_DIR
	unset XGHOST_CONFIG_SOURCE
	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR
	unset XGHOST_KNOBS_SCHEMA

	# HOME is set on its own line, and every XDG variable is built from it on a
	# later one. A single 'export HOME=... XDG_CONFIG_HOME="$HOME/..."' reads
	# the OLD HOME, which is the real one, and this project has already written
	# into a real dotfile that way once.
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	use_fixed_machine_facts
	use_own_knobs

	stub_programs

	# This suite is about the reload, so it is the suite that turns it on. The
	# line is here, after stub_programs, because the order is the safety: the
	# switch is only ever on with the stubs already first on the PATH.
	export XGHOST_RELOAD=yes

	assert_stubs_are_first
}

# Put a stub of every program the module can reach first on the PATH.
stub_programs() {
	STUB_DIR="$BATS_TEST_TMPDIR/stub"
	mkdir -p "$STUB_DIR"
	export STUB_DIR

	: >"$STUB_DIR/log"

	# The arguments of the stub hyprctl, one per line, with a count before each
	# call. The log above joins the arguments with a space, so it cannot say
	# whether a path holding a space arrived whole.
	: >"$STUB_DIR/argv"

	# The processes this machine is running, one name per line, as the stub
	# pgrep reads them. A test writes this file to say what is running.
	: >"$STUB_DIR/running"

	# The stub probe. It records the call and answers from the file above, with
	# the exit statuses the real pgrep uses: 0 for a match, 1 for none. A test
	# that wants the third case, a probe that could not answer, sets
	# PGREP_STATUS.
	cat >"$STUB_DIR/pgrep" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'pgrep %s\n' "$*" >>"$STUB_DIR/log"
		if [ -n "${PGREP_STATUS:-}" ]; then
			exit "$PGREP_STATUS"
		fi
		if grep -qxF -- "${!#}" "$STUB_DIR/running"; then
			exit 0
		fi
		exit 1
	STUB

	# The stub signal. It records the call, and it can be told to fail, and to
	# take the process away as it fails, which is the race the module resolves
	# by asking a second time.
	cat >"$STUB_DIR/pkill" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'pkill %s\n' "$*" >>"$STUB_DIR/log"
		if [ -n "${PKILL_STDERR:-}" ]; then
			printf '%s\n' "$PKILL_STDERR" >&2
		fi
		if [ -n "${PKILL_VANISHES:-}" ]; then
			grep -vxF -- "$PKILL_VANISHES" "$STUB_DIR/running" \
				>"$STUB_DIR/running.new" || true
			mv "$STUB_DIR/running.new" "$STUB_DIR/running"
		fi
		exit "${PKILL_STATUS:-0}"
	STUB

	# The real 'hyprctl' writes its errors to standard OUTPUT, so this stub can
	# be told to fail on either stream. Issue #63 exists because the module read
	# standard error alone and threw the cause away.
	cat >"$STUB_DIR/hyprctl" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'hyprctl %s\n' "$*" >>"$STUB_DIR/log"
		printf 'argc %s\n' "$#" >>"$STUB_DIR/argv"
		if [ "$#" -gt 0 ]; then
			printf 'arg %s\n' "$@" >>"$STUB_DIR/argv"
		fi
		if [ -n "${HYPRCTL_STDERR:-}" ]; then
			printf '%s\n' "$HYPRCTL_STDERR" >&2
		fi
		if [ -n "${HYPRCTL_STDOUT:-}" ]; then
			printf '%s\n' "$HYPRCTL_STDOUT"
		fi
		exit "${HYPRCTL_STATUS:-0}"
	STUB

	cat >"$STUB_DIR/swaync-client" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'swaync-client %s\n' "$*" >>"$STUB_DIR/log"
		exit "${SWAYNC_STATUS:-0}"
	STUB

	chmod +x "$STUB_DIR/pgrep" "$STUB_DIR/pkill" "$STUB_DIR/hyprctl" \
		"$STUB_DIR/swaync-client"
	PATH="$STUB_DIR:$PATH"
	export PATH
}

# Fail the test here rather than in the live session.
#
# Every name below reaches the session of whoever runs this suite. A PATH that
# does not resolve to the stub is the one fault that turns a test of this file
# into a change to that session, so it is checked before any test body runs.
assert_stubs_are_first() {
	local name
	for name in pgrep pkill hyprctl swaync-client; do
		[ "$(command -v "$name")" = "$STUB_DIR/$name" ] || {
			printf 'the stub %s is not first on the PATH; refusing to run\n' "$name" >&2
			return 1
		}
	done
}

# Say which processes this machine is running.
running() {
	printf '%s\n' "$@" >"$STUB_DIR/running"
}

# Every component of the shipped table, running.
running_all() {
	running Hyprland waybar swaync ghostty hyprpaper
}

# The image of a build, where a render leaves one.
#
# The wallpaper request names this file, and the module asks whether it is
# there before it sends anything. A test that wants the request sent puts one
# here; a test that wants "nothing to send" leaves the path empty.
a_background() {
	local image=${1:-$XDG_STATE_HOME/xghost/generated/hypr/background.png}

	mkdir -p "${image%/*}"
	printf 'this stands for the image a render draws\n' >"$image"
	printf '%s\n' "$image"
}

# Copy the library of this checkout into a directory of this test, with one
# 'sed' expression applied to lib/reload.sh.
#
# The whole directory is copied because the module sources lib/paths.sh and
# lib/background.sh beside itself: it reads the state directory rule and the
# name of the image from the files that own them rather than keeping a copy of
# either. A copy of reload.sh alone would resolve neither.
module_copy() {
	local expression=$1
	local dir

	dir=$(mktemp -d "$BATS_TEST_TMPDIR/lib.XXXXXX")
	cp "$ROOT_DIR"/lib/*.sh "$dir/"
	sed "$expression" "$ROOT_DIR/lib/reload.sh" >"$dir/reload.sh"
	printf '%s\n' "$dir/reload.sh"
}

# Run one function of the module in this shell, so the variables it sets can be
# read. The module is sourced fresh each time, because it is written to be
# sourced once.
module() {
	# shellcheck source=../lib/reload.sh
	. "$MODULE"
	"$@"
}

# The calls the stubs recorded, without the probe, so a test can read the
# signals alone and in order.
signals() {
	grep -v '^pgrep ' "$STUB_DIR/log" || true
}

# --- the table ----------------------------------------------------------------

@test "every row of the table is four fields, and no field is empty" {
	local row name process program command
	local count=0

	. "$MODULE"
	for row in "${RELOAD_COMPONENTS[@]}"; do
		IFS='|' read -r name process program command <<<"$row"
		[ -n "$name" ]
		[ -n "$process" ]
		[ -n "$program" ]
		[ -n "$command" ]
		# The field count is asserted as well, so a row with a fifth field
		# fails here rather than losing it in silence.
		[ "$(printf '%s\n' "$row" | tr -cd '|' | wc -c)" -eq 3 ]
		count=$((count + 1))
	done

	[ "$count" -eq "${#RELOAD_COMPONENTS[@]}" ]
	[ "$count" -gt 0 ]
}

@test "no process name in the table is longer than the kernel keeps" {
	local row process

	. "$MODULE"
	for row in "${RELOAD_COMPONENTS[@]}"; do
		IFS='|' read -r _ process _ _ <<<"$row"
		[ "${#process}" -le "$RELOAD_COMM_LIMIT" ]
	done
}

@test "the compositor is reloaded first" {
	. "$MODULE"
	[ "${RELOAD_COMPONENTS[0]%%|*}" = hyprland ]
}

# --- one component ------------------------------------------------------------

@test "a running component is reloaded, and the signal names the process" {
	running_all

	module reload_one waybar
	[ "$RELOAD_RESULT" = reloaded ]
	[ -z "$RELOAD_DETAIL" ]

	run -0 grep -qxF 'pkill -SIGUSR2 -x -u '"$EUID"' waybar' "$STUB_DIR/log"
}

@test "the compositor is reloaded with 'hyprctl reload'" {
	running_all

	module reload_one hyprland
	[ "$RELOAD_RESULT" = reloaded ]

	run -0 grep -qxF 'hyprctl reload' "$STUB_DIR/log"
}

@test "the notification centre is reloaded with 'swaync-client -rs'" {
	running_all

	module reload_one swaync
	[ "$RELOAD_RESULT" = reloaded ]

	run -0 grep -qxF 'swaync-client -rs' "$STUB_DIR/log"
}

@test "a running terminal is sent SIGUSR2, which is what Ghostty reloads on" {
	running_all

	module reload_one ghostty
	[ "$RELOAD_RESULT" = reloaded ]

	run -0 grep -qxF 'pkill -SIGUSR2 -x -u '"$EUID"' ghostty' "$STUB_DIR/log"
}

@test "the probe and the signal ask about the processes of this user alone" {
	running_all

	module reload_one waybar

	# Both lines carry the same user, so the answer describes the set of
	# processes the action reaches. Without it the probe finds the bar of this
	# user and the signal reaches the bar of every user on the machine.
	run -0 grep -qxF 'pgrep -x -u '"$EUID"' -- waybar' "$STUB_DIR/log"
	run -0 grep -qxF 'pkill -SIGUSR2 -x -u '"$EUID"' waybar' "$STUB_DIR/log"
}

@test "a component that is not running is skipped, and is not a failure" {
	running Hyprland

	# The status is the whole point of criterion 7: a desktop that is not
	# running is not a failed reload, so reload_one returns 0 here.
	module reload_one waybar
	[ "$RELOAD_RESULT" = "not running" ]
}

@test "a component that is not running is never signalled" {
	running Hyprland waybar ghostty

	module reload_one swaync
	[ "$RELOAD_RESULT" = "not running" ]

	# This is the one that matters most. 'swaync-client' reaches an ACTIVATABLE
	# D-Bus name: /usr/share/dbus-1/services/org.erikreider.swaync.cc.service
	# names 'Exec=/usr/bin/swaync', so a call on a session with no notification
	# daemon does not fail, it STARTS one. A reload that installs a daemon
	# nobody started is not a reload, and asking first is what stops it.
	run -1 grep -q 'swaync-client' "$STUB_DIR/log"
}

@test "a component that fails to reload is reported, with the status and the reason" {
	running_all
	export HYPRCTL_STATUS=1
	export HYPRCTL_STDERR='Couldn'"'"'t connect to the socket'

	run -1 env STUB_DIR="$STUB_DIR" MODULE="$MODULE" \
		HYPRCTL_STATUS=1 HYPRCTL_STDERR="$HYPRCTL_STDERR" PATH="$PATH" \
		bash -c '
			. "$MODULE"
			reload_one hyprland
			status=$?
			printf "%s|%s\n" "$RELOAD_RESULT" "$RELOAD_DETAIL"
			exit "$status"
		'

	[[ $output == *"failed|"* ]]
	[[ $output == *"'hyprctl reload' ended 1"* ]]
	[[ $output == *"Couldn't connect to the socket"* ]]
}

@test "a reload that failed on standard output reports the cause" {
	# 'hyprctl' is the component this matters for: it writes its errors to
	# standard output. The module captured standard error alone, so this
	# diagnostic was thrown away and the reader was told only 'ended 1'.
	running_all

	run -1 env STUB_DIR="$STUB_DIR" MODULE="$MODULE" \
		HYPRCTL_STATUS=1 HYPRCTL_STDOUT='Invalid dispatcher' PATH="$PATH" \
		bash -c '
			. "$MODULE"
			reload_one hyprland
			status=$?
			printf "%s|%s\n" "$RELOAD_RESULT" "$RELOAD_DETAIL"
			exit "$status"
		'

	[[ $output == *"failed|"* ]]
	[[ $output == *"'hyprctl reload' ended 1"* ]]
	[[ $output == *"Invalid dispatcher"* ]]
}

@test "a reload that failed on standard error still reports the cause" {
	# The other direction of the same rule. Keeping both streams must not lose
	# the one that already worked.
	running_all

	run -1 env STUB_DIR="$STUB_DIR" MODULE="$MODULE" \
		HYPRCTL_STATUS=1 HYPRCTL_STDERR='socket is gone' PATH="$PATH" \
		bash -c '
			. "$MODULE"
			reload_one hyprland
			status=$?
			printf "%s|%s\n" "$RELOAD_RESULT" "$RELOAD_DETAIL"
			exit "$status"
		'

	[[ $output == *"failed|"* ]]
	[[ $output == *"socket is gone"* ]]
}

@test "a component that succeeds gains no noise from its output" {
	# Keeping both streams changes the failure report and nothing else. A
	# component that writes to standard output and succeeds is still just
	# 'reloaded', with no detail, exactly as before.
	running_all

	run -0 env STUB_DIR="$STUB_DIR" MODULE="$MODULE" \
		HYPRCTL_STATUS=0 HYPRCTL_STDOUT='ok' PATH="$PATH" \
		bash -c '
			. "$MODULE"
			reload_one hyprland
			status=$?
			printf "%s|%s\n" "$RELOAD_RESULT" "$RELOAD_DETAIL"
			exit "$status"
		'

	[[ $output == "reloaded|" ]]
}

@test "a compositor that is running and refused the reload is not called 'not running'" {
	# The defect this module replaced. update_restart_one ran 'hyprctl reload'
	# and read ANY non-zero status as "not running", so the one outcome worth
	# acting on, a compositor that is there and refused, was reported as the one
	# outcome that needs nothing done.
	running_all
	export HYPRCTL_STATUS=1

	module reload_one hyprland || true
	[ "$RELOAD_RESULT" = failed ]
	[ "$RELOAD_RESULT" != "not running" ]
}

@test "a component that goes away between the probe and the signal is 'not running'" {
	running_all
	export PKILL_STATUS=1
	export PKILL_VANISHES=waybar

	module reload_one waybar

	# 'pkill' ends with 1 when it matched nothing, and the probe had already
	# said the bar was there, so the bar went away in between. Asking a second
	# time is what tells that apart from a bar that refused.
	[ "$RELOAD_RESULT" = "not running" ]
}

@test "a component that is running and whose signal failed is not excused by the second probe" {
	running_all
	export PKILL_STATUS=1

	module reload_one waybar || true
	[ "$RELOAD_RESULT" = failed ]
}

@test "a probe that cannot answer is a problem, and is not read as 'not running'" {
	running_all
	export PGREP_STATUS=2

	module reload_one waybar || true

	# 'pgrep' ends with 1 when it matched nothing and with 2 when it failed, and
	# a plain 'if' reads the two the same. That is the difference between "the
	# bar is not running" and "this machine cannot tell", and reporting the
	# second as the first is how a broken reload looks healthy.
	[ "$RELOAD_RESULT" = failed ]
	[[ $RELOAD_DETAIL == *"could not say whether waybar is running"* ]]
}

@test "a name that is in no row is reported as unknown" {
	running_all

	module reload_one nosuchcomponent || true
	[ "$RELOAD_RESULT" = unknown ]
	[[ $RELOAD_DETAIL == *"not a component this reloads"* ]]
	[ ! -s "$STUB_DIR/log" ]
}

# --- the row is checked before it is run --------------------------------------

@test "a row with an empty process field is refused rather than run" {
	# 'pgrep' with no pattern at all matches every process of the user, so an
	# empty process field would report every component as running and the
	# matching 'pkill' would signal the whole session. It is refused by name.
	local copy
	copy=$(module_copy 's#^\t"waybar|waybar|pkill#\t"waybar||pkill#')
	run -0 grep -qF '"waybar||pkill' "$copy"

	# shellcheck disable=SC1090
	. "$copy"
	run -1 reload_one waybar
	# The assertion above ran in a subshell, so it is asked again for the
	# variables.
	reload_one waybar || true
	[ "$RELOAD_RESULT" = malformed ]
	[[ $RELOAD_DETAIL == *"empty field"* ]]

	# Nothing was run at all.
	[ ! -s "$STUB_DIR/log" ]
}

@test "a row that tests for one program and runs another is refused" {
	# The program field is what is tested for existence and the command is what
	# runs. A row where the two disagree tests one program and runs another, so
	# an installed component reads as one with no command, or a missing one is
	# run.
	local copy
	copy=$(module_copy 's#^\t"waybar|waybar|pkill|pkill #\t"waybar|waybar|killall|pkill #')
	run -0 grep -qF '"waybar|waybar|killall|pkill ' "$copy"

	# shellcheck disable=SC1090
	. "$copy"
	reload_one waybar || true
	[ "$RELOAD_RESULT" = malformed ]
	[[ $RELOAD_DETAIL == *"tests for 'killall' and runs 'pkill'"* ]]
	[ ! -s "$STUB_DIR/log" ]
}

@test "every row of the shipped table runs the program it tests for" {
	local row process program command

	. "$MODULE"
	for row in "${RELOAD_COMPONENTS[@]}"; do
		IFS='|' read -r _ process program command <<<"$row"
		[ "${command%% *}" = "$program" ]
	done
}

@test "a row whose process name is longer than the kernel keeps is refused" {
	local copy
	copy=$(module_copy 's#^\t"waybar|waybar|pkill#\t"waybar|waybar-with-a-very-long-name|pkill#')

	# shellcheck disable=SC1090
	. "$copy"
	reload_one waybar || true
	[ "$RELOAD_RESULT" = malformed ]
	[[ $RELOAD_DETAIL == *"longer than 15 characters"* ]]
	[ ! -s "$STUB_DIR/log" ]
}

# --- a running component whose program is missing -----------------------------

@test "a running component whose program is not installed is a reported problem" {
	# This one asks the module with a PATH that reaches none of the programs
	# that signal a component.
	#
	# The reason is a safety rule this project has already broken once. Removing
	# a stub does not make a program absent: it reveals the real one, and
	# hyprctl, pkill and swaync-client all reach the live session of whoever
	# runs this suite. A PATH built from nothing is the only way to ask this
	# question that cannot reach a running component. The probe is a stub, so
	# the answer is the same on every machine, and 'dirname' is there because a
	# sourced module resolves its own directory.
	local safe="$BATS_TEST_TMPDIR/safe-path"
	local shell name
	mkdir -p "$safe"
	shell=$(command -v bash)
	ln -s "$(command -v dirname)" "$safe/dirname"
	ln -s "$STUB_DIR/pgrep" "$safe/pgrep"
	# The stub probe is a script, and its shebang line names bash, so bash has
	# to be reachable or the probe fails to start and the test proves nothing
	# about the branch it is aimed at. Neither bash nor dirname can signal
	# anything, and the assertion below is what says the PATH holds nothing
	# that can.
	ln -s "$shell" "$safe/bash"
	running_all

	# The assertion that makes the rest of this test safe to run.
	for name in hyprctl pkill swaync-client waybar swaync ghostty Hyprland hyprpaper; do
		run -1 env PATH="$safe" "$shell" -c "command -v $name"
	done

	# The wallpaper daemon is asked here too, and it is asked with an image in
	# place. A missing program and a build with no image are two different
	# answers, and the one this branch is about is the missing program: it is a
	# fault of the installation that nothing else reports.
	a_background >/dev/null

	for name in hyprland waybar swaync ghostty hyprpaper; do
		run -1 env PATH="$safe" STUB_DIR="$STUB_DIR" MODULE="$MODULE" \
			PGREP_STATUS=0 "$shell" -c '
				. "$MODULE"
				reload_one '"$name"'
				status=$?
				printf "%s|%s\n" "$RELOAD_RESULT" "$RELOAD_DETAIL"
				exit "$status"
			'
		[[ $output == "no command|"* ]]
		[[ $output == *"is running and the"* ]]
		[[ $output == *"is not installed"* ]]
	done

	# Nothing was signalled, because nothing could be.
	run -1 grep -qE 'hyprctl|pkill|swaync-client' "$STUB_DIR/log"
}

# --- every component ----------------------------------------------------------

@test "every component is reloaded, and the compositor is first" {
	running_all
	local image
	image=$(a_background)

	module reload_all
	[ "$RELOAD_PROBLEMS" -eq 0 ]

	run -0 signals
	[ "${lines[0]}" = 'hyprctl reload' ]
	[ "${lines[1]}" = "pkill -SIGUSR2 -x -u $EUID waybar" ]
	[ "${lines[2]}" = 'swaync-client -rs' ]
	[ "${lines[3]}" = "pkill -SIGUSR2 -x -u $EUID ghostty" ]
	[ "${lines[4]}" = "hyprctl hyprpaper wallpaper ,$image" ]
	[ "${#lines[@]}" -eq 5 ]
}

@test "one failure does not stop the rest" {
	# No image is put in place here, so the wallpaper daemon has nothing to
	# send and signals nothing. The four signals below are the whole of what
	# this run sends.
	running_all
	export HYPRCTL_STATUS=1

	module reload_all || true

	# The compositor failed and is first in the table, and every component after
	# it was still reloaded. lib/doctor.sh solves the same problem and its
	# header records why: a run whose first failure hides the rest still looks
	# like a report.
	[ "$RELOAD_PROBLEMS" -eq 1 ]
	run -0 signals
	[ "${#lines[@]}" -eq 4 ]
	run -0 grep -qxF "pkill -SIGUSR2 -x -u $EUID waybar" "$STUB_DIR/log"
	run -0 grep -qxF 'swaync-client -rs' "$STUB_DIR/log"
	run -0 grep -qxF "pkill -SIGUSR2 -x -u $EUID ghostty" "$STUB_DIR/log"
}

@test "every component names its own result, and the count is what the status is built from" {
	running Hyprland waybar
	export PKILL_STATUS=1

	run -1 env STUB_DIR="$STUB_DIR" MODULE="$MODULE" PATH="$PATH" \
		PKILL_STATUS=1 bash -c '
			. "$MODULE"
			printf "%s\n" "running: $(cat "$STUB_DIR/running" | tr "\n" " ")"
			reload_all
			status=$?
			printf "problems=%d status=%d\n" "$RELOAD_PROBLEMS" "$status"
			printf "summary=%s\n" "$RELOAD_SUMMARY"
			exit "$status"
		'

	[[ $output == *"hyprland: reloaded"* ]]
	[[ $output == *"waybar: failed"* ]]
	[[ $output == *"swaync: not running"* ]]
	[[ $output == *"ghostty: not running"* ]]
	[[ $output == *"hyprpaper: not running"* ]]
	[[ $output == *"problems=1 status=1"* ]]
	[[ $output == *"summary=hyprland reloaded,waybar failed,swaync not running,ghostty not running,hyprpaper not running"* ]]
}

@test "a run in which nothing is running is not a failure" {
	running

	module reload_all
	[ "$RELOAD_PROBLEMS" -eq 0 ]
	run -1 grep -qE 'hyprctl|pkill|swaync-client' "$STUB_DIR/log"
}

# --- the switch ---------------------------------------------------------------

@test "XGHOST_RELOAD=no stops the reload, and says so where the components would be" {
	running_all
	export XGHOST_RELOAD=no

	run -0 env STUB_DIR="$STUB_DIR" MODULE="$MODULE" PATH="$PATH" \
		XGHOST_RELOAD=no bash -c '. "$MODULE"; reload_all; printf "summary=%s\n" "$RELOAD_SUMMARY"'

	[[ $output == *"reload is off"* ]]
	[[ $output == *"summary=not reloaded"* ]]

	# Not even the probe ran.
	[ ! -s "$STUB_DIR/log" ]
}

@test "a value of XGHOST_RELOAD that is neither 'yes' nor 'no' stops the reload and reports it" {
	running_all

	run -0 env STUB_DIR="$STUB_DIR" MODULE="$MODULE" PATH="$PATH" \
		XGHOST_RELOAD=off bash -c '. "$MODULE"; reload_all'

	# The conservative half: a value nobody meant to write stops a signal rather
	# than sending one, and it is not silent about it.
	[[ $output == *"XGHOST_RELOAD is 'off'"* ]]
	[[ $output == *"'yes' or 'no'"* ]]
	[ ! -s "$STUB_DIR/log" ]
}

@test "the switch is tested in reload_one as well, so a direct caller cannot slip past it" {
	running_all

	run -0 env STUB_DIR="$STUB_DIR" MODULE="$MODULE" PATH="$PATH" \
		XGHOST_RELOAD=no bash -c '. "$MODULE"; reload_one waybar; printf "%s\n" "$RELOAD_RESULT"'

	[ "$output" = off ]
	[ ! -s "$STUB_DIR/log" ]
}

# --- the command --------------------------------------------------------------

@test "the reload is a verb of the group 'system'" {
	run -0 "$XGHOST"
	[[ $output == *system* ]]
	[[ $output == *"reload"* ]]

	run -0 "$XGHOST" system reload --help
	[[ $output == *"Usage: xghost system reload"* ]]
}

@test "'xghost system reload' reloads every running component and ends well" {
	running_all
	a_background >/dev/null

	run -0 "$XGHOST" system reload
	[[ $output == *"hyprland: reloaded"* ]]
	[[ $output == *"ghostty: reloaded"* ]]
	[[ $output == *"hyprpaper: reloaded"* ]]

	run -0 grep -qxF 'hyprctl reload' "$STUB_DIR/log"
}

@test "'xghost system reload' ends 1 when a component failed, and names it" {
	running_all
	export HYPRCTL_STATUS=1

	run -1 "$XGHOST" system reload
	[[ $output == *"hyprland: failed"* ]]
	[[ $output == *"1 of 5 components did not reload"* ]]

	# The exit status of this command is the reload, which is what makes it the
	# one to run again after a failure is fixed.
}

@test "'xghost system reload' ends well when nothing is running" {
	running

	run -0 "$XGHOST" system reload
	[[ $output == *"hyprland: not running"* ]]
}

# --- the two commands that render ---------------------------------------------

# A theme and a template small enough to render in a test, so these tests are
# about the reload rather than about the shipped bundles.
use_own_inputs() {
	export XGHOST_THEMES_DIR="$BATS_TEST_TMPDIR/themes"
	export XGHOST_TEMPLATE_DIR="$BATS_TEST_TMPDIR/templates"
	mkdir -p "$XGHOST_THEMES_DIR/plain" "$XGHOST_TEMPLATE_DIR"
	cat >"$XGHOST_THEMES_DIR/plain/palette.conf" <<-'EOF'
		BG=#1a1b26
		SURFACE=#1f2335
		SURFACE_ALT=#24283b
		TEXT=#c0caf5
		TEXT_MUTED=#565f89
		ACCENT=#7aa2f7
		ACCENT_ALT=#bb9af7
		WARN=#e0af68
		ERROR=#f7768e
		SUCCESS=#9ece6a
	EOF
	printf 'background = @BG@\n' >"$XGHOST_TEMPLATE_DIR/colors.conf"
}

@test "'xghost theme set' reloads the running components after the switch" {
	use_own_inputs
	running_all

	run -0 "$XGHOST" theme set plain
	[[ $output == *"the active theme is now 'plain'"* ]]
	[[ $output == *"reload the running components"* ]]
	[[ $output == *"hyprland: reloaded"* ]]
	[[ $output == *"waybar: reloaded"* ]]
	[[ $output == *"swaync: reloaded"* ]]
	[[ $output == *"ghostty: reloaded"* ]]
	[[ $output == *"hyprpaper: reloaded"* ]]

	run -0 grep -qxF 'hyprctl reload' "$STUB_DIR/log"

	# The switch drew an image, so the wallpaper daemon was told to draw it.
	run -0 grep -qxF \
		"hyprctl hyprpaper wallpaper ,$XDG_STATE_HOME/xghost/generated/hypr/background.png" \
		"$STUB_DIR/log"
}

@test "'xghost theme set' reloads nothing when the render failed" {
	use_own_inputs
	running_all
	# A template that names a value no palette declares fails the render, and a
	# failed render leaves the previous theme whole. There is nothing new to
	# show, so there is nothing to tell anybody to read.
	printf 'background = @NO_SUCH_KEY@\n' >"$XGHOST_TEMPLATE_DIR/colors.conf"

	run -1 "$XGHOST" theme set plain
	[ ! -s "$STUB_DIR/log" ]
}

@test "'xghost theme set' ends well when a component did not reload, and says which" {
	use_own_inputs
	running_all
	export HYPRCTL_STATUS=1

	# The exit status of this command is the theme switch. The theme IS set and
	# the generated output IS in place, so a component that did not take the
	# message is reported rather than turned into a failed switch.
	run -0 "$XGHOST" theme set plain
	[[ $output == *"the active theme is now 'plain'"* ]]
	[[ $output == *"hyprland: failed"* ]]

	# The switch drew an image, so the wallpaper request was sent as well, and
	# the stub fails every 'hyprctl' call of this test.
	[[ $output == *"hyprpaper: failed"* ]]
	[[ $output == *"2 of 5 components did not reload"* ]]
	[[ $output == *"xghost system reload"* ]]
}

@test "'xghost settings set' reloads the running components after the render" {
	use_own_inputs
	running_all
	printf 'font = @KNOB_FONT@\n' >"$XGHOST_TEMPLATE_DIR/colors.conf"

	run -0 "$XGHOST" theme set plain
	: >"$STUB_DIR/log"

	run -0 "$XGHOST" settings set KNOB_FONT 'CaskaydiaCove Nerd Font'
	[[ $output == *"reload the running components"* ]]
	[[ $output == *"waybar: reloaded"* ]]

	run -0 grep -qxF "pkill -SIGUSR2 -x -u $EUID waybar" "$STUB_DIR/log"
}

@test "'xghost settings set' reloads nothing when no theme is active" {
	use_own_inputs
	running_all

	# The value is stored and nothing is rendered, so there is nothing to show.
	run -0 "$XGHOST" settings set KNOB_FONT 'CaskaydiaCove Nerd Font'
	[[ $output == *"no theme is active"* ]]
	[ ! -s "$STUB_DIR/log" ]
}

# --- the wallpaper ------------------------------------------------------------

# The wallpaper daemon is the one component whose command carries a path, and
# the path is a file of the generated output. Every test below asks the module
# with a stub 'hyprctl' first on the PATH, which setup() has already asserted.
#
# What cannot be tested here is the wallpaper itself. The only hyprpaper on this
# machine is the session of whoever runs this suite, and the request this module
# sends CHANGES a wallpaper. docs/reloading.md records that claim as reasoned
# rather than observed, with the four others of its kind.

@test "the wallpaper daemon is told to draw the image of the build" {
	running_all
	local image
	image=$(a_background)

	module reload_one hyprpaper
	[ "$RELOAD_RESULT" = reloaded ]
	[ -z "$RELOAD_DETAIL" ]

	run -0 grep -qxF "hyprctl hyprpaper wallpaper ,$image" "$STUB_DIR/log"
}

@test "the wallpaper request names no monitor, so it reaches every display" {
	# The Hyprland bundle promises that no output name is written into any file
	# or request of this project, and the empty monitor field is what keeps it.
	# hyprpaper reads an empty monitor as every display.
	running_all
	local image
	image=$(a_background)

	module reload_one hyprpaper
	[ "$RELOAD_RESULT" = reloaded ]

	# The arguments, one per line. The request is three of them, and the third
	# starts with the comma that leaves the monitor field empty.
	run -0 grep -qxF 'argc 3' "$STUB_DIR/argv"
	run -0 grep -qxF 'arg hyprpaper' "$STUB_DIR/argv"
	run -0 grep -qxF 'arg wallpaper' "$STUB_DIR/argv"
	run -0 grep -qxF "arg ,$image" "$STUB_DIR/argv"

	# No fit mode is passed. The third argument is optional and hyprpaper uses
	# 'cover' without it, which is the mode the generated wallpaper file names.
	run -1 grep -qxF 'argc 4' "$STUB_DIR/argv"
}

@test "a generated path that holds a space reaches the daemon as one argument" {
	# XDG_STATE_HOME is the user's to set, and a directory name may hold a
	# space. The command of a row is split on white space, so a value put in
	# before the split would arrive as two arguments naming two files that are
	# not there, and hyprpaper would draw neither. The value is put in after
	# the split, one word at a time.
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state dir"
	mkdir -p "$XDG_STATE_HOME"
	running_all

	local image
	image=$(a_background)
	# The floor of this test: without a space in the path it proves nothing.
	[[ $image == *" "* ]]

	module reload_one hyprpaper
	[ "$RELOAD_RESULT" = reloaded ]

	# Three arguments, and the path is the whole of the third. A line of the
	# call log could not tell this apart from four arguments, which is why the
	# stub records them one per line.
	run -0 grep -qxF 'argc 3' "$STUB_DIR/argv"
	run -0 grep -qxF "arg ,$image" "$STUB_DIR/argv"
	run -1 grep -qxF 'argc 4' "$STUB_DIR/argv"
}

@test "the path the request names is the path the wallpaper file names" {
	# The two are written by different modules. lib/theme.sh writes the path
	# into hypr/wallpaper.conf for the daemon to read at start, and
	# lib/reload.sh names it in the request that reaches a daemon already
	# running. Both compose it with xghost_generated_dir of lib/paths.sh, and
	# this is what says they agree.
	#
	# The state directory of this test holds a space as well, so a path built
	# from anything but XDG_STATE_HOME fails here.
	use_own_inputs
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state dir"
	mkdir -p "$XDG_STATE_HOME"
	running_all

	run -0 "$XGHOST" theme set plain
	[[ $output == *"hyprpaper: reloaded"* ]]

	local wallpaper=$XDG_STATE_HOME/xghost/generated/hypr/wallpaper.conf
	local named
	named=$(sed -n 's/^[[:space:]]*path = //p' "$wallpaper")

	# The floor. A file that named no image would make every claim below hold
	# against nothing.
	[ -n "$named" ]
	[[ $named == *" "* ]]
	[ -f "$named" ]

	run -0 grep -qxF "arg ,$named" "$STUB_DIR/argv"
	run -0 grep -qxF 'argc 3' "$STUB_DIR/argv"
}

@test "a build that drew no image is 'nothing to send', and nothing is sent" {
	# The machine facts may carry no resolution, and a palette may declare no
	# colour to draw with. Both are states lib/background.sh supports, and both
	# leave the output with no image. 'failed' would report a supported state
	# as a fault, and 'hyprctl' would fail on a path that is not there.
	running_all
	[ ! -e "$XDG_STATE_HOME/xghost/generated/hypr/background.png" ]

	module reload_one hyprpaper
	[ "$RELOAD_RESULT" = "nothing to send" ]
	[[ $RELOAD_DETAIL == *"drew no wallpaper"* ]]
	[[ $RELOAD_DETAIL == *"hypr/wallpaper.conf"* ]]

	# The probe ran and the request did not.
	run -0 grep -qxF "pgrep -x -u $EUID -- hyprpaper" "$STUB_DIR/log"
	run -1 grep -q 'hyprctl' "$STUB_DIR/log"
	[ ! -s "$STUB_DIR/argv" ]
}

@test "a build with nothing to send is not a problem, and says why on its line" {
	running_all

	run -0 env STUB_DIR="$STUB_DIR" MODULE="$MODULE" PATH="$PATH" \
		HOME="$HOME" XDG_STATE_HOME="$XDG_STATE_HOME" XGHOST_RELOAD=yes \
		bash -c '
			. "$MODULE"
			reload_all
			status=$?
			printf "problems=%d status=%d\n" "$RELOAD_PROBLEMS" "$status"
			printf "summary=%s\n" "$RELOAD_SUMMARY"
		'

	# The reason is on the line of the component. A reader of that report is
	# told which build drew nothing and where the reason for it is written.
	[[ $output == *"hyprpaper: nothing to send: this build drew no wallpaper"* ]]
	[[ $output == *"problems=0 status=0"* ]]
	[[ $output == *"summary="*"hyprpaper nothing to send"* ]]
}

@test "a state directory with no home is reported, and no request is sent" {
	# The one case where this module cannot tell where the generated output is
	# at all. It is a failure rather than "nothing to send", because a machine
	# with neither variable set is not a build that drew no image.
	running_all

	run -1 env -u HOME -u XDG_STATE_HOME STUB_DIR="$STUB_DIR" \
		MODULE="$MODULE" PATH="$PATH" XGHOST_RELOAD=yes bash -c '
			. "$MODULE"
			reload_one hyprpaper
			status=$?
			printf "%s|%s\n" "$RELOAD_RESULT" "$RELOAD_DETAIL"
			exit "$status"
		'

	[[ $output == "failed|"* ]]
	[[ $output == *"neither XDG_STATE_HOME nor HOME is set"* ]]
	run -1 grep -q 'hyprctl' "$STUB_DIR/log"
}

@test "a row that carries a value this file resolves no name for is refused" {
	# A name nothing answers would be sent to the program as itself, and the
	# request would name a file called '@NOSUCH@'. The row is refused instead,
	# by name, in the same way as the three rules the fields keep.
	local copy
	copy=$(module_copy 's#wallpaper ,@BACKGROUND@#wallpaper ,@NOSUCH@#')
	run -0 grep -qF 'wallpaper ,@NOSUCH@' "$copy"
	running_all
	a_background >/dev/null

	# shellcheck disable=SC1090
	. "$copy"
	reload_one hyprpaper || true
	[ "$RELOAD_RESULT" = malformed ]
	[[ $RELOAD_DETAIL == *"'@NOSUCH@'"* ]]
	[[ $RELOAD_DETAIL == *"resolves no value of that name"* ]]

	# Nothing was run at all.
	[ ! -s "$STUB_DIR/log" ]
}

@test "every value the shipped table carries is one the module resolves" {
	local row command name rest
	local count=0

	. "$MODULE"
	for row in "${RELOAD_COMPONENTS[@]}"; do
		command=${row##*|}
		rest=$command
		while [[ $rest =~ $RELOAD_VALUE_PATTERN ]]; do
			name=$BASH_REMATCH
			run -0 reload_value_row "$name"
			rest=${rest#*"$name"}
			count=$((count + 1))
		done
	done

	# The floor. The loop above holds for a table that carries no value at all,
	# and one row carries one today.
	[ "$count" -ge 1 ]
}

# --- criterion 9: adding a component is a one-file change ---------------------

@test "a component added to the table alone is reloaded, and no other file changes" {
	# Acceptance criterion 9 of issue #24 is a design criterion, so its test is
	# a real one: a fictional component is added to a copy of this checkout, and
	# the proof is both halves at once. It reloads, AND the only file that
	# differs from the checkout is lib/reload.sh.
	local case=$BATS_TEST_TMPDIR/case
	mkdir -p "$case"
	tar -C "$ROOT_DIR" --exclude=./.git --exclude=./.claude -cf - . |
		tar -C "$case" -xf -

	cat >"$STUB_DIR/fictionalctl" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'fictionalctl %s\n' "$*" >>"$STUB_DIR/log"
		exit 0
	STUB
	chmod +x "$STUB_DIR/fictionalctl"

	# One row. One file. Nothing else.
	python3 - "$case/lib/reload.sh" <<-'PY'
		import sys
		path = sys.argv[1]
		anchor = '\t"ghostty|ghostty|pkill|pkill -SIGUSR2 -x -u $EUID ghostty"\n'
		text = open(path, encoding="utf-8").read()
		assert text.count(anchor) == 1, "the anchor row moved"
		row = '\t"fictional|fictionald|fictionalctl|fictionalctl reload"\n'
		open(path, "w", encoding="utf-8").write(text.replace(anchor, anchor + row, 1))
	PY

	running Hyprland waybar swaync ghostty fictionald

	run -0 env XGHOST_COMMAND_DIR="$case/commands" "$case/bin/xghost" system reload
	[[ $output == *"fictional: reloaded"* ]]
	run -0 grep -qxF 'fictionalctl reload' "$STUB_DIR/log"

	# The other half of the criterion. 'diff -r' names every file that differs,
	# and the list has to be exactly one.
	run diff -r -q --no-dereference "$ROOT_DIR" "$case" \
		--exclude=.git --exclude=.claude
	[ "${#lines[@]}" -eq 1 ]
	[[ ${lines[0]} == *"lib/reload.sh"* ]]
}
