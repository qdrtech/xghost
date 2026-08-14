#!/usr/bin/env bats
#
# Tests for the installer: the package manifests, the runner in lib/install.sh,
# and the steps under install/steps/.
#
# Nothing here installs a package. Every test that reaches the packaging group
# puts a stub pacman first on the PATH, and that stub answers 'pacman -T' from a
# file the test writes and records what 'pacman -S' was called with. A test that
# reached the real pacman would need root, and it would change the machine that
# runs the suite.
#
# Shadowing a name is not enough on its own, because a variable decides which
# name the installer looks for. XGHOST_AUR_HELPERS names the AUR helpers of the
# packaging step, and its default is 'yay paru'. A person who exports
# 'XGHOST_AUR_HELPERS=paru' would otherwise have their own paru called, and the
# call would build packages from the AUR before the assertion that follows it
# ever ran. stub_programs therefore pins that variable to the one name it
# shadows. Unsetting it would not do: the default names paru as well.
#
# Every other program lookup of this suite was read the same way:
#
#   pacman, sudo   Shadowed by stub_programs. No variable moves either name.
#   yay            Shadowed, and pinned by XGHOST_AUR_HELPERS as above.
#   hyprctl        Shadowed by stub_programs. It reads only, and the stub is
#                  what makes the monitor facts of a test the same on a machine
#                  in a Hyprland session and on one that is not.
#   localectl, timedatectl, xdg-settings
#                  The real programs of the machine, and all three read only.
#                  No variable moves a name, and no assertion here reads a
#                  value that comes from one of them.
#   flock, mktemp, and the rest of coreutils
#                  The real programs. No variable moves a name.
#
# Everything else runs for real, in a home directory of the test: the linker
# links the prescribed configuration, detection reads the machine, and the
# renderer writes the generated output. That is the whole installation except
# the packages, and it is what proves the order of the steps, the idempotency of
# a second run, and the end state.
#
# Two things this suite does not prove:
#
#   - The refusal to run as root. The test would have to be root, and a suite
#     that runs as root is a suite that can damage the machine it runs on. The
#     step reads EUID, which bash makes readonly, so it cannot be faked either.
#   - That the desktop comes up. No test starts a Hyprland session. The suite
#     proves that the generated output is complete and that a theme is active,
#     which is as far as an offline test reaches. docs/installing.md records
#     what that leaves unproved.
#
# The design of the installer is recorded in docs/installing.md.
bats_require_minimum_version 1.5.0

setup() {
	ROOT_DIR="$BATS_TEST_DIRNAME/.."
	INSTALL="$ROOT_DIR/install.sh"
	XGHOST="$ROOT_DIR/bin/xghost"
	FIXTURES="$BATS_TEST_DIRNAME/fixtures/install"

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# Every path the installer writes to comes from this setup, so no test
	# touches the home directory of the person who runs the suite, and no
	# override that person happens to export reaches a step.
	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR
	unset XGHOST_CONFIG_SOURCE
	unset XGHOST_ROOT
	unset XGHOST_THEMES_DIR
	unset XGHOST_TEMPLATE_DIR
	unset XGHOST_MACHINE_FACTS
	unset XGHOST_STEPS_DIR
	unset XGHOST_PACKAGES_DIR
	unset XGHOST_INSTALL_THEME

	# Every step runs in a bash of its own, and bash sources the file BASH_ENV
	# names into every one of them. A person who exports it would put their own
	# file inside the isolation the runner claims at lib/install.sh:30.
	unset BASH_ENV

	# XGHOST_AUR_HELPERS is not unset here. It is pinned in stub_programs
	# instead, because the default of that variable names paru, which this suite
	# does not shadow.

	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XGHOST_BIN_DIR="$HOME/.local/bin"
	export XGHOST_OS_RELEASE="$FIXTURES/os-release/arch"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	GENERATED="$XDG_STATE_HOME/xghost/generated"
	FACTS="$XDG_CONFIG_HOME/xghost/machine.conf"
	DETECT_FIXTURES="$BATS_TEST_DIRNAME/fixtures/detect"
	export DETECT_FIXTURES

	stub_programs
}

# Put a stub pacman, sudo, AUR helper and hyprctl first on the PATH, and pin the
# lookup of the AUR helper to the name that is shadowed.
#
# The stub pacman keeps its state in one file. 'pacman -T' prints the names that
# file holds, which is the set this machine is missing, and 'pacman -S' takes
# the names it was given out of that set and records the call. A step that
# installs therefore changes the answer of the next test, exactly as a real
# installation would, and nothing is installed anywhere.
#
# The stub hyprctl answers what HYPRCTL says. 'session' reads the two-monitor
# fixture, which is what an installation inside a Hyprland session sees, and
# anything else fails the way hyprctl fails outside a session. Pinning it is
# what keeps the monitor facts of a test off the hardware of the machine that
# runs the suite.
stub_programs() {
	STUB_DIR="$BATS_TEST_TMPDIR/stub"
	mkdir -p "$STUB_DIR"

	# The one name the AUR lookup may find. The default of this variable is
	# 'yay paru', and this suite shadows neither name on the machine it runs on,
	# so a value from the environment or the default would reach a real helper
	# and build packages from the AUR before the assertion of the test ran.
	export XGHOST_AUR_HELPERS=yay

	# No test is inside a Hyprland session until it says so.
	export HYPRCTL=${HYPRCTL:-none}
	: >"$STUB_DIR/missing"
	: >"$STUB_DIR/log"
	export STUB_DIR

	cat >"$STUB_DIR/pacman" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		case ${1:-} in
		-T)
			shift
			[ "${1:-}" = -- ] && shift
			status=0
			for name in "$@"; do
				if grep -qxF -- "$name" "$STUB_DIR/missing"; then
					printf '%s\n' "$name"
					status=127
				fi
			done
			exit "$status"
			;;
		-S)
			printf 'pacman %s\n' "$*" >>"$STUB_DIR/log"
			shift
			for name in "$@"; do
				case $name in --* | --) continue ;; esac
				grep -vxF -- "$name" "$STUB_DIR/missing" >"$STUB_DIR/missing.new" || :
				mv "$STUB_DIR/missing.new" "$STUB_DIR/missing"
			done
			exit 0
			;;
		esac
		printf 'the stub pacman was called with an unexpected verb: %s\n' "$*" >&2
		exit 99
	STUB

	cat >"$STUB_DIR/sudo" <<-'STUB'
		#!/usr/bin/env bash
		exec "$@"
	STUB

	cat >"$STUB_DIR/yay" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		printf 'yay %s\n' "$*" >>"$STUB_DIR/log"
		shift
		for name in "$@"; do
			case $name in --* | --) continue ;; esac
			grep -vxF -- "$name" "$STUB_DIR/missing" >"$STUB_DIR/missing.new" || :
			mv "$STUB_DIR/missing.new" "$STUB_DIR/missing"
		done
		exit 0
	STUB

	cat >"$STUB_DIR/hyprctl" <<-'STUB'
		#!/usr/bin/env bash
		set -uo pipefail
		if [ "${HYPRCTL:-none}" != session ]; then
			printf 'hyprctl: no Hyprland session\n' >&2
			exit 1
		fi
		case "$*" in
		"monitors -j") cat "$DETECT_FIXTURES/monitors-two.json" ;;
		"devices -j") cat "$DETECT_FIXTURES/devices-laptop.json" ;;
		*) exit 1 ;;
		esac
	STUB

	chmod +x "$STUB_DIR/pacman" "$STUB_DIR/sudo" "$STUB_DIR/yay" "$STUB_DIR/hyprctl"
	PATH="$STUB_DIR:$PATH"
	export PATH
}

# Run the next installation as one inside a Hyprland session, where hyprctl
# answers with the two monitors of the fixture.
in_hyprland_session() {
	export HYPRCTL=session
}

# Print the value of one key of the machine facts file.
fact() {
	local key=$1 line
	while IFS= read -r line; do
		if [ "${line%%=*}" = "$key" ]; then
			printf '%s\n' "${line#*=}"
			return 0
		fi
	done <"$FACTS"
	printf '<absent>\n'
}

# Give the step a machine with no AUR helper.
#
# The stub is removed and the list of helpers to look for is replaced by one
# name that is on no machine. Replacing it is what matters: the machine that
# runs the suite may carry a real yay or paru, and removing the stub alone would
# leave the lookup free to find one of those. A helper of a name that is on no
# machine is what a machine with no helper looks like to the step.
drop_aur_helper() {
	rm -f "$STUB_DIR/yay"
	export XGHOST_AUR_HELPERS=xghost-test-no-such-helper
}

# Declare the packages the stub pacman reports as missing.
missing_packages() {
	printf '%s\n' "$@" >"$STUB_DIR/missing"
}

# Source lib/install.sh into the test, for the tests of one function.
load_install_lib() {
	# shellcheck source=lib/install.sh
	. "$ROOT_DIR/lib/install.sh"
	install_paths
}

# Print the step names of a run, in the order the runner reported them.
step_order() {
	printf '%s\n' "$1" | sed -n 's/^-- //p'
}

#
# The manifests.
#

@test "the base manifest declares the packages of both bundles" {
	load_install_lib
	run -0 install_read_manifest "$INSTALL_PACKAGES_DIR/base.txt"

	# The Ghostty bundle names the terminal and the font; the Hyprland bundle
	# names the compositor, its daemons, the portal, and every program the
	# keybindings and the autostart run.
	for name in ghostty ttf-jetbrains-mono-nerd \
		hyprland hypridle hyprlock hyprpaper \
		xdg-desktop-portal xdg-desktop-portal-hyprland polkit-gnome \
		psmisc wireplumber brightnessctl playerctl \
		network-manager-applet blueman nautilus hyprshot; do
		[[ $'\n'$output$'\n' == *$'\n'"$name"$'\n'* ]] || {
			printf 'the base manifest does not declare %s\n' "$name" >&2
			return 1
		}
	done
}

# Every bundle page carries a package table, and the manifest is derived from
# those tables. One page was read here before, so the packages of the Ghostty
# bundle were covered by the hard-coded list of the test above and by nothing
# that fails when the bundle changes. Every page is read now, and a page added
# later is read by the same loop.
@test "the manifests declare every package a bundle page lists" {
	load_install_lib
	run -0 install_read_manifest "$INSTALL_PACKAGES_DIR/base.txt"
	declared=$output
	run -0 install_read_manifest "$INSTALL_PACKAGES_DIR/aur.txt"
	declared="$declared"$'\n'"$output"

	# A package row of a bundle page names the package and the repository that
	# carries it. Reading the repository as well is what keeps the rows of the
	# other tables of those pages out of this test.
	local page rows
	for page in "$ROOT_DIR"/docs/bundles/*.md; do
		rows=0
		while IFS= read -r name; do
			rows=$((rows + 1))
			[[ $'\n'$declared$'\n' == *$'\n'"$name"$'\n'* ]] || {
				printf '%s lists %s and no manifest declares it\n' "${page##*/}" "$name" >&2
				return 1
			}
		done < <(sed -n 's/^| `\([a-z0-9@._+-]*\)` *| `\(core\|extra\|multilib\|aur\)` *|.*|$/\1/p' "$page")

		# A page whose table stopped matching would pass this test without a
		# package name ever being read.
		[ "$rows" -gt 0 ] || {
			printf '%s carries no package table this test can read\n' "${page##*/}" >&2
			return 1
		}
	done
}

# The one package no bundle page owns. Detection reads the default browser with
# 'xdg-settings', which is in xdg-utils, so the manifest declares it for xghost
# itself rather than for a bundle. Nothing else in this suite would notice it
# going missing, and a machine without it records MACHINE_BROWSER=unknown.
@test "the base manifest declares the package xghost itself reads" {
	load_install_lib
	run -0 install_read_manifest "$INSTALL_PACKAGES_DIR/base.txt"
	[[ $'\n'$output$'\n' == *$'\n'"xdg-utils"$'\n'* ]]

	run -0 grep -q 'xdg-settings get default-web-browser' "$ROOT_DIR/lib/detect.sh"
}

@test "no package is declared by both manifests" {
	load_install_lib
	run -0 install_read_manifest "$INSTALL_PACKAGES_DIR/base.txt"
	base=$output
	run -0 install_read_manifest "$INSTALL_PACKAGES_DIR/aur.txt"

	while IFS= read -r name; do
		[ -n "$name" ] || continue
		[[ $'\n'$base$'\n' != *$'\n'"$name"$'\n'* ]] || {
			printf '%s is in both manifests, so two tools would install it\n' "$name" >&2
			return 1
		}
	done <<<"$output"
}

@test "the manifest reader drops comments and empty lines" {
	load_install_lib
	run -0 install_read_manifest "$FIXTURES/packages/base.txt"
	[ "$output" = "fixture-one
fixture-two
fixture-three" ]
}

@test "the manifest reader reports every bad name with its line number" {
	load_install_lib
	run -1 install_read_manifest "$FIXTURES/packages/malformed.txt"
	[[ $output == *"line 2: 'Bad-Upper-Case' is not an Arch package name"* ]]
	[[ $output == *"line 3: '-opens-with-a-hyphen' is not an Arch package name"* ]]
}

@test "the manifest reader reports a manifest that is not there" {
	load_install_lib
	run -1 install_read_manifest "$BATS_TEST_TMPDIR/no-such-manifest.txt"
	[[ $output == *"missing or cannot be read"* ]]
}

#
# The front end.
#

@test "install.sh prints its usage and changes nothing" {
	run -0 "$INSTALL" --help
	[[ $output == *"Usage: ./install.sh"* ]]
	[[ $output == *"--dry-run"* ]]
	[ ! -e "$XDG_CONFIG_HOME/hypr" ]
}

@test "install.sh refuses an unknown option" {
	run -2 "$INSTALL" --wat
	[[ $output == *"unknown option '--wat'"* ]]
}

#
# Preflight.
#

@test "preflight refuses a system that is not Arch, and changes nothing" {
	export XGHOST_OS_RELEASE="$FIXTURES/os-release/ubuntu"
	run -1 "$INSTALL"
	[[ $output == *"this is not an Arch Linux system"* ]]
	[[ $output == *"ID='ubuntu'"* ]]
	[[ $output == *"the step preflight/10-system.sh failed"* ]]

	[ ! -e "$XDG_CONFIG_HOME/hypr" ]
	[ ! -e "$FACTS" ]
	[ ! -e "$GENERATED" ]
	[ ! -e "$XGHOST_BIN_DIR/xghost" ]
}

@test "preflight accepts a derivative that names arch in ID_LIKE" {
	export XGHOST_OS_RELEASE="$FIXTURES/os-release/arch-derivative"
	run -0 "$INSTALL" --dry-run
	[[ $output == *"the system is Arch Linux: ID=endeavouros"* ]]
}

@test "preflight refuses a machine whose os-release cannot be read" {
	export XGHOST_OS_RELEASE="$BATS_TEST_TMPDIR/no-such-os-release"
	run -1 "$INSTALL"
	[[ $output == *"cannot read"* ]]
	[[ $output == *"the step preflight/10-system.sh failed"* ]]
}

@test "preflight refuses a manifest it cannot parse, before anything changes" {
	export XGHOST_PACKAGES_DIR="$BATS_TEST_TMPDIR/packages"
	mkdir -p "$XGHOST_PACKAGES_DIR"
	printf 'Bad-Upper-Case\n' >"$XGHOST_PACKAGES_DIR/base.txt"
	: >"$XGHOST_PACKAGES_DIR/aur.txt"

	run -1 "$INSTALL"
	[[ $output == *"is not an Arch package name"* ]]
	[[ $output == *"the step preflight/30-manifests.sh failed"* ]]
	[ ! -e "$XDG_CONFIG_HOME/hypr" ]
}

# The theme name is knowable before anything changes, and the step that renders
# it is the last config step. A name with a typo in it used to be met after the
# prescribed configuration was linked, which leaves a Hyprland configuration
# whose 'source' lines name generated files that were never rendered, and
# Hyprland reports a missing source as an error rather than passing over it.
@test "a theme name that is not a theme is refused before anything is linked" {
	printf 'the ghostty config of the user\n' >"$XDG_CONFIG_HOME/ghostty"

	run -1 "$INSTALL" --theme tokoyonight
	[[ $output == *"there is no theme named 'tokoyonight'"* ]]
	[[ $output == *"the step preflight/40-checkout.sh failed"* ]]

	# Nothing was linked, nothing was backed up, and no package was installed.
	[ ! -L "$XDG_CONFIG_HOME/ghostty" ]
	[ "$(cat "$XDG_CONFIG_HOME/ghostty")" = "the ghostty config of the user" ]
	[ ! -e "$XDG_CONFIG_HOME/hypr" ]
	[ ! -e "$XDG_CONFIG_HOME/xghost-generated" ]
	[ ! -e "$FACTS" ]
	[ ! -s "$STUB_DIR/log" ]
}

@test "the themes this checkout carries are named when the theme is refused" {
	run -1 "$INSTALL" --theme tokoyonight
	[[ $output == *"macos-dark"* ]]
	[[ $output == *"tokyonight"* ]]
}

# A checkout that lost the execute bit, which is what a download of a source
# archive is. Every config step runs the command, so the failure used to arrive
# after every package of the manifest had been installed.
@test "a command that is not executable is refused before a package is installed" {
	checkout="$BATS_TEST_TMPDIR/checkout"
	mkdir -p "$checkout/bin" "$checkout/lib"
	cp "$ROOT_DIR/install.sh" "$checkout/install.sh"
	cp "$ROOT_DIR"/lib/*.sh "$checkout/lib/"
	cp "$ROOT_DIR/bin/xghost" "$checkout/bin/xghost"
	chmod -x "$checkout/bin/xghost"
	local name
	for name in install commands themes templates config; do
		ln -s "$ROOT_DIR/$name" "$checkout/$name"
	done

	missing_packages blueman nautilus
	run -1 "$checkout/install.sh"
	[[ $output == *"the xghost command is not an executable file"* ]]
	[[ $output == *"the step preflight/40-checkout.sh failed"* ]]

	[ ! -s "$STUB_DIR/log" ]
	[ ! -e "$XDG_CONFIG_HOME/hypr" ]
	[[ $output != *"Permission denied"* ]]
}

#
# The runner: the order of the groups, and what a failure reports.
#

@test "the groups run in the order preflight, packaging, config, post-install" {
	export XGHOST_STEPS_DIR="$FIXTURES/steps"
	run -0 "$INSTALL"
	[ "$(step_order "$output")" = "preflight/10-probe.sh
packaging/10-probe.sh
config/10-probe.sh
post-install/10-probe.sh" ]
}

@test "a step that fails names itself and what to do about it" {
	export XGHOST_STEPS_DIR="$FIXTURES/steps"
	export PROBE=fail
	run -1 "$INSTALL"
	[[ $output == *"the probe failed on purpose"* ]]
	[[ $output == *"what to do: read tests/install.bats"* ]]
	[[ $output == *"the step preflight/10-probe.sh failed"* ]]
	[[ $output == *"run './install.sh' again"* ]]
}

@test "a step that stops under 'set -e' is named all the same" {
	export XGHOST_STEPS_DIR="$FIXTURES/steps"
	export PROBE=crash
	run -1 "$INSTALL"
	[[ $output == *"the step preflight/10-probe.sh failed"* ]]
	[[ $output != *"this line is never reached"* ]]
}

@test "a failed step stops the groups that follow it" {
	export XGHOST_STEPS_DIR="$FIXTURES/steps"
	export PROBE=fail
	run -1 "$INSTALL"
	[[ $output != *"probe packaging"* ]]
	[[ $output != *"probe config"* ]]
	[[ $output != *"probe post-install"* ]]
}

@test "a group with no step is a failure rather than a group that is passed over" {
	export XGHOST_STEPS_DIR="$BATS_TEST_TMPDIR/steps"
	mkdir -p "$XGHOST_STEPS_DIR"/{preflight,packaging,config,post-install}
	printf 'install_say "probe"\n' >"$XGHOST_STEPS_DIR/preflight/10-probe.sh"

	run -1 "$INSTALL"
	[[ $output == *"the group 'packaging' holds no step"* ]]
}

@test "a file that is not named like a step is a failure" {
	export XGHOST_STEPS_DIR="$BATS_TEST_TMPDIR/steps"
	mkdir -p "$XGHOST_STEPS_DIR"/{preflight,packaging,config,post-install}
	printf 'install_say "probe"\n' >"$XGHOST_STEPS_DIR/preflight/10-probe.sh"
	printf 'install_say "stray"\n' >"$XGHOST_STEPS_DIR/preflight/notes.txt"

	run -1 "$INSTALL"
	[[ $output == *"'notes.txt' is not a step file"* ]]
}

# A plain file with the wrong name is a hard error, and the message for it says
# that the installer passes no file of a group over in silence. An entry that is
# not a regular file has to be the same, or that sentence is not true: a
# directory named like a step and a link that points at nothing are both a step
# that will not run.
@test "a directory named like a step is a failure rather than an entry that is passed over" {
	export XGHOST_STEPS_DIR="$BATS_TEST_TMPDIR/steps"
	mkdir -p "$XGHOST_STEPS_DIR"/{preflight,packaging,config,post-install}
	printf 'install_say "probe"\n' >"$XGHOST_STEPS_DIR/preflight/10-probe.sh"
	mkdir -p "$XGHOST_STEPS_DIR/preflight/20-directory.sh"

	run -1 "$INSTALL"
	[[ $output == *"'20-directory.sh' is not a regular file"* ]]
	[[ $output != *"the installation is complete"* ]]
}

@test "a broken symbolic link in a group is a failure rather than an entry that is passed over" {
	export XGHOST_STEPS_DIR="$BATS_TEST_TMPDIR/steps"
	mkdir -p "$XGHOST_STEPS_DIR"/{preflight,packaging,config,post-install}
	printf 'install_say "probe"\n' >"$XGHOST_STEPS_DIR/preflight/10-probe.sh"
	ln -s "$BATS_TEST_TMPDIR/no-such-step" "$XGHOST_STEPS_DIR/preflight/20-broken.sh"

	run -1 "$INSTALL"
	[[ $output == *"'20-broken.sh' is a broken symbolic link"* ]]
	[[ $output != *"the installation is complete"* ]]
}

#
# Packaging.
#

@test "packaging installs the packages that are missing and nothing else" {
	missing_packages blueman nautilus
	run -0 "$INSTALL"
	[[ $output == *"2 of "*" packages are missing: blueman nautilus"* ]]
	[ "$(cat "$STUB_DIR/log")" = "pacman -S --needed -- blueman nautilus" ]
}

@test "packaging with nothing missing runs no package operation" {
	run -0 "$INSTALL"
	[[ $output == *"is installed ("* ]]
	[ ! -s "$STUB_DIR/log" ]
}

# The one privilege escalation of an installation. Preflight says that sudo is
# installed three steps earlier, and an unbounded amount of pacman output can
# separate the two, so the notice has to be next to the command it announces.
@test "the command that needs root is announced where it runs" {
	missing_packages blueman
	run -0 "$INSTALL"

	[[ $output == *"the next command needs root, and it is the only one that does:"* ]]
	[[ $output == *"sudo pacman -S --needed -- blueman"* ]]
	[[ $output == *"asks for your password now"* ]]

	# It is announced before the command runs, not reported after it.
	notice=$(printf '%s\n' "$output" | grep -n 'the next command needs root' | head -n 1 | cut -d: -f1)
	done_line=$(printf '%s\n' "$output" | grep -n 'every package of' | head -n 1 | cut -d: -f1)
	[ -n "$notice" ]
	[ -n "$done_line" ]
	[ "$notice" -lt "$done_line" ]
}

@test "a run with nothing missing announces no escalation, because it raises none" {
	run -0 "$INSTALL"
	[[ $output != *"the next command needs root"* ]]
}

@test "packaging reports the packages pacman did not install" {
	missing_packages blueman
	# A pacman that ends well and installs nothing.
	cat >"$STUB_DIR/pacman" <<-'STUB'
		#!/usr/bin/env bash
		if [ "${1:-}" = -T ]; then
			shift
			[ "${1:-}" = -- ] && shift
			status=0
			for name in "$@"; do
				if grep -qxF -- "$name" "$STUB_DIR/missing"; then
					printf '%s\n' "$name"
					status=127
				fi
			done
			exit "$status"
		fi
		exit 0
	STUB
	chmod +x "$STUB_DIR/pacman"

	run -1 "$INSTALL"
	[[ $output == *"these packages are still not installed after pacman ran: blueman"* ]]
	[[ $output == *"the step packaging/10-official.sh failed"* ]]
}

@test "an AUR package with no helper installed is named, and the installation finishes" {
	export XGHOST_PACKAGES_DIR="$FIXTURES/packages"
	missing_packages fixture-aur-one
	drop_aur_helper

	run -0 "$INSTALL"
	[[ $output == *"no AUR helper is installed, so these packages are not installed: fixture-aur-one"* ]]
	[[ $output == *"the installation is complete"* ]]
}

@test "an AUR package is installed by the helper when there is one" {
	export XGHOST_PACKAGES_DIR="$FIXTURES/packages"
	missing_packages fixture-aur-one

	run -0 "$INSTALL"
	[[ $(cat "$STUB_DIR/log") == *"yay -S --needed -- fixture-aur-one"* ]]
}

@test "the shipped AUR manifest declares no package, so no helper is looked for" {
	drop_aur_helper
	run -0 "$INSTALL"
	[[ $output == *"the AUR manifest declares no package"* ]]
}

# The harness itself, which is what keeps this suite off the AUR.
#
# The step looks for the helpers XGHOST_AUR_HELPERS names, and it runs the first
# one it finds on the PATH. The suite shadows 'yay' and nothing else, so any
# other value of that variable — one the person running the suite exported, or
# the default 'yay paru' — reaches a helper this suite never shadowed. That
# helper builds packages from the AUR, and it does it before the assertion of
# the test it ran under.
@test "the AUR helper lookup is pinned to the name the suite shadows" {
	# The environment of the person who runs the suite, as setup() meets it.
	export XGHOST_AUR_HELPERS=paru
	stub_programs
	[ "$XGHOST_AUR_HELPERS" = yay ]
}

@test "a helper the environment names is never the helper that runs" {
	export XGHOST_AUR_HELPERS=paru
	stub_programs

	# This stands in for the real yay or paru of the machine that runs the
	# suite. It is on the PATH, and calling it is the failure this test is
	# about, so it installs nothing and records the call.
	decoy="$BATS_TEST_TMPDIR/decoy"
	mkdir -p "$decoy"
	cat >"$decoy/paru" <<-'STUB'
		#!/usr/bin/env bash
		printf 'paru %s\n' "$*" >>"$STUB_DIR/decoy.log"
		exit 0
	STUB
	chmod +x "$decoy/paru"
	export PATH="$STUB_DIR:$decoy:$PATH"

	export XGHOST_PACKAGES_DIR="$FIXTURES/packages"
	missing_packages fixture-aur-one

	run -0 "$INSTALL"
	[ ! -e "$STUB_DIR/decoy.log" ]
	[[ $(cat "$STUB_DIR/log") == *"yay -S --needed -- fixture-aur-one"* ]]
}

# BASH_ENV is read by every non-interactive bash, and every step of the
# installer is one. A file the person running the suite named there would be
# sourced into each of them, which is the isolation lib/install.sh claims for a
# step spelled the other way round.
@test "no BASH_ENV of the environment reaches a step" {
	[ -z "${BASH_ENV+set}" ]
}

#
# The dry run.
#

@test "a dry run reports every group and changes nothing" {
	missing_packages blueman
	run -0 "$INSTALL" --dry-run

	[[ $output == *"would: run: sudo pacman -S --needed -- blueman"* ]]
	[[ $output == *"would: run: xghost machine detect"* ]]
	[[ $output == *"would: run: xghost theme set macos-dark"* ]]
	[[ $output == *"the dry run is complete. Nothing was changed."* ]]

	[ ! -e "$XDG_CONFIG_HOME/hypr" ]
	[ ! -e "$XDG_CONFIG_HOME/xghost-generated" ]
	[ ! -e "$FACTS" ]
	[ ! -e "$GENERATED" ]
	[ ! -e "$XGHOST_BIN_DIR/xghost" ]
	[ ! -s "$STUB_DIR/log" ]
}

#
# A whole installation, with the packaging stubbed out.
#

@test "an installation links the configuration, writes the facts, and renders a theme" {
	run -0 "$INSTALL"
	[[ $output == *"the installation is complete"* ]]

	[ -L "$XDG_CONFIG_HOME/hypr" ]
	[ -L "$XDG_CONFIG_HOME/ghostty" ]
	[ -L "$XDG_CONFIG_HOME/xghost-generated" ]
	[ -f "$FACTS" ]
	[ -f "$GENERATED/ghostty/colors.conf" ]
	[ -f "$GENERATED/hypr/colors.conf" ]
	[ -f "$GENERATED/hypr/monitors.conf" ]
	[ -L "$XGHOST_BIN_DIR/xghost" ]

	run -0 "$XGHOST" theme current
	[ "$output" = macos-dark ]
}

@test "the bridge an installation leaves behind reaches the generated files" {
	run -0 "$INSTALL"

	# The bridge is the one name a prescribed file reaches the generated output
	# through, and it is right only when both ends are in place.
	[ "$(readlink "$XDG_CONFIG_HOME/xghost-generated")" = "$GENERATED" ]
	[ -f "$XDG_CONFIG_HOME/xghost-generated/ghostty/colors.conf" ]
	[ -f "$XDG_CONFIG_HOME/xghost-generated/hypr/colors.conf" ]
	[ -f "$XDG_CONFIG_HOME/xghost-generated/hypr/monitors.conf" ]
}

@test "a second installation changes nothing and reports what is already in place" {
	run -0 "$INSTALL"
	run -0 "$XGHOST" theme current
	first=$output

	run -0 "$INSTALL"
	[[ $output == *"already linked: $XDG_CONFIG_HOME/hypr"* ]]
	[[ $output == *"already linked: $XGHOST_BIN_DIR/xghost"* ]]
	[[ $output == *"the installation is complete"* ]]

	run -0 "$XGHOST" theme current
	[ "$output" = "$first" ]
}

@test "an installation that stopped part way through is resumed by running it again" {
	# The first run stops in the packaging group, with the config group and the
	# post-install group untouched.
	missing_packages blueman
	cat >"$STUB_DIR/pacman" <<-'STUB'
		#!/usr/bin/env bash
		if [ "${1:-}" = -T ]; then
			shift
			[ "${1:-}" = -- ] && shift
			status=0
			for name in "$@"; do
				if grep -qxF -- "$name" "$STUB_DIR/missing"; then
					printf '%s\n' "$name"
					status=127
				fi
			done
			exit "$status"
		fi
		exit 1
	STUB
	chmod +x "$STUB_DIR/pacman"

	run -1 "$INSTALL"
	[[ $output == *"the step packaging/10-official.sh failed"* ]]
	[ ! -e "$XDG_CONFIG_HOME/hypr" ]

	# The second run meets a machine that has the package, and finishes.
	stub_programs
	run -0 "$INSTALL"
	[[ $output == *"the installation is complete"* ]]
	[ -L "$XDG_CONFIG_HOME/hypr" ]
	run -0 "$XGHOST" theme current
	[ "$output" = macos-dark ]
}

@test "the installation keeps a theme the user has already set" {
	run -0 "$INSTALL"
	run -0 "$XGHOST" theme set tokyonight

	run -0 "$INSTALL"
	[[ $output == *"the theme 'tokyonight' is already active"* ]]
	run -0 "$XGHOST" theme current
	[ "$output" = tokyonight ]
}

@test "--theme names the theme an installation sets" {
	run -0 "$INSTALL" --theme tokyonight
	run -0 "$XGHOST" theme current
	[ "$output" = tokyonight ]
}

# A theme that is set and whose record cannot be read is not a machine with no
# theme, and the two used to be told apart by nothing. Rendering the default
# over a theme the user chose is the switch this step promises never to make,
# and the state directory is a directory people clear out.
@test "an installation refuses to replace a theme whose record it cannot read" {
	run -0 "$INSTALL"
	run -0 "$XGHOST" theme set tokyonight
	rm -rf "$XDG_STATE_HOME/xghost/builds"

	run -1 "$INSTALL"
	[[ $output == *"its record cannot be read"* ]]
	[[ $output == *"the step config/30-theme.sh failed"* ]]

	# No build was made, so no theme was rendered over the one the user set.
	[ ! -e "$XDG_STATE_HOME/xghost/builds" ]
}

@test "a named theme is rendered even when the record of the active one is broken" {
	run -0 "$INSTALL"
	rm -rf "$XDG_STATE_HOME/xghost/builds"

	run -0 "$INSTALL" --theme tokyonight
	run -0 "$XGHOST" theme current
	[ "$output" = tokyonight ]
}

#
# Detection, and the facts a second run must not lose.
#

@test "an installation inside a session records the monitors it reads" {
	in_hyprland_session
	run -0 "$INSTALL"

	[ "$(fact MACHINE_MONITOR_COUNT)" = 2 ]
	[ "$(fact MACHINE_MONITOR_1_NAME)" = DP-1 ]
	run -0 grep -c '^monitor = DP-1,' "$GENERATED/hypr/monitors.conf"
	[ "$output" = 1 ]
}

# The installation is run again from a terminal, or over ssh, where hyprctl
# answers nothing at all. The monitors were read correctly once, and a run that
# cannot read them keeps them: putting them back to 'unknown' renders
# 'monitor = ,preferred,auto,auto' over a layout that was right, and leaves the
# facts that were right in a copy that the next run overwrites.
@test "a second installation outside a session keeps the monitors that were read" {
	in_hyprland_session
	run -0 "$INSTALL"
	first=$(cat "$FACTS")

	export HYPRCTL=none
	run -0 "$INSTALL"
	[[ $output == *"these facts keep the value of the previous detection"* ]]

	[ "$(fact MACHINE_MONITOR_COUNT)" = 2 ]
	[ "$(fact MACHINE_MONITOR_1_NAME)" = DP-1 ]
	[ "$(fact MACHINE_MONITOR_2_NAME)" = eDP-1 ]
	[ "$(fact MACHINE_PRIMARY_MONITOR)" = eDP-1 ]
	[ "$(fact MACHINE_COMPOSITOR)" = hyprland ]

	run -0 grep -c '^monitor = DP-1,' "$GENERATED/hypr/monitors.conf"
	[ "$output" = 1 ]
	run -1 grep -c '^monitor = ,preferred,auto,auto' "$GENERATED/hypr/monitors.conf"

	# The file is the file that was already there, so the one copy the design
	# offers still holds what it held.
	[ "$(cat "$FACTS")" = "$first" ]
	[ ! -e "$FACTS.previous" ]
}

@test "a first installation with no session on record reads the monitors as unknown" {
	run -0 "$INSTALL"
	[ "$(fact MACHINE_MONITOR_COUNT)" = unknown ]
	[ "$(fact MACHINE_MONITOR_1_NAME)" = '<absent>' ]
	run -0 grep -c '^monitor = ,preferred,auto,auto' "$GENERATED/hypr/monitors.conf"
	[ "$output" = 1 ]
}

@test "'machine refresh' outside a session keeps the monitors as well" {
	in_hyprland_session
	run -0 "$INSTALL"

	export HYPRCTL=none
	run -0 "$XGHOST" machine refresh
	[ "$(fact MACHINE_MONITOR_COUNT)" = 2 ]
	run -0 grep -c '^monitor = DP-1,' "$GENERATED/hypr/monitors.conf"
	[ "$output" = 1 ]
}

#
# The backup, which is criterion 7.
#

@test "configuration that is in the way is moved into the backup directory" {
	printf 'the ghostty config of the user\n' >"$XDG_CONFIG_HOME/ghostty"

	run -0 "$INSTALL"
	[[ $output == *"backup: moved $XDG_CONFIG_HOME/ghostty to "* ]]
	[ -L "$XDG_CONFIG_HOME/ghostty" ]

	# The backup is the original file, because the linker moves it.
	run -0 find "$XDG_STATE_HOME/xghost/backups" -name ghostty -type f
	[ -n "$output" ]
	[ "$(cat "$output")" = "the ghostty config of the user" ]
}

#
# Post-install.
#

@test "the xghost command is linked, and a path that is not it is left alone" {
	mkdir -p "$XGHOST_BIN_DIR"
	printf 'a command of my own\n' >"$XGHOST_BIN_DIR/xghost"

	run -1 "$INSTALL"
	[[ $output == *"is already there and it is not this command"* ]]
	[[ $output == *"the step post-install/10-command-path.sh failed"* ]]
	[ "$(cat "$XGHOST_BIN_DIR/xghost")" = "a command of my own" ]
}

# Arch puts nothing of ~/.local/bin on the PATH of a login shell, and this
# installer edits no shell file. The autostart runs 'xghost machine refresh' by
# name, so a run that cannot reach the command by name reports the PATH edit as
# the step that is left rather than promising a refresh that fails at every
# login.
@test "the summary reports the PATH edit when the command does not run by name" {
	run -0 "$INSTALL"
	[[ $output == *"does not run by name on this PATH"* ]]
	[[ $output == *"put $XGHOST_BIN_DIR on the PATH of your login shell"* ]]
	[[ $output == *"fails at every login"* ]]
	[[ $output != *"runs at the start of that session, records"* ]]
}

@test "the summary promises the refresh when the command does run by name" {
	mkdir -p "$XGHOST_BIN_DIR"
	export PATH="$XGHOST_BIN_DIR:$PATH"

	run -0 "$INSTALL"
	[[ $output == *"runs at the start of that session, records"* ]]
	[[ $output != *"does not run by name on this PATH"* ]]
}

# A program of the same name that is not this command is not this command. The
# autostart would run that one, so the promise is not the summary to print.
@test "the summary names another xghost the PATH finds first" {
	other="$BATS_TEST_TMPDIR/other"
	mkdir -p "$other"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$other/xghost"
	chmod +x "$other/xghost"
	export PATH="$other:$PATH"

	run -0 "$INSTALL"
	[[ $output == *"does not run by name on this PATH"* ]]
	[[ $output == *"this PATH finds is $other/xghost"* ]]
}

#
# The second detection, which the first login runs.
#

@test "the Hyprland autostart runs 'xghost machine refresh'" {
	run -0 grep -qE '^exec-once = xghost machine refresh$' \
		"$ROOT_DIR/config/hypr/conf/autostart.conf"
}

# The authentication agent. blueman and nm-applet are both started by the same
# file, and both ask for authorisation through polkit, so a session with no
# agent running fails to pair a device and fails to save a system connection,
# with no dialog to answer.
@test "the Hyprland autostart starts the authentication agent the manifest installs" {
	run -0 grep -qxF \
		'exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1' \
		"$ROOT_DIR/config/hypr/conf/autostart.conf"

	load_install_lib
	run -0 install_read_manifest "$INSTALL_PACKAGES_DIR/base.txt"
	[[ $'\n'$output$'\n' == *$'\n'"polkit-gnome"$'\n'* ]]
}

@test "'machine refresh' writes the facts again and renders the active theme" {
	run -0 "$INSTALL"
	run -0 "$XGHOST" machine refresh
	[[ $output == *"is rendered again from the machine facts"* ]]

	[ -f "$FACTS" ]
	run -0 "$XGHOST" theme current
	[ "$output" = macos-dark ]
}

@test "'machine refresh' with no theme active writes the facts and stops there" {
	run -0 "$XGHOST" machine refresh
	[[ $output == *"no theme is active"* ]]
	[ -f "$FACTS" ]
}

@test "'machine refresh' takes no argument" {
	run -2 "$XGHOST" machine refresh please
	[[ $output == *"takes no argument"* ]]
}
