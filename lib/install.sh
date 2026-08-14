#!/usr/bin/env bash
#
# The installer module: the groups of steps, the order they run in, and the
# package manifests they read.
#
# install.sh at the root of the checkout sources this file and calls
# install_main. The steps under install/steps/ are sourced by install_run_step,
# so a step reaches every function here and needs no shebang and no execute bit.
#
# The four groups run in a fixed order, and that order is the contract of the
# installer rather than a property of the directory listing:
#
#   preflight     refuse a machine this cannot install onto, before anything
#                 changes
#   packaging     install the packages the manifests declare
#   config        link the prescribed configuration, detect the machine, and
#                 render the theme
#   post-install  put the command in reach and report the end state
#
# Inside one group the steps run in the order of their names, which start with
# two digits.
#
# Every step is idempotent. A step that already did its work reports that and
# changes nothing, so an installation that failed part way through is resumed by
# running install.sh again.
#
# The contract of one step:
#
#   - It is sourced into a shell of its own, so 'exit' ends that step and
#     nothing else, and a variable it sets reaches no other step.
#   - It reports a problem with install_fail, which prints the problem, prints
#     what to do about it, and ends the step. The runner then names the step.
#   - A step that ends non-zero without calling install_fail is still named by
#     the runner, because that shell runs under 'set -e'.
#   - Under a dry run it reports what it would do with install_would and changes
#     nothing.
#
# Environment:
#   XGHOST_OS_RELEASE     The os-release file preflight reads. The tests use this.
#   XGHOST_STEPS_DIR      The step directory. The tests use this.
#   XGHOST_PACKAGES_DIR   The manifest directory. The tests use this.
#   XGHOST_BIN_DIR        The directory the 'xghost' command is linked into.
#                         The default is $HOME/.local/bin.
#   XGHOST_INSTALL_THEME  The theme a first installation sets.
#   XGHOST_AUR_HELPERS    The AUR helpers to look for, in the order to look.
#                         The default is 'yay paru'.

# The include sentinel. A second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_INSTALL_SOURCED:-}" ]; then
	return 0
fi
XGHOST_INSTALL_SOURCED=1

# The environment may carry BASHOPTS or SHELLOPTS, and both change how the
# globs in this file behave. Normalise every option this file depends on.
shopt -u dotglob nocaseglob failglob
unset GLOBIGNORE
set +f

XGHOST_INSTALL_PROGRAM=xghost

# The groups, in the order they run. The order is the contract.
readonly INSTALL_GROUPS=(preflight packaging config post-install)

# A step file is two digits, a hyphen, a name, and '.sh'. The digits are what
# orders the steps of one group.
readonly INSTALL_STEP_PATTERN='^[0-9][0-9]-[a-z0-9-]+\.sh$'

# An Arch package name: lower case letters, digits, and the four punctuation
# characters a package name may hold. It never opens with a hyphen or a dot.
readonly INSTALL_PACKAGE_PATTERN='^[a-z0-9][a-z0-9@._+-]*$'

# The theme a first installation sets. The dotfiles this project carries its
# configuration over from name this one in their own post-deployment step
# (qdrtech/dotfiles, docs/installation.md). '--theme NAME' overrides it, and an
# installation that finds a theme already active keeps that one instead.
readonly INSTALL_DEFAULT_THEME=macos-dark

# The AUR helpers this looks for, in the order it looks. A machine that carries
# another one names it here.
INSTALL_AUR_HELPERS=${XGHOST_AUR_HELPERS:-"yay paru"}

# Set by install.sh from its options. Each one keeps the value it already
# carries, because install_run_step hands these to the shell of a step through
# the environment and that shell sources this file again.
INSTALL_DRY_RUN=${INSTALL_DRY_RUN:-no}
INSTALL_THEME=${INSTALL_THEME:-${XGHOST_INSTALL_THEME:-$INSTALL_DEFAULT_THEME}}

# Whether the theme above was asked for with '--theme'. A theme the caller
# named wins over the theme that is already active; the default one does not,
# because a second run of the installer must not undo a switch the user made.
INSTALL_THEME_GIVEN=${INSTALL_THEME_GIVEN:-no}

install_say() {
	printf '%s\n' "$*"
}

install_warn() {
	printf '%s: %s\n' "$XGHOST_INSTALL_PROGRAM" "$*" >&2
}

# Report what a dry run would have done.
install_would() {
	printf 'would: %s\n' "$*"
}

# End one step with a report. The first argument is the problem, the second is
# what the reader does about it. Both are printed, and neither is optional: a
# step that stops without saying what to do next leaves the reader with a
# failed installation and no move.
install_fail() {
	local problem=$1 remedy=$2
	install_warn "$problem"
	install_warn "what to do: $remedy"
	exit 1
}

# Resolve every path the installer uses. The checkout is the directory above
# this file, so the installer runs from wherever it was cloned.
install_paths() {
	INSTALL_LIB_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
	INSTALL_ROOT=$(cd -P "$INSTALL_LIB_DIR/.." && pwd)
	INSTALL_STEPS_DIR=${XGHOST_STEPS_DIR:-$INSTALL_ROOT/install/steps}
	INSTALL_PACKAGES_DIR=${XGHOST_PACKAGES_DIR:-$INSTALL_ROOT/install/packages}

	# The command the config steps run. It is the one in this checkout, never
	# one the PATH happens to hold, because the installation being made is this
	# checkout.
	INSTALL_XGHOST=$INSTALL_ROOT/bin/$XGHOST_INSTALL_PROGRAM
}

# Print one package per line from a manifest.
#
#   install_read_manifest FILE
#
# A '#' starts a comment, whether it opens the line or follows a package name.
# An empty line is allowed, and the white space at both ends of a name is
# dropped.
#
# Returns 1 when the file cannot be read, or when at least one line holds
# something that is not a package name. Every bad line is reported with its
# number, not only the first, because a manifest is corrected in one pass.
install_read_manifest() {
	local file=$1
	local line name
	local lineno=0 status=0
	local -a names=()

	if [ ! -f "$file" ] || [ ! -r "$file" ]; then
		install_warn "the package manifest is missing or cannot be read: $file"
		return 1
	fi

	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))
		name=${line%%#*}
		name=${name#"${name%%[![:space:]]*}"}
		name=${name%"${name##*[![:space:]]}"}
		if [ -z "$name" ]; then
			continue
		fi
		if [[ ! $name =~ $INSTALL_PACKAGE_PATTERN ]]; then
			install_warn "$file line $lineno: '$name' is not an Arch package name"
			status=1
			continue
		fi
		names+=("$name")
	done <"$file"

	if [ "$status" -ne 0 ]; then
		return 1
	fi
	if [ "${#names[@]}" -gt 0 ]; then
		printf '%s\n' "${names[@]}"
	fi
}

# Print the packages of a list that this machine does not have, one per line.
#
#   install_missing_packages NAME ...
#
# 'pacman -T' is the test rather than 'pacman -Q', because it counts a package
# that another installed package provides as satisfied. It reads the local
# database, it needs no root, and it changes nothing. It exits 127 when at least
# one name is unsatisfied and 0 when they are all satisfied, so any other status
# is a failure of pacman itself and is reported as one.
install_missing_packages() {
	local output status=0

	if [ $# -eq 0 ]; then
		return 0
	fi

	# A pacman that is not there ends with 127 as well, and that is the status
	# pacman itself uses for "something is missing". The two are told apart here,
	# because reading the second as the first would report that this machine has
	# every package.
	if ! command -v pacman >/dev/null 2>&1; then
		install_warn "the 'pacman' program is not installed, so the packages that are missing are not known"
		return 1
	fi

	output=$(pacman -T -- "$@") || status=$?
	if [ "$status" -ne 0 ] && [ "$status" -ne 127 ]; then
		install_warn "'pacman -T' ended with status $status, so the packages that are missing are not known"
		return 1
	fi

	if [ -n "$output" ]; then
		printf '%s\n' "$output"
	fi
}

# Run one step of one group.
#
#   install_run_step GROUP FILE-NAME
#
# The step is sourced into a shell of its own, which sources this module first,
# so the step reaches every function and every path here and needs no shebang
# and no execute bit. That shell keeps one step from setting a variable the next
# step reads.
#
# The shell is a separate process rather than a subshell, and the reason is
# 'set -e'. A subshell that is part of a '||' list runs with -e ignored, and
# bash ignores it for every command inside that subshell, including a 'set -e'
# the subshell runs itself. A step whose command failed would then carry on to
# its next line and report success. A separate process has its own -e, so a step
# that fails a command it did not guard stops there, and the runner names it.
install_run_step() {
	local group=$1 base=$2
	local path=$INSTALL_STEPS_DIR/$group/$base
	local status=0

	install_say "-- $group/$base"

	# The shell of the step. It reads two paths and the options of this run from
	# its environment, because it starts with none of them.
	local runner='
set -euo pipefail
. "$XGHOST_INSTALL_LIB"
install_paths
. "$XGHOST_INSTALL_STEP"
'

	XGHOST_INSTALL_LIB=$INSTALL_LIB_DIR/install.sh \
		XGHOST_INSTALL_STEP=$path \
		INSTALL_DRY_RUN=$INSTALL_DRY_RUN \
		INSTALL_THEME=$INSTALL_THEME \
		INSTALL_THEME_GIVEN=$INSTALL_THEME_GIVEN \
		"${BASH:-bash}" -c "$runner" || status=$?

	if [ "$status" -ne 0 ]; then
		install_warn "the step $group/$base failed"
		install_warn "what to do: fix the problem reported above, then run './install.sh' again. Every step is idempotent, so the steps that already did their work do nothing the second time."
		return 1
	fi
}

# Run every step of one group, in the order of the step names.
install_run_group() {
	local group=$1
	local dir=$INSTALL_STEPS_DIR/$group
	local path base
	local -a found=() ordered=()

	if [ ! -d "$dir" ]; then
		install_warn "the step directory of the group '$group' is missing: $dir"
		install_warn "what to do: check the repository out again. The installer runs four groups, and every one of them is part of it."
		return 1
	fi

	for path in "$dir"/*; do
		if [ ! -f "$path" ]; then
			continue
		fi
		base=${path##*/}
		if [[ ! $base =~ $INSTALL_STEP_PATTERN ]]; then
			install_warn "$group: '$base' is not a step file; a step is named NN-name.sh"
			install_warn "what to do: rename it or remove it from $dir. The installer runs every file of a group, so it will not pass one over in silence."
			return 1
		fi
		found+=("$base")
	done

	if [ "${#found[@]}" -eq 0 ]; then
		install_warn "the group '$group' holds no step: $dir"
		install_warn "what to do: check the repository out again. A group with no step is a missing part of the installer, not an empty one."
		return 1
	fi

	while IFS= read -r base; do
		ordered+=("$base")
	done < <(printf '%s\n' "${found[@]}" | LC_ALL=C sort)

	for base in "${ordered[@]}"; do
		install_run_step "$group" "$base" || return 1
	done
}

install_usage() {
	cat <<'USAGE'
xghost — install a prescribed Arch Linux desktop.

Usage: ./install.sh [option ...]

Options:
  --dry-run        Report what every step would do and change nothing.
  --theme NAME     Set this theme instead of the default one. An installation
                   that finds a theme already active keeps that one.
  -h, --help       Print this text.

The installer runs four groups of steps in order: preflight, packaging, config
and post-install. Every step is idempotent, so an installation that stopped
part way through is resumed by running this command again.

docs/installing.md records what each group does and why the order is what it is.
USAGE
}

install_main() {
	local group

	while [ $# -gt 0 ]; do
		case $1 in
		--dry-run)
			INSTALL_DRY_RUN=yes
			;;
		--theme)
			if [ $# -lt 2 ]; then
				install_warn "'--theme' needs a theme name"
				return 2
			fi
			INSTALL_THEME=$2
			INSTALL_THEME_GIVEN=yes
			shift
			;;
		--theme=*)
			INSTALL_THEME=${1#--theme=}
			INSTALL_THEME_GIVEN=yes
			;;
		-h | --help)
			install_usage
			return 0
			;;
		*)
			install_warn "unknown option '$1'. Run './install.sh --help' for the options."
			return 2
			;;
		esac
		shift
	done

	install_paths

	install_say "xghost installs from $INSTALL_ROOT"
	if [ "$INSTALL_DRY_RUN" = yes ]; then
		install_say "this is a dry run: every step reports what it would do, and nothing is changed."
	fi

	for group in "${INSTALL_GROUPS[@]}"; do
		install_run_group "$group" || return 1
	done

	if [ "$INSTALL_DRY_RUN" = yes ]; then
		install_say "the dry run is complete. Nothing was changed."
		return 0
	fi

	install_say "the installation is complete."
}
