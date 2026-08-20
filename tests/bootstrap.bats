#!/usr/bin/env bats
#
# Tests for boot.sh, the one command that installs the desktop.
#
# Nothing here installs a package, and nothing here reaches the network.
#
# The package side is shadowed the way tests/install.bats shadows it, and for
# the reason recorded there: a stub first on the PATH is not enough on its own
# when a variable decides which name is looked up. Every lookup boot.sh makes
# was read before this suite was written:
#
#   git      The real program, and every clone here is a clone of a repository
#            this suite built under BATS_TEST_TMPDIR. A local path is not a
#            network fetch, so the clone is a real one and no test depends on
#            GitHub answering.
#   pacman   Shadowed by a stub, which records its command line and installs
#            nothing. No variable moves the name.
#   sudo     Shadowed by a stub, which execs what it was given, so a raised
#            command reaches the stub pacman. No variable moves the name.
#
# The tests where git is missing go further than shadowing. They hand boot.sh a
# PATH that is the stub directory and nothing else, so no pacman, no sudo and no
# AUR helper of the machine that runs the suite is reachable by any name at all,
# and the stub pacman is what puts git on that PATH, exactly as installing the
# package would. XGHOST_AUR_HELPERS is pinned as well: boot.sh looks up no
# helper today, and pinning it is what keeps that true of a test written later.
#
# The stubs and the fixture installer are '#!/bin/sh' and use no external
# program except one absolute path, because a narrowed PATH cannot find
# '/usr/bin/env bash' either.
#
# Two things this suite does not prove:
#
#   - That the documented curl command fetches anything. No test reaches the
#     network. The URL is proved as text: boot.sh, the README and
#     docs/installing.md are asserted to carry the same one, so the three cannot
#     drift apart.
#   - That the hand-off runs the real installer. Every clone here is of a
#     fixture repository whose install.sh records what it was handed, which is
#     what proves the hand-off. That the shipped installer then installs the
#     desktop is what tests/install.bats proves.
#
# The design of the bootstrap is recorded in docs/installing.md.
bats_require_minimum_version 1.5.0

setup() {
	ROOT_DIR="$BATS_TEST_DIRNAME/.."
	BOOT="$ROOT_DIR/boot.sh"

	# Every path this suite writes to comes from here, so no test touches the
	# home directory of the person who runs the suite, and no override that
	# person exports reaches boot.sh.
	unset XGHOST_REPO
	unset XGHOST_INSTALL_DIR
	unset XDG_DATA_HOME

	# boot.sh hands off by exec, and bash sources the file BASH_ENV names into
	# every shell it starts. A person who exports it would put their own file
	# inside the hand-off this suite asserts about.
	unset BASH_ENV

	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"

	# The fixture repository, and the record its install.sh writes.
	REPO="$BATS_TEST_TMPDIR/repo"
	HANDOFF_LOG="$BATS_TEST_TMPDIR/handoff"
	export HANDOFF_LOG

	stub_programs
	make_fixture_repo
}

# Put a stub pacman and a stub sudo first on the PATH.
#
# The stub pacman records what it was called with and installs nothing. Asked
# for git, it puts git on the PATH by linking the real program into the stub
# directory. That is what installing the package does from boot.sh's side, and
# it is what lets the clone which follows be a real one.
stub_programs() {
	STUB_DIR="$BATS_TEST_TMPDIR/stub"
	mkdir -p "$STUB_DIR"
	: >"$STUB_DIR/log"
	export STUB_DIR

	# boot.sh looks up no AUR helper. Pinning the variable to a name that is on
	# no machine keeps a real helper unreachable if that ever changes.
	export XGHOST_AUR_HELPERS=xghost-test-no-such-helper

	# Both are resolved before any PATH is narrowed, because a stub that runs
	# under the narrowed one can no longer find a program by name.
	REAL_GIT=$(command -v git)
	REAL_LN=$(command -v ln)
	export REAL_GIT REAL_LN

	cat >"$STUB_DIR/pacman" <<-'STUB'
		#!/bin/sh
		printf 'pacman %s\n' "$*" >>"$STUB_DIR/log"
		case " $* " in
		*" git "*) "$REAL_LN" -sf "$REAL_GIT" "$STUB_DIR/git" ;;
		esac
		exit 0
	STUB

	cat >"$STUB_DIR/sudo" <<-'STUB'
		#!/bin/sh
		printf 'sudo %s\n' "$*" >>"$STUB_DIR/log"
		exec "$@"
	STUB

	chmod +x "$STUB_DIR/pacman" "$STUB_DIR/sudo"
	PATH="$STUB_DIR:$PATH"
	export PATH

	# The PATH boot.sh is run with. A test that takes git away narrows this one
	# and leaves the PATH of the test body alone, so the body can still read the
	# files it asserts about.
	BOOT_PATH=$PATH
}

# Build the repository every clone of this suite clones.
#
# Its install.sh records the path it was run as and the arguments it was handed,
# so a test reads that record to prove the hand-off happened and what reached
# it.
make_fixture_repo() {
	mkdir -p "$REPO"
	cat >"$REPO/install.sh" <<-'FIXTURE'
		#!/bin/sh
		printf 'ran: %s\n' "$0" >>"$HANDOFF_LOG"
		printf 'args: %s\n' "$*" >>"$HANDOFF_LOG"
	FIXTURE
	chmod +x "$REPO/install.sh"

	git -C "$REPO" init --quiet --initial-branch=main
	git -C "$REPO" add install.sh
	git -C "$REPO" -c user.name=xghost -c user.email=xghost@example.invalid \
		commit --quiet -m 'the fixture installer'

	export XGHOST_REPO=$REPO
}

# Run boot.sh, and require it to finish.
run_boot() {
	run -0 env "PATH=$BOOT_PATH" "$BOOT" "$@"
}

# Run boot.sh, and require it to stop.
run_boot_fails() {
	run -1 env "PATH=$BOOT_PATH" "$BOOT" "$@"
}

# Give the next run a machine that has no git.
#
# The stub directory becomes the whole PATH of that run, so nothing of the
# machine which runs the suite is reachable by name: not git, not pacman, not
# sudo, not an AUR helper.
without_git() {
	rm -f "$STUB_DIR/git"
	BOOT_PATH=$STUB_DIR
}

# Print the lines the stub programs recorded.
stub_log() {
	cat "$STUB_DIR/log"
}

#
# The clone, and where it lands.
#

@test "the bootstrap clones to the documented install location and hands off" {
	run_boot

	[ -f "$HOME/.local/share/xghost/install.sh" ]
	[ -d "$HOME/.local/share/xghost/.git" ]
	[[ $output == *"cloning $REPO into $HOME/.local/share/xghost"* ]]
	[[ $output == *"handing off to $HOME/.local/share/xghost/install.sh"* ]]

	# The hand-off itself, proved by the installer of the clone recording that
	# it ran and the path it ran as.
	run -0 cat "$HANDOFF_LOG"
	[[ $output == *"ran: $HOME/.local/share/xghost/install.sh"* ]]
}

@test "the install location follows XDG_DATA_HOME" {
	export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
	run_boot

	[ -f "$XDG_DATA_HOME/xghost/install.sh" ]
	[ ! -e "$HOME/.local/share/xghost" ]
}

@test "the install location is overridden by XGHOST_INSTALL_DIR" {
	export XGHOST_INSTALL_DIR="$BATS_TEST_TMPDIR/elsewhere/xghost"
	run_boot

	[ -f "$XGHOST_INSTALL_DIR/install.sh" ]
	[ ! -e "$HOME/.local/share" ]
}

@test "the arguments of the bootstrap reach the installer" {
	run_boot --dry-run --theme tokyonight

	run -0 cat "$HANDOFF_LOG"
	[[ $output == *"args: --dry-run --theme tokyonight"* ]]
}

@test "the bootstrap installs nothing itself and configures nothing itself" {
	run_boot

	# git is installed here, so no package operation is reachable at all. The
	# clone is the one thing this script does before the hand-off.
	[ ! -s "$STUB_DIR/log" ]

	# Anything under the home directory of this test other than the clone would
	# be configuration the bootstrap made on its own.
	run -0 find "$HOME" -mindepth 1 -maxdepth 3 \
		-not -path "$HOME/.local" \
		-not -path "$HOME/.local/share" \
		-not -path "$HOME/.local/share/xghost"
	[ -z "$output" ]
}

#
# Running it again.
#

@test "a second run clones nothing and leaves the checkout exactly as it was" {
	run_boot
	printf 'the mark of the first run\n' >"$HOME/.local/share/xghost/mark"

	run_boot
	[[ $output == *"xghost is already cloned to $HOME/.local/share/xghost"* ]]
	[[ $output == *'handing off to'* ]]

	# A pull, a reset or a second clone would each have taken this file away.
	run -0 cat "$HOME/.local/share/xghost/mark"
	[ "$output" = 'the mark of the first run' ]

	# The installer ran both times, because the installer is what makes a second
	# run reach the state the first one was going for.
	run -0 grep -c '^ran: ' "$HANDOFF_LOG"
	[ "$output" -eq 2 ]
}

@test "a second run names the command that updates the checkout" {
	run_boot
	run_boot

	[[ $output == *"git -C $HOME/.local/share/xghost pull"* ]]
}

#
# The install location holds something else.
#

@test "an incomplete clone left by an interrupted run is refused by name" {
	# What a run that was killed part way through leaves behind: the directory
	# is there and the checkout is not.
	mkdir -p "$HOME/.local/share/xghost/.git"
	printf 'ref: refs/heads/main\n' >"$HOME/.local/share/xghost/.git/HEAD"

	run_boot_fails
	[[ $output == *"the clone into $HOME/.local/share/xghost failed"* ]]
	[[ $output == *'what to do:'* ]]
	[[ $output == *'killed part way through'* ]]

	# It removed nothing, and it handed off to nothing.
	[ -f "$HOME/.local/share/xghost/.git/HEAD" ]
	[ ! -e "$HANDOFF_LOG" ]
}

@test "a directory in the way that is no checkout is refused, and nothing in it is touched" {
	mkdir -p "$HOME/.local/share/xghost"
	printf 'not xghost\n' >"$HOME/.local/share/xghost/notes.txt"

	run_boot_fails
	[[ $output == *"the clone into $HOME/.local/share/xghost failed"* ]]

	run -0 cat "$HOME/.local/share/xghost/notes.txt"
	[ "$output" = 'not xghost' ]
}

@test "a clone that cannot be made is reported, and nothing is handed off to" {
	export XGHOST_REPO="$BATS_TEST_TMPDIR/no-such-repository"

	run_boot_fails
	[[ $output == *"the clone into $HOME/.local/share/xghost failed"* ]]
	[[ $output == *'what to do:'* ]]
	[ ! -e "$HANDOFF_LOG" ]
}

@test "an install location whose install.sh cannot be run is refused by name" {
	mkdir -p "$HOME/.local/share/xghost"
	printf 'not runnable\n' >"$HOME/.local/share/xghost/install.sh"
	chmod -x "$HOME/.local/share/xghost/install.sh"

	run_boot_fails
	[[ $output == *'holds no install.sh this can run'* ]]
	[[ $output == *'what to do:'* ]]
	[ ! -e "$HANDOFF_LOG" ]
}

#
# git, when the machine has none.
#

@test "a machine with no git has git installed, and the escalation is announced first" {
	without_git

	run_boot

	[[ $output == *'the next command needs root, and it is the only one this script runs as root:'* ]]
	[[ $output == *'sudo pacman -S --needed -- git'* ]]
	[[ $output == *'sudo asks for your password now'* ]]

	# The command line the escalation announced, and no other package operation.
	run -0 stub_log
	[ "${lines[0]}" = 'sudo pacman -S --needed -- git' ]
	[ "${lines[1]}" = 'pacman -S --needed -- git' ]
	[ "${#lines[@]}" -eq 2 ]

	# git arrived, so the clone and the hand-off both happened.
	[ -f "$HOME/.local/share/xghost/install.sh" ]
	run -0 cat "$HANDOFF_LOG"
	[[ $output == *'ran: '* ]]
}

@test "a machine that has git installs no package at all" {
	run_boot

	[ ! -s "$STUB_DIR/log" ]
	[[ $output != *'needs root'* ]]
}

@test "a machine with no git and no pacman is refused by name" {
	without_git
	rm -f "$STUB_DIR/pacman"

	run_boot_fails
	[[ $output == *"has no 'pacman' to install it with"* ]]
	[[ $output == *'what to do:'* ]]
	[ ! -e "$HOME/.local/share/xghost" ]
}

@test "a machine with no git and no sudo is refused by name" {
	without_git
	rm -f "$STUB_DIR/sudo"

	run_boot_fails
	[[ $output == *"installing a package needs 'sudo'"* ]]
	[[ $output == *'what to do:'* ]]
	[ ! -s "$STUB_DIR/log" ]
	[ ! -e "$HOME/.local/share/xghost" ]
}

@test "a pacman that could not install git stops the run before the clone" {
	without_git
	cat >"$STUB_DIR/pacman" <<-'STUB'
		#!/bin/sh
		printf 'pacman %s\n' "$*" >>"$STUB_DIR/log"
		printf 'error: target not found: git\n' >&2
		exit 1
	STUB
	chmod +x "$STUB_DIR/pacman"

	run_boot_fails
	[[ $output == *'pacman could not install git'* ]]
	[[ $output == *'what to do:'* ]]
	[ ! -e "$HOME/.local/share/xghost" ]
}

#
# An unset HOME, which is the one value the install location cannot be built
# without.
#

@test "an unset HOME is named rather than left to the shell" {
	run -1 env -u HOME -u XDG_DATA_HOME -u XGHOST_INSTALL_DIR \
		"PATH=$BOOT_PATH" "$BOOT"

	[[ $output == *'HOME is not set'* ]]
	[[ $output == *'what to do:'* ]]
	[[ $output != *'unbound variable'* ]]
}

#
# Short enough to read, and documented as such.
#

# The script is what a cautious user reads before piping it into a shell, so its
# length is part of what it promises. The bound is also what stops the bootstrap
# growing into a second installer: work that needs more lines than this belongs
# in a step under install/steps/, where it is grouped, idempotent and tested.
@test "the bootstrap is short enough to read before running it" {
	# A hundred lines is the number the README and docs/installing.md both
	# state, so the bound and the promise move together or not at all.
	run -0 awk 'END { print NR }' "$BOOT"
	[ "$output" -lt 100 ]

	# The lines that are neither blank nor a comment. The comments are there for
	# the reader, so what the script does is counted apart from them.
	run -0 awk '!/^[[:space:]]*(#|$)/ { n++ } END { print n + 0 }' "$BOOT"
	[ "$output" -le 50 ]
}

@test "the bootstrap is POSIX shell, because it runs before anything is installed" {
	run -0 head -n 1 "$BOOT"
	[ "$output" = '#!/bin/sh' ]

	# The bash-only constructs a script written beside the rest of this
	# project's shell would pick up without anyone noticing.
	run grep -nE 'BASH_SOURCE|\[\[|^[[:space:]]*(local|declare|readonly) |\+=\(' "$BOOT"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "the documented command and the script agree on one URL" {
	url='https://raw.githubusercontent.com/qdrtech/xghost/main/boot.sh'

	run -0 grep -qF -- "$url" "$BOOT"
	run -0 grep -qF -- "$url" "$ROOT_DIR/README.md"
	run -0 grep -qF -- "$url" "$ROOT_DIR/docs/installing.md"
}

@test "the documentation shows the one-liner and the read-it-first form" {
	one_liner='sh -c "$(curl -fsSL https://raw.githubusercontent.com/qdrtech/xghost/main/boot.sh)"'

	for page in "$ROOT_DIR/README.md" "$ROOT_DIR/docs/installing.md"; do
		grep -qF -- "$one_liner" "$page" || {
			printf '%s does not show the one command that installs the desktop\n' "$page" >&2
			return 1
		}
		grep -qF -- 'curl -fsSLO' "$page" || {
			printf '%s does not show how to read the script before running it\n' "$page" >&2
			return 1
		}
	done
}

@test "the shipped repository holds the installer the bootstrap hands off to" {
	[ -x "$ROOT_DIR/install.sh" ]
}
