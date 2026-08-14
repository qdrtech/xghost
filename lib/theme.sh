#!/usr/bin/env bash
#
# The theme module: where the generated output lives, which theme is active,
# and how a switch is made atomic.
#
# The commands in commands/theme-* source this file. It sources the renderer
# and the palette reader itself.
#
# The generated output lands under the user's state directory, outside every
# repository working tree. docs/theming.md records that decision.
#
# Environment:
#   XGHOST_ROOT           Override the checkout. The tests use this.
#   XGHOST_THEMES_DIR     Override the theme directory.
#   XGHOST_TEMPLATE_DIR   Override the template directory.
#   XDG_STATE_HOME        The state directory, per the XDG base directory
#                         specification. An empty or relative value is ignored,
#                         as the specification requires.

# The environment may carry BASHOPTS or SHELLOPTS, and both change how the
# globs in this file behave. Normalise every option this file depends on.
shopt -u dotglob nocaseglob failglob
unset GLOBIGNORE
set +f

XGHOST_LIB_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/palette.sh
. "$XGHOST_LIB_DIR/palette.sh"
# shellcheck source=lib/renderer.sh
. "$XGHOST_LIB_DIR/renderer.sh"

XGHOST_PROGRAM=xghost

# A theme name is also a directory name, so the pattern keeps a path separator
# and a leading dot out of it.
readonly THEME_NAME_PATTERN='^[a-z0-9][a-z0-9-]*$'

# The palette file of a theme. A directory without one is not a theme.
readonly THEME_PALETTE_FILE=palette.conf

# Set by the functions below when they return non-zero.
THEME_PROBLEM=

xghost_warn() {
	printf '%s: %s\n' "$XGHOST_PROGRAM" "$*" >&2
}

xghost_die() {
	local code=$1
	shift
	xghost_warn "$*"
	exit "$code"
}

# The state directory of the user, per the XDG base directory specification.
# The specification says a relative value is invalid and must be ignored.
xghost_state_home() {
	local base=${XDG_STATE_HOME:-}
	if [ -z "$base" ] || [ "${base:0:1}" != / ]; then
		if [ -z "${HOME:-}" ]; then
			return 1
		fi
		base=$HOME/.local/state
	fi
	printf '%s\n' "$base"
}

theme_paths_init() {
	local state_home
	if ! state_home=$(xghost_state_home); then
		xghost_die 1 "neither XDG_STATE_HOME nor HOME is set, so the generated output has no home"
	fi

	XGHOST_ROOT=${XGHOST_ROOT:-$(cd -P "$XGHOST_LIB_DIR/.." && pwd)}
	XGHOST_THEMES_DIR=${XGHOST_THEMES_DIR:-$XGHOST_ROOT/themes}
	XGHOST_TEMPLATE_DIR=${XGHOST_TEMPLATE_DIR:-$XGHOST_ROOT/templates}

	XGHOST_STATE_DIR=$state_home/$XGHOST_PROGRAM

	# The stable path applications reference. It is a symbolic link, because a
	# link is what the kernel replaces in one step. See theme_set.
	XGHOST_GENERATED_DIR=$XGHOST_STATE_DIR/generated

	# One directory per build. The link above points into the live one.
	XGHOST_BUILDS_DIR=$XGHOST_STATE_DIR/builds
}

theme_paths_init

# Print the name of every theme, one per line, sorted.
#
# A directory of themes/ that holds no palette file is not a theme and is left
# out. Returns 1 when there is no theme to list.
theme_list() {
	THEME_PROBLEM=

	if [ ! -d "$XGHOST_THEMES_DIR" ]; then
		THEME_PROBLEM="the theme directory does not exist: $XGHOST_THEMES_DIR"
		return 1
	fi

	local path base
	local -a names=()

	for path in "$XGHOST_THEMES_DIR"/*; do
		if [ ! -d "$path" ]; then
			continue
		fi
		base=${path##*/}
		if [[ ! $base =~ $THEME_NAME_PATTERN ]]; then
			continue
		fi
		if [ ! -f "$path/$THEME_PALETTE_FILE" ]; then
			continue
		fi
		names+=("$base")
	done

	if [ "${#names[@]}" -eq 0 ]; then
		THEME_PROBLEM="no theme is installed in $XGHOST_THEMES_DIR"
		return 1
	fi

	printf '%s\n' "${names[@]}" | LC_ALL=C sort
}

# Print the name of the active theme.
#
# The name is read from the build the stable path points at, so the link and the
# name can never disagree. Returns 1 when no theme is active.
theme_current() {
	THEME_PROBLEM=

	if [ ! -L "$XGHOST_GENERATED_DIR" ]; then
		THEME_PROBLEM="no theme is active. Run '$XGHOST_PROGRAM theme set <name>'."
		return 1
	fi

	local target build name
	target=$(readlink -f "$XGHOST_GENERATED_DIR" || true)
	if [ -z "$target" ] || [ ! -d "$target" ]; then
		THEME_PROBLEM="the generated output is broken: $XGHOST_GENERATED_DIR points at nothing. Run '$XGHOST_PROGRAM theme set <name>'."
		return 1
	fi

	build=${target%/*}
	if [ ! -f "$build/theme" ]; then
		THEME_PROBLEM="the generated output is broken: the build at $build does not record its theme. Run '$XGHOST_PROGRAM theme set <name>'."
		return 1
	fi

	IFS= read -r name <"$build/theme" || true
	if [ -z "$name" ]; then
		THEME_PROBLEM="the generated output is broken: the build at $build records an empty theme name. Run '$XGHOST_PROGRAM theme set <name>'."
		return 1
	fi

	printf '%s\n' "$name"
}

# Render one theme and move the result into place.
#
# The switch is atomic. The renderer builds a complete new output directory
# beside the live one, and the stable path is a symbolic link that the kernel
# replaces in one step. An interrupted or failed render therefore leaves the
# previous theme fully intact: the link still points at its build, and every
# file of that build is still there.
#
# Returns 1 and sets THEME_PROBLEM when the theme is not applied. Every problem
# the renderer found is reported on standard error first.
theme_set() {
	local name=$1

	THEME_PROBLEM=

	if [[ ! $name =~ $THEME_NAME_PATTERN ]]; then
		THEME_PROBLEM="'$name' is not a theme name; a name holds lower case letters, digits and hyphens. Run '$XGHOST_PROGRAM theme list'."
		return 1
	fi

	local theme_dir=$XGHOST_THEMES_DIR/$name
	if [ ! -d "$theme_dir" ] || [ ! -f "$theme_dir/$THEME_PALETTE_FILE" ]; then
		THEME_PROBLEM="unknown theme '$name'. Run '$XGHOST_PROGRAM theme list'."
		return 1
	fi

	if ! mkdir -p "$XGHOST_BUILDS_DIR"; then
		THEME_PROBLEM="cannot create the build directory: $XGHOST_BUILDS_DIR"
		return 1
	fi

	# Drop every build the stable path does not point at. This runs before the
	# render rather than after it, so the previous build survives the switch and
	# is dropped only when the next one succeeds.
	theme_prune_builds

	local staging
	if ! staging=$(mktemp -d "$XGHOST_BUILDS_DIR/build.XXXXXXXX"); then
		THEME_PROBLEM="cannot create a build directory under $XGHOST_BUILDS_DIR"
		return 1
	fi

	# An interrupted render leaves no half-built directory behind.
	trap 'rm -rf "$staging"; exit 130' INT TERM HUP

	local problem
	if ! render_tree "$XGHOST_TEMPLATE_DIR" "$theme_dir" '' '' "$staging/tree"; then
		for problem in "${RENDER_ERRORS[@]}"; do
			xghost_warn "$name: $problem"
		done
		rm -rf "$staging"
		trap - INT TERM HUP
		THEME_PROBLEM="the render of theme '$name' failed. The active theme is unchanged."
		return 1
	fi

	if ! printf '%s\n' "$name" >"$staging/theme"; then
		rm -rf "$staging"
		trap - INT TERM HUP
		THEME_PROBLEM="cannot record the theme name in the build. The active theme is unchanged."
		return 1
	fi

	# The switch itself. 'mv -T' onto the link is one rename, so a reader of the
	# stable path sees either the previous build or the new one, never a
	# half-written directory.
	local pending=$XGHOST_STATE_DIR/generated.pending.$$
	rm -f "$pending"
	if ! ln -s "$staging/tree" "$pending"; then
		rm -rf "$staging"
		trap - INT TERM HUP
		THEME_PROBLEM="cannot prepare the switch to theme '$name'. The active theme is unchanged."
		return 1
	fi
	if ! mv -T "$pending" "$XGHOST_GENERATED_DIR"; then
		rm -f "$pending"
		rm -rf "$staging"
		trap - INT TERM HUP
		THEME_PROBLEM="cannot move the new output into place at $XGHOST_GENERATED_DIR. The active theme is unchanged."
		return 1
	fi

	trap - INT TERM HUP
}

# Drop every build directory the stable path does not point at.
theme_prune_builds() {
	local keep= target path

	if [ -L "$XGHOST_GENERATED_DIR" ]; then
		target=$(readlink -f "$XGHOST_GENERATED_DIR" || true)
		if [ -n "$target" ]; then
			# The target is <build>/tree, so the build is its parent. The name
			# alone is compared, because the path of the build directory may
			# hold a symbolic link of its own.
			target=${target%/*}
			keep=${target##*/}
		fi
	fi

	for path in "$XGHOST_BUILDS_DIR"/*; do
		if [ ! -e "$path" ]; then
			continue
		fi
		if [ -n "$keep" ] && [ "${path##*/}" = "$keep" ]; then
			continue
		fi
		rm -rf "$path"
	done
}
