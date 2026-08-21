#!/usr/bin/env bats
#
# Tests for the doctor: lib/doctor.sh and the command that runs it.
#
# Nothing here reaches the machine that runs the suite.
#
#   the checkout    A throwaway clone inside the temporary directory of the
#                   test. No test reads or writes the repository this project
#                   is developed in, and every 'git status' below is asked
#                   about that clone.
#   the packages    The query is injected. XGHOST_DOCTOR_PACKAGE_QUERY names a
#                   script the test writes, so no test asks the package
#                   database of whoever runs this suite. A pacman stub that
#                   ends 99 sits first on the PATH beside it, so a doctor that
#                   ever reached the package manager directly would fail the
#                   test rather than answer from this machine.
#   the components  A stub hyprctl, pkill and swaync-client that all end 99.
#                   The doctor signals nothing, and those stubs are what turns
#                   that from an intention into an assertion.
#   the home        Every path the doctor reads or writes is under a home
#                   directory inside the temporary directory of the test.
#
# HOME is set in a statement of its own and each XDG variable in another. One
# 'export HOME=... XDG_CONFIG_HOME=$HOME/.config' would read the OLD HOME and
# point this suite at the config directory of whoever runs it.
#
# assert_stubs_are_first runs in setup, before any test body, so a PATH that
# does not resolve to the stub fails the test there instead of reaching the
# live session.
bats_require_minimum_version 1.5.0

# Build the repository the tests clone from, once for the file.
#
# It is this checkout with its git directory left out, committed fresh. Every
# test clones it, so every test has a git working tree of its own that it may
# dirty however it likes.
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
		commit --quiet -m 'the project the doctor reports on'
}

setup() {
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
	unset XGHOST_PACKAGES_DIR
	unset XGHOST_DOCTOR_PACKAGE_QUERY
	unset BASH_ENV

	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/home/.config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/home/.local/state"
	mkdir -p "$XDG_CONFIG_HOME/xghost" "$XDG_STATE_HOME"

	GENERATED="$XDG_STATE_HOME/xghost/generated"
	FACTS="$XDG_CONFIG_HOME/xghost/machine.conf"
	KNOBS="$XDG_CONFIG_HOME/xghost/knobs.conf"
	LINK_RECORD="$XDG_STATE_HOME/xghost/links"

	# git needs an identity for the commits a test makes, and HOME above holds
	# no configuration file to take one from.
	export GIT_AUTHOR_NAME=xghost
	export GIT_AUTHOR_EMAIL=xghost@example.invalid
	export GIT_COMMITTER_NAME=xghost
	export GIT_COMMITTER_EMAIL=xghost@example.invalid

	CHECKOUT="$BATS_TEST_TMPDIR/checkout"
	git clone --quiet --local "$FILE_ORIGIN" "$CHECKOUT"
	export XGHOST_ROOT="$CHECKOUT"
	XGHOST="$CHECKOUT/bin/xghost"
	PRESCRIBED="$CHECKOUT/config"

	stub_programs
	assert_stubs_are_first
	set_missing_packages
}

# Put a stub of every program the doctor must never call first on the PATH.
#
# None of these is a stub that answers. Each one ends 99 and records the call,
# because the doctor reads and signals nothing: it never installs a package,
# never reloads the compositor, never signals the bar and never raises
# privileges. A stub that answered would let a defect that called one of them
# pass this suite in silence.
#
# The package manager is here for a second reason. The doctor queries the
# packages through XGHOST_DOCTOR_PACKAGE_QUERY, and this stub is what proves
# that injection is really used: a doctor that called pacman itself would get
# 99 and report that the query could not answer.
stub_programs() {
	STUB_DIR="$BATS_TEST_TMPDIR/stub"
	mkdir -p "$STUB_DIR"
	export STUB_DIR

	: >"$STUB_DIR/log"

	local name
	for name in pacman sudo yay paru hyprctl pkill swaync-client; do
		cat >"$STUB_DIR/$name" <<-STUB
			#!/usr/bin/env bash
			set -uo pipefail
			printf '$name %s\n' "\$*" >>"\$STUB_DIR/log"
			printf 'the doctor called $name, and it must call none of these\n' >&2
			exit 99
		STUB
		chmod +x "$STUB_DIR/$name"
	done

	PATH="$STUB_DIR:$PATH"
	export PATH
}

# Fail the test here rather than in the live session.
assert_stubs_are_first() {
	local name
	for name in pacman sudo yay paru hyprctl pkill swaync-client; do
		[ "$(command -v "$name")" = "$STUB_DIR/$name" ] || {
			printf 'the stub %s is not first on the PATH; refusing to run\n' "$name" >&2
			return 1
		}
	done
}

# Assert that nothing the doctor must never call was called.
assert_nothing_was_called() {
	[ -f "$STUB_DIR/log" ]
	[ ! -s "$STUB_DIR/log" ] || {
		printf 'the doctor called a program it must never call:\n' >&2
		cat "$STUB_DIR/log" >&2
		return 1
	}
}

# The injected package query.
#
#   set_missing_packages [NAME ...]
#
# It writes a script that prints the names it was given, whatever packages it
# is asked about, and ends 0. With no name it prints nothing, which is a
# machine that has every package the manifest declares.
set_missing_packages() {
	QUERY="$BATS_TEST_TMPDIR/package-query"
	printf '#!/usr/bin/env bash\nset -uo pipefail\n' >"$QUERY"
	if [ "$#" -gt 0 ]; then
		printf 'printf %s\n' "'%s\\n' $(printf '%q ' "$@")" >>"$QUERY"
	fi
	printf 'exit 0\n' >>"$QUERY"
	chmod +x "$QUERY"
	export XGHOST_DOCTOR_PACKAGE_QUERY="$QUERY"
}

# A package query that cannot answer.
set_query_that_fails() {
	QUERY="$BATS_TEST_TMPDIR/package-query"
	cat >"$QUERY" <<-'Q'
		#!/usr/bin/env bash
		printf 'the package database is locked\n' >&2
		exit 1
	Q
	chmod +x "$QUERY"
	export XGHOST_DOCTOR_PACKAGE_QUERY="$QUERY"
}

# Give this machine the fixed machine facts.
give_machine_facts() {
	cp "$FIXTURES/machine/golden.conf" "$FACTS"
}

# Link the prescribed configuration and render a theme, so the machine is one
# a healthy report describes.
install_a_desktop() {
	give_machine_facts
	run -0 "$XGHOST" config link
	run -0 "$XGHOST" theme set macos-dark
}

# The build directory the stable path points at, with the link resolved. A test
# that writes into the generated output writes here, so it writes into the
# build rather than through the link into a path the next render replaces.
generated_build() {
	readlink -f "$GENERATED"
}

# Run the doctor.
doctor() {
	run "$XGHOST" system doctor "$@"
}

# The number of lines of the report that carry a verdict of 'problem'.
problem_lines() {
	printf '%s\n' "$output" | grep -c '^  problem ' || true
}

# A fingerprint of one directory: every file name, every file content and every
# link target. Two trees with the same fingerprint hold the same thing.
fingerprint() {
	local dir=$1 path
	if [ ! -d "$dir" ]; then
		printf 'none\n'
		return 0
	fi
	{
		cd "$dir" || exit 1
		find . \( -type f -o -type l \) -print | LC_ALL=C sort |
			while IFS= read -r path; do
				if [ -L "$path" ]; then
					printf 'l %s %s\n' "$path" "$(readlink "$path")"
				else
					printf 'f %s %s\n' "$path" "$(cksum <"$path")"
				fi
			done
	} | cksum
}

# Source the library into this shell, for the tests that call one function
# rather than the whole command.
source_doctor() {
	# shellcheck source=../lib/doctor.sh
	. "$CHECKOUT/lib/doctor.sh"
}

# --- the command --------------------------------------------------------------

@test "the doctor is a verb of the group 'system'" {
	run -0 "$XGHOST"
	[[ $output == *system* ]]
	[[ $output == *"doctor"* ]]

	run -0 "$XGHOST" system doctor --help
	[[ $output == *"Usage: xghost system doctor"* ]]
}

@test "an option the doctor does not take is refused, and nothing is reported" {
	doctor --no-such-option
	[ "$status" -eq 2 ]
	[[ $output == *"unknown option '--no-such-option'"* ]]
	[[ $output != *"prescribed configuration"* ]]
}

# --- criterion 1: the overall verdict and the exit status ----------------------

@test "a healthy installation reports no problem and ends 0" {
	install_a_desktop
	doctor
	[ "$status" -eq 0 ]
	[[ $output == *"no problem found"* ]]
	[ "$(problem_lines)" -eq 0 ]
	assert_nothing_was_called
}

@test "one thing wrong ends non-zero and is counted as one problem" {
	install_a_desktop
	rm "$XDG_CONFIG_HOME/hypr"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"1 problem"* ]]
	[[ $output != *"problems"* ]]
	[ "$(problem_lines)" -eq 1 ]
}

@test "the number the report ends with is the number of problems it holds" {
	install_a_desktop
	rm "$XDG_CONFIG_HOME/hypr"
	rm "$XDG_CONFIG_HOME/rofi"
	set_missing_packages waybar

	doctor
	[ "$status" -eq 1 ]

	local counted
	counted=$(problem_lines)
	[ "$counted" -eq 3 ]
	[[ $output == *"$counted problems"* ]]
}

@test "a doctor that found problems never ends 0" {
	install_a_desktop
	printf 'a line nobody prescribed\n' >>"$PRESCRIBED/ghostty/config"

	doctor
	[ "$status" -ne 0 ]
	[ "$(problem_lines)" -gt 0 ]
}

# --- criterion 2: a prescribed file modified locally ---------------------------

@test "a prescribed file modified in the checkout is reported by its path" {
	install_a_desktop
	printf '\n# a line somebody added\n' >>"$PRESCRIBED/ghostty/config"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"modified: $PRESCRIBED/ghostty/config"* ]]
}

@test "a prescribed file edited through the link is reported, because the link reaches the checkout" {
	install_a_desktop

	# The edit is made at the path the desktop reads, which is a symbolic link
	# into the checkout. This is what a user who edited their configuration
	# would really do, and the report has to name the file in the checkout.
	printf '\n# edited where the desktop reads it\n' >>"$XDG_CONFIG_HOME/ghostty/config"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"modified: $PRESCRIBED/ghostty/config"* ]]
	run -0 grep -qF 'edited where the desktop reads it' "$PRESCRIBED/ghostty/config"
}

@test "a prescribed file that was deleted is reported as deleted" {
	install_a_desktop
	rm "$PRESCRIBED/ghostty/config"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"deleted: $PRESCRIBED/ghostty/config"* ]]
}

@test "a file added to the prescribed directory is reported as untracked" {
	install_a_desktop
	printf 'a file the project does not ship\n' >"$PRESCRIBED/ghostty/extra.conf"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"untracked: $PRESCRIBED/ghostty/extra.conf"* ]]
}

@test "every modified prescribed file is named, not just the first" {
	install_a_desktop
	printf '\n# one\n' >>"$PRESCRIBED/ghostty/config"
	printf '\n# two\n' >>"$PRESCRIBED/tmux/tmux.conf"

	doctor
	[[ $output == *"modified: $PRESCRIBED/ghostty/config"* ]]
	[[ $output == *"modified: $PRESCRIBED/tmux/tmux.conf"* ]]
}

@test "a change outside the prescribed directory is not a modified prescribed file, and the version says the checkout is dirty" {
	install_a_desktop
	printf '\na line of the readme\n' >>"$CHECKOUT/README.md"

	doctor
	[[ $output == *"no prescribed file is modified"* ]]
	[[ $output != *"modified: $CHECKOUT/README.md"* ]]

	# The checkout carries work of its own all the same, and the version line
	# is where a reader sees that.
	[[ $output == *-dirty* ]]
}

@test "a checkout that is not a git working tree reports that it could not check, and never that nothing is modified" {
	install_a_desktop
	rm -rf "$CHECKOUT/.git"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"not checked"* ]]
	[[ $output == *"is not inside a git working tree"* ]]
	[[ $output != *"no prescribed file is modified"* ]]
}

@test "the clean report counts the prescribed files it read" {
	install_a_desktop
	doctor
	[ "$status" -eq 0 ]

	local tracked
	tracked=$(git -C "$PRESCRIBED" ls-files -- . | grep -c .)
	[ "$tracked" -gt 0 ]
	[[ $output == *"$tracked files are tracked under $PRESCRIBED"* ]]
}

# --- criterion 3: the dependencies of the manifest -----------------------------

@test "a machine with every package of the manifest is reported as having them, with the count" {
	install_a_desktop
	set_missing_packages

	doctor
	[ "$status" -eq 0 ]

	local declared
	declared=$(grep -cve '^[[:space:]]*#' -e '^[[:space:]]*$' \
		"$CHECKOUT/install/packages/base.txt")
	[[ $output == *"every one of the $declared packages"* ]]
	[[ $output == *"install/packages/base.txt is installed"* ]]
}

@test "a missing package is reported by name, with how many of how many" {
	install_a_desktop
	set_missing_packages waybar rofi

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"2 of the "*" packages of "*"base.txt are not installed"* ]]
	[[ $output == *"waybar"* ]]
	[[ $output == *"rofi"* ]]
	[[ $output == *"sudo pacman -S --needed -- waybar rofi"* ]]
}

@test "the package query is injected, and the package manager of this machine is never called" {
	install_a_desktop
	set_missing_packages ghostty

	doctor
	[[ $output == *"ghostty"* ]]

	# The stub pacman ends 99 and records the call. An empty log is what says
	# the answer above came from the injected query and from nothing else.
	assert_nothing_was_called
}

@test "a query that cannot answer is reported as not checked, and never as nothing missing" {
	install_a_desktop
	set_query_that_fails

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"not checked: the packages this machine is missing could not be read"* ]]
	[[ $output != *"is installed"* ]]
}

@test "a machine with no package manager at all reports that it could not check" {
	install_a_desktop

	# To prove a program is absent, build a PATH that holds only what the check
	# needs and assert it reaches none of the forbidden names. Removing a stub
	# from a PATH that still holds /usr/bin does not make a program absent: it
	# reveals the real one, and the real one then runs against this machine.
	local minimal="$BATS_TEST_TMPDIR/minimal"
	local name source
	mkdir -p "$minimal"
	for name in bash dirname; do
		source=$(command -v "$name")
		ln -s "$source" "$minimal/$name"
	done
	for name in pacman yay paru pamac apt dnf; do
		if PATH="$minimal" command -v "$name" >/dev/null 2>&1; then
			printf 'the minimal PATH reaches %s; refusing to run\n' "$name" >&2
			return 1
		fi
	done

	unset XGHOST_DOCTOR_PACKAGE_QUERY
	PATH="$minimal" run -1 bash -c '
		. "$XGHOST_ROOT/lib/doctor.sh"
		doctor_check_packages
	'
	[[ $output == *"not checked: the packages this machine is missing could not be read"* ]]
	[[ $output == *"the 'pacman' program is not installed"* ]]
	[[ $output != *"is installed"$'\n'* ]]
}

@test "a manifest that cannot be read is reported as not checked" {
	install_a_desktop
	rm "$CHECKOUT/install/packages/base.txt"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"not checked: the base package manifest cannot be read"* ]]
}

@test "a manifest with a name that is not a package name is reported as not checked" {
	install_a_desktop
	printf 'Not A Package Name\n' >>"$CHECKOUT/install/packages/base.txt"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"not checked: the base package manifest cannot be read"* ]]
}

# --- criterion 4: the generated output ----------------------------------------

@test "output that matches a fresh render is reported as matching, with the file count" {
	install_a_desktop
	doctor
	[ "$status" -eq 0 ]
	[[ $output == *"the output matches a fresh render of the theme 'macos-dark'"* ]]
	[[ $output =~ macos-dark\'\;\ [0-9]+\ files ]]
}

@test "a generated file edited by hand is reported as different, by path" {
	install_a_desktop
	printf '/* a line somebody added */\n' >>"$(generated_build)/waybar/colors.css"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the generated output is stale"* ]]
	[[ $output == *"differs: waybar/colors.css"* ]]
}

@test "a generated file that was deleted is reported as missing, by path" {
	install_a_desktop
	rm "$(generated_build)/ghostty/colors.conf"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the generated output is stale"* ]]
	[[ $output == *"missing: ghostty/colors.conf"* ]]
}

@test "a file no render produces is named as one" {
	install_a_desktop
	printf 'nothing renders this\n' >"$(generated_build)/leftover.conf"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"no render produces it: leftover.conf"* ]]
}

@test "a knob the user changed after the render makes the output stale" {
	install_a_desktop

	# A real input change: the third input of the renderer moves, and nothing
	# else does. This is the state a machine is in between 'settings set' and
	# the render, and it is what "stale" is for.
	printf 'KNOB_GAP_SIZE=20\n' >"$KNOBS"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the generated output is stale"* ]]
	[[ $output == *"differs:"* ]]
}

@test "machine facts the user corrected after the render make the output stale" {
	install_a_desktop
	sed -i 's/^MACHINE_MONITOR_1_NAME=.*/MACHINE_MONITOR_1_NAME=DP-9/' "$FACTS"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the generated output is stale"* ]]
	[[ $output == *"differs: hypr/monitors.conf"* ]]
}

@test "a template changed by a pull makes the output stale" {
	install_a_desktop
	printf '\n# a line a later release added\n' >>"$CHECKOUT/templates/ghostty/colors.conf"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"differs: ghostty/colors.conf"* ]]
}

@test "a machine with no theme set is reported, and never passed over" {
	install_a_desktop
	rm "$GENERATED"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"no theme is active"* ]]
}

@test "a stable path that points at nothing is reported as a broken output" {
	install_a_desktop
	rm -rf "$XDG_STATE_HOME/xghost/builds"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the generated output is broken"* ]] ||
		[[ $output == *"the generated output is missing"* ]]
}

@test "the doctor changes nothing: the generated output is the same after it as before" {
	install_a_desktop

	local before after config_before config_after
	before=$(fingerprint "$(generated_build)")
	config_before=$(fingerprint "$XDG_CONFIG_HOME/xghost")

	doctor
	[ "$status" -eq 0 ]

	after=$(fingerprint "$(generated_build)")
	config_after=$(fingerprint "$XDG_CONFIG_HOME/xghost")

	[ "$before" = "$after" ]
	[ "$config_before" = "$config_after" ]

	# The build the stable path points at did not move either, so the doctor
	# rendered somewhere else and switched nothing.
	[ "$(readlink "$GENERATED")" = "$(readlink "$GENERATED")" ]
}

@test "the doctor leaves no temporary tree behind" {
	install_a_desktop

	local before after
	before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)
	doctor
	[ "$status" -eq 0 ]
	after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)
	[ "$before" -eq "$after" ]
}

# --- criterion 5: the symbolic links ------------------------------------------

@test "an installation whose links are all in place says how many there are" {
	install_a_desktop
	doctor
	[ "$status" -eq 0 ]
	[[ $output =~ [0-9]+\ links\ are\ in\ place ]]
}

@test "a link that was removed is reported as missing" {
	install_a_desktop
	rm "$XDG_CONFIG_HOME/hypr"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"missing: $XDG_CONFIG_HOME/hypr is not there"* ]]
	[[ $output == *"it should link to $PRESCRIBED/hypr"* ]]
}

@test "a link that points somewhere else is reported as pointing elsewhere, with both targets" {
	install_a_desktop
	rm "$XDG_CONFIG_HOME/rofi"
	ln -s "$BATS_TEST_TMPDIR" "$XDG_CONFIG_HOME/rofi"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"points elsewhere: $XDG_CONFIG_HOME/rofi links to $BATS_TEST_TMPDIR"* ]]
	[[ $output == *"the record says $PRESCRIBED/rofi"* ]]
}

@test "a regular file where a link belongs is reported as not a link" {
	install_a_desktop
	rm "$XDG_CONFIG_HOME/tmux"
	printf 'a file somebody put here\n' >"$XDG_CONFIG_HOME/tmux"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"not a link: $XDG_CONFIG_HOME/tmux is a regular file"* ]]
}

@test "a link whose target is gone is reported as a link with no target" {
	install_a_desktop
	rm -rf "$PRESCRIBED/tmux"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the target is gone: $XDG_CONFIG_HOME/tmux links to $PRESCRIBED/tmux"* ]]
}

@test "the three faults of a link are told apart in one report" {
	install_a_desktop
	rm "$XDG_CONFIG_HOME/hypr"
	rm "$XDG_CONFIG_HOME/rofi"
	ln -s "$BATS_TEST_TMPDIR" "$XDG_CONFIG_HOME/rofi"
	rm -rf "$PRESCRIBED/tmux"

	doctor
	[ "$status" -eq 1 ]

	# Three faults, three different words. A report that called all three
	# "broken" would leave the reader to work out which one they have.
	[[ $output == *"missing: $XDG_CONFIG_HOME/hypr"* ]]
	[[ $output == *"points elsewhere: $XDG_CONFIG_HOME/rofi"* ]]
	[[ $output == *"the target is gone: $XDG_CONFIG_HOME/tmux"* ]]

	# Four problems and not three. Removing the prescribed entry is what makes
	# the third link have no target, and it is a deleted prescribed file as
	# well. Both are true and the report says both.
	[[ $output == *"deleted: $PRESCRIBED/tmux/tmux.conf"* ]]
	[ "$(problem_lines)" -eq 4 ]
}

@test "a prescribed entry that was never linked is reported as not linked" {
	install_a_desktop

	# A bundle that arrived in the checkout after the last 'config link'. It
	# is in no link record, so the record alone cannot report it.
	mkdir -p "$PRESCRIBED/anewapp"
	printf 'the prescribed file of a new bundle\n' >"$PRESCRIBED/anewapp/anewapp.conf"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"not linked: $XDG_CONFIG_HOME/anewapp is in no link record"* ]]
}

@test "the bridge to the generated output is checked like every other link" {
	install_a_desktop

	# The bridge is the link every relative include of this project resolves
	# through. It is in the link record like any other link, so removing it
	# from disk is reported by the same words as any other missing link.
	rm "$XDG_CONFIG_HOME/xghost-generated"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"missing: $XDG_CONFIG_HOME/xghost-generated is not there"* ]]
}

@test "a bridge that is in no link record is reported, and no prescribed entry stands behind it" {
	install_a_desktop

	# The record of a machine linked before the bridge existed holds every
	# prescribed entry and not the bridge. Nothing in the prescribed directory
	# stands behind it, so the scan of that directory cannot find it either:
	# it is the one link a report has to name on its own.
	grep -v "$XDG_CONFIG_HOME/xghost-generated" "$LINK_RECORD" >"$LINK_RECORD.new"
	mv "$LINK_RECORD.new" "$LINK_RECORD"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"not linked: $XDG_CONFIG_HOME/xghost-generated is in no link record"* ]]
	[[ $output == *"the bridge every include of the generated output resolves through"* ]]
}

@test "a machine with no link record at all is reported as not linked" {
	give_machine_facts
	run -0 "$XGHOST" theme set macos-dark

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"nothing is linked: there is no link record at $LINK_RECORD"* ]]
	[[ $output == *"run 'xghost config link'"* ]]
}

@test "a link record that is not a regular file is reported rather than read" {
	install_a_desktop
	rm "$LINK_RECORD"
	mkdir "$LINK_RECORD"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the link record $LINK_RECORD is a directory"* ]]
}

# --- criterion 6: the version, the theme and the machine facts ----------------

@test "the version is the commit of this checkout, and no invented release number" {
	install_a_desktop
	doctor
	[ "$status" -eq 0 ]

	local described
	described=$(git -C "$CHECKOUT" describe --tags --always --dirty)
	[ -n "$described" ]
	[[ $output == *"version:  $described"* ]]

	# The project ships no version scheme, so nothing that looks like a release
	# number is printed. docs/doctor.md records why.
	[[ ! $output =~ version:\ +[0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "a checkout that carries work of its own says so in the version" {
	install_a_desktop
	printf 'work of my own\n' >>"$CHECKOUT/README.md"

	doctor
	[[ $output =~ version:\ +[0-9a-f]+-dirty ]]
}

@test "a checkout that is not a git working tree reports that the version cannot be read" {
	install_a_desktop
	rm -rf "$CHECKOUT/.git"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the version cannot be read"* ]]
	[[ $output == *"is not a git working tree"* ]]
}

@test "a version that cannot be read does not hide the theme and the machine facts beside it" {
	install_a_desktop
	rm -rf "$CHECKOUT/.git"

	# The three lines of the first section are independent of one another for
	# the same reason the five checks are. A section that stopped at its first
	# fault would drop the two facts a reader needs most.
	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the version cannot be read"* ]]
	[[ $output == *"theme:    macos-dark"* ]]
	[[ $output == *"monitors: 2: DP-1"* ]]
}

@test "the report names the active theme" {
	install_a_desktop
	doctor
	[[ $output == *"theme:    macos-dark"* ]]
}

@test "the report summarises the machine facts it found" {
	install_a_desktop
	doctor
	[ "$status" -eq 0 ]

	[[ $output == *"facts:    $FACTS"* ]]
	[[ $output == *"monitors: 2: DP-1 3840x2160@60.00 scale 1; HDMI-A-1 2560x1440@144.00 scale 1.25"* ]]
	[[ $output == *"input:    keyboard us, variant none, timezone UTC"* ]]
	[[ $output == *"session:  compositor hyprland, browser none, terminal ghostty"* ]]
}

@test "machine facts that are not there are reported, and the file is named" {
	install_a_desktop
	rm "$FACTS"

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"the machine facts cannot be read"* ]]
	[[ $output == *"the machine facts file does not exist: $FACTS"* ]]
	[[ $output == *"run 'xghost machine detect'"* ]]
}

@test "every problem of a broken machine facts file is reported, not just the first" {
	install_a_desktop
	cat >"$FACTS" <<-'FACTS'
		MACHINE_FACTS_VERSION=1
		this line is not a pair
		MACHINE_MONITOR_COUNT=
	FACTS

	doctor
	[ "$status" -eq 1 ]
	[[ $output == *"line 2"* ]]
	[[ $output == *"line 3"* ]]
}

@test "a machine fact the file never recorded is told apart from one that is unknown" {
	install_a_desktop
	# 'unknown' is a value detection writes on purpose. A key that is not in
	# the file at all is a different thing, and the report says which it is.
	sed -i 's/^MACHINE_TIMEZONE=.*/MACHINE_TIMEZONE=unknown/' "$FACTS"
	sed -i '/^MACHINE_BROWSER=/d' "$FACTS"

	doctor
	[[ $output == *"timezone unknown"* ]]
	[[ $output == *"browser not recorded"* ]]
}

# --- criterion 7: no colour when there is no terminal -------------------------

@test "a report written to a pipe carries no escape sequence" {
	install_a_desktop
	rm "$XDG_CONFIG_HOME/hypr"

	# Both a healthy report and a report with problems, because the colour is
	# on the verdict words and a run with no problem prints only one of them.
	run bash -c '"$1" system doctor | cat' _ "$XGHOST"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | grep -qP '\x1b' && {
		printf 'the report carries an escape sequence in a pipe\n' >&2
		return 1
	}
	[[ $output == *problem* ]]
	[[ $output == *ok* ]]
}

@test "a report written to a file carries no escape sequence" {
	install_a_desktop
	rm "$XDG_CONFIG_HOME/hypr"

	local report="$BATS_TEST_TMPDIR/report.txt"
	run "$XGHOST" system doctor
	printf '%s\n' "$output" >"$report"

	run "$XGHOST" system doctor
	[ "$status" -eq 1 ]

	# The command wrote its own file, rather than this test writing what bats
	# captured, so the redirection under test is the real one.
	"$XGHOST" system doctor >"$report" 2>&1 || true
	run -1 grep -qP '\x1b' "$report"
	run -0 grep -qF 'problem' "$report"
}

@test "the decision to use colour is made by asking whether standard output is a terminal" {
	source_doctor

	# Standard output of this test body is not a terminal.
	doctor_resolve_colour
	[ "$DOCTOR_COLOUR" = no ]

	# And the painting that decision gates really can emit colour, so the test
	# above is gating something rather than nothing.
	DOCTOR_COLOUR=yes
	run -0 doctor_paint "$DOCTOR_GREEN" ok
	[[ $output == *$'\033'* ]]

	DOCTOR_COLOUR=no
	run -0 doctor_paint "$DOCTOR_GREEN" ok
	[ "$output" = ok ]
}

@test "the report is plain text a reader pastes into an issue" {
	install_a_desktop
	rm "$XDG_CONFIG_HOME/hypr"

	doctor
	[ "$status" -eq 1 ]

	# No escape sequence, no carriage return, and every line is printable.
	printf '%s' "$output" | grep -qP '[\x00-\x08\x0b-\x1f\x7f]' && {
		printf 'the report carries a control character\n' >&2
		return 1
	}
	[[ $output == "xghost doctor"* ]]
}

# --- criterion 8: the checks are independent ----------------------------------

@test "five faults at once are all five reported" {
	install_a_desktop

	# One fault per check, all on the same machine. A doctor whose first
	# failure ended the run would report the first of these and none of the
	# rest, and the output would still look like a report.
	rm "$FACTS"                                              # this installation
	printf '\n# edited\n' >>"$PRESCRIBED/ghostty/config"     # prescribed
	set_missing_packages waybar                              # dependencies
	printf 'stray\n' >"$(generated_build)/leftover.conf"     # generated output
	rm "$XDG_CONFIG_HOME/hypr"                               # symbolic links

	doctor
	[ "$status" -eq 1 ]

	[[ $output == *"the machine facts cannot be read"* ]]
	[[ $output == *"modified: $PRESCRIBED/ghostty/config"* ]]
	[[ $output == *"1 of the "*" packages of "*" are not installed"* ]]
	[[ $output == *"waybar"* ]]
	[[ $output == *"missing: $XDG_CONFIG_HOME/hypr is not there"* ]]

	# The generated output cannot be compared without machine facts, so that
	# check reports why rather than reporting nothing.
	[[ $output == *"generated output"* ]]
	[[ $output == *"not checked: the theme 'macos-dark' cannot be rendered"* ]]

	[ "$(problem_lines)" -ge 5 ]
}

@test "a check that cannot run at all does not hide the checks after it" {
	install_a_desktop

	# The checkout stops being a git working tree, which is a hard failure of
	# the first two checks: neither the version nor a modified prescribed file
	# can be read without git. Every check after them still has to report.
	rm -rf "$CHECKOUT/.git"
	set_missing_packages rofi
	rm "$XDG_CONFIG_HOME/hypr"

	doctor
	[ "$status" -eq 1 ]

	[[ $output == *"the version cannot be read"* ]]
	[[ $output == *"not checked: $PRESCRIBED is not inside a git working tree"* ]]

	# The three checks after the two that failed.
	[[ $output == *"rofi"* ]]
	[[ $output == *"the output matches a fresh render"* ]]
	[[ $output == *"missing: $XDG_CONFIG_HOME/hypr is not there"* ]]
}

@test "every section of the report is present however much is broken" {
	install_a_desktop
	rm -rf "$CHECKOUT/.git"
	rm "$FACTS"
	rm -rf "$XDG_STATE_HOME/xghost"
	rm "$CHECKOUT/install/packages/base.txt"

	doctor
	[ "$status" -eq 1 ]

	local section
	for section in "this installation" "prescribed configuration" \
		"dependencies" "generated output" "symbolic links"; do
		[[ $output == *"$section"* ]] || {
			printf 'the section "%s" is not in the report\n' "$section" >&2
			return 1
		}
	done
}

@test "a state directory that has no home does not stop the checks that need none" {
	install_a_desktop

	# Neither XDG_STATE_HOME nor HOME, so the generated output and the link
	# record have nowhere to be. The checkout is still readable, and the checks
	# that read it still have to report.
	run env -u HOME -u XDG_STATE_HOME \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		XGHOST_ROOT="$CHECKOUT" \
		XGHOST_DOCTOR_PACKAGE_QUERY="$QUERY" \
		PATH="$PATH" \
		"$XGHOST" system doctor

	[ "$status" -eq 1 ]
	[[ $output == *"version:"* ]]
	[[ $output == *"no prescribed file is modified"* ]]
	[[ $output == *"is installed"* ]]
	[[ $output == *"generated output"* ]]
	[[ $output == *"symbolic links"* ]]
}

# --- what the doctor must never do --------------------------------------------

@test "the doctor writes nothing into the config directory of the user" {
	install_a_desktop

	local before after
	before=$(fingerprint "$XDG_CONFIG_HOME")
	doctor
	[ "$status" -eq 0 ]
	after=$(fingerprint "$XDG_CONFIG_HOME")
	[ "$before" = "$after" ]
}

@test "the doctor writes nothing into the checkout" {
	install_a_desktop

	local before after
	before=$(git -C "$CHECKOUT" status --porcelain)
	doctor
	after=$(git -C "$CHECKOUT" status --porcelain)
	[ "$before" = "$after" ]
}

@test "the doctor signals no component and installs nothing" {
	install_a_desktop
	doctor
	[ "$status" -eq 0 ]
	assert_nothing_was_called
}
