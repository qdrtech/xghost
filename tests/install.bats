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

	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XGHOST_BIN_DIR="$HOME/.local/bin"
	export XGHOST_OS_RELEASE="$FIXTURES/os-release/arch"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	GENERATED="$XDG_STATE_HOME/xghost/generated"
	FACTS="$XDG_CONFIG_HOME/xghost/machine.conf"

	stub_programs
}

# Put a stub pacman, sudo and AUR helper first on the PATH.
#
# The stub pacman keeps its state in one file. 'pacman -T' prints the names that
# file holds, which is the set this machine is missing, and 'pacman -S' takes
# the names it was given out of that set and records the call. A step that
# installs therefore changes the answer of the next test, exactly as a real
# installation would, and nothing is installed anywhere.
stub_programs() {
	STUB_DIR="$BATS_TEST_TMPDIR/stub"
	mkdir -p "$STUB_DIR"
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

	chmod +x "$STUB_DIR/pacman" "$STUB_DIR/sudo" "$STUB_DIR/yay"
	PATH="$STUB_DIR:$PATH"
	export PATH
}

# Give the step a machine with no AUR helper.
#
# The stub is removed and the list of helpers to look for is replaced, because
# the machine that runs the suite may carry a real yay or paru and this suite
# must never reach one. A helper of that name is what a machine with no helper
# looks like to the step.
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

@test "the base manifest declares every package the Hyprland bundle page lists" {
	load_install_lib
	run -0 install_read_manifest "$INSTALL_PACKAGES_DIR/base.txt"
	declared=$output
	run -0 install_read_manifest "$INSTALL_PACKAGES_DIR/aur.txt"
	declared="$declared"$'\n'"$output"

	# The rows of the package table of the bundle page, which is the table the
	# manifest is derived from.
	while IFS= read -r name; do
		[[ $'\n'$declared$'\n' == *$'\n'"$name"$'\n'* ]] || {
			printf 'docs/bundles/hyprland.md lists %s and no manifest declares it\n' "$name" >&2
			return 1
		}
	done < <(sed -n 's/^| `\([a-z0-9@._+-]*\)` *|.*|.*|$/\1/p' "$ROOT_DIR/docs/bundles/hyprland.md")
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

#
# The second detection, which the first login runs.
#

@test "the Hyprland autostart runs 'xghost machine refresh'" {
	run -0 grep -qE '^exec-once = xghost machine refresh$' \
		"$ROOT_DIR/config/hypr/conf/autostart.conf"
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
