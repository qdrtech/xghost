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
#   XGHOST_KNOBS_SCHEMA   Override the knob schema the project owns.
#   XDG_STATE_HOME        The state directory, per the XDG base directory
#                         specification. An empty or relative value is ignored,
#                         as the specification requires.

# The include sentinel. A library may be sourced more than once, because two
# modules may each need it. The second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_THEME_SOURCED:-}" ]; then
	return 0
fi
XGHOST_THEME_SOURCED=1

# The environment may carry BASHOPTS or SHELLOPTS, and both change how the
# globs in this file behave. Normalise every option this file depends on.
shopt -u dotglob nocaseglob failglob
unset GLOBIGNORE
set +f

XGHOST_LIB_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/paths.sh
. "$XGHOST_LIB_DIR/paths.sh"
# shellcheck source=lib/palette.sh
. "$XGHOST_LIB_DIR/palette.sh"
# shellcheck source=lib/facts.sh
. "$XGHOST_LIB_DIR/facts.sh"
# shellcheck source=lib/knobs.sh
. "$XGHOST_LIB_DIR/knobs.sh"
# shellcheck source=lib/background.sh
. "$XGHOST_LIB_DIR/background.sh"
# shellcheck source=lib/renderer.sh
. "$XGHOST_LIB_DIR/renderer.sh"

XGHOST_PROGRAM=xghost

# A theme name is also a directory name, so the pattern keeps a path separator
# and a leading dot out of it.
readonly THEME_NAME_PATTERN='^[a-z0-9][a-z0-9-]*$'

# The palette file of a theme. A directory without one is not a theme.
readonly THEME_PALETTE_FILE=palette.conf

# The lock file of the state directory. theme_set holds an exclusive lock on it
# for the whole of a switch, so two switches run one after the other.
readonly THEME_LOCK_FILE=lock

# The modes theme_set sets on what it creates under the state directory. It
# sets them itself rather than leaving them to the umask of the caller, so the
# same switch produces the same modes on every machine. The renderer sets the
# modes inside the output tree; see RENDER_DIR_MODE in lib/renderer.sh.
readonly THEME_DIR_MODE=0755
readonly THEME_FILE_MODE=0644

# Set by the functions below when they return non-zero.
THEME_PROBLEM=

# The machine facts file the render reads, or empty when there is none. It is
# resolved by theme_set and read by theme_set_locked.
THEME_FACTS_FILE=

# The knobs file the render reads, or empty when there is none. Empty means
# every knob takes the default the schema gives it, which is what a machine that
# has never run 'xghost settings set' renders with.
THEME_KNOBS_FILE=

xghost_warn() {
	printf '%s: %s\n' "$XGHOST_PROGRAM" "$*" >&2
}

xghost_die() {
	local code=$1
	shift
	xghost_warn "$*"
	exit "$code"
}

# The paths inside the checkout.
#
# They need no state directory, so a command that only reads the checkout is
# never stopped by a machine that has neither XDG_STATE_HOME nor HOME.
theme_repo_paths() {
	XGHOST_ROOT=${XGHOST_ROOT:-$(cd -P "$XGHOST_LIB_DIR/.." && pwd)}
	XGHOST_THEMES_DIR=${XGHOST_THEMES_DIR:-$XGHOST_ROOT/themes}
	XGHOST_TEMPLATE_DIR=${XGHOST_TEMPLATE_DIR:-$XGHOST_ROOT/templates}

	# The knob schema belongs to the project, so it lives in the checkout beside
	# the templates. The file that answers it belongs to the user and lives in
	# the config directory: see knobs_path in lib/knobs.sh.
	XGHOST_KNOBS_SCHEMA=${XGHOST_KNOBS_SCHEMA:-$XGHOST_ROOT/schema/knobs.conf}
}

# The paths under the state directory of the user.
#
# They are resolved at first use, not when this file is sourced. A missing
# state directory is a problem of the command that needs one, and it must not
# reach a command that needs none: 'theme list' reads the checkout alone.
#
# Returns 1 and sets THEME_PROBLEM when the state directory has no home.
theme_state_paths() {
	local state_home
	if ! state_home=$(xghost_state_home); then
		THEME_PROBLEM="neither XDG_STATE_HOME nor HOME is set, so the generated output has no home"
		return 1
	fi

	XGHOST_STATE_DIR=$state_home/$XGHOST_STATE_SUBDIR

	# The stable path applications reference. It is a symbolic link, because a
	# link is what the kernel replaces in one step. See theme_set.
	#
	# It is composed by lib/paths.sh rather than here, because lib/reload.sh
	# names the same path in the request it sends to the wallpaper daemon and
	# the two have to be the same path. The call cannot fail here: the state
	# directory is resolved above.
	XGHOST_GENERATED_DIR=$(xghost_generated_dir)

	# One directory per build. The link above points into the live one.
	XGHOST_BUILDS_DIR=$XGHOST_STATE_DIR/builds
}

# Print the name of every theme, one per line, sorted.
#
# A directory of themes/ that holds no palette file is not a theme and is left
# out. Returns 1 when there is no theme to list.
theme_list() {
	THEME_PROBLEM=

	theme_repo_paths

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

	if ! theme_state_paths; then
		return 1
	fi

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
# The whole switch runs under an exclusive lock on the state directory, so two
# switches that start at the same time run one after the other. Without the
# lock one switch deletes the half-built directory of the other, and the stable
# path can end up pointing at nothing while both commands report success.
#
# Returns 1 and sets THEME_PROBLEM when the theme is not applied. Every problem
# the renderer found is reported on standard error first.
theme_set() {
	local name=$1
	local theme_facts_file= theme_knobs_file=

	THEME_PROBLEM=

	theme_repo_paths

	if [[ ! $name =~ $THEME_NAME_PATTERN ]]; then
		THEME_PROBLEM="'$name' is not a theme name; a name holds lower case letters, digits and hyphens. Run '$XGHOST_PROGRAM theme list'."
		return 1
	fi

	local theme_dir=$XGHOST_THEMES_DIR/$name
	if [ ! -d "$theme_dir" ] || [ ! -f "$theme_dir/$THEME_PALETTE_FILE" ]; then
		THEME_PROBLEM="unknown theme '$name'. Run '$XGHOST_PROGRAM theme list'."
		return 1
	fi

	if ! theme_state_paths; then
		return 1
	fi

	# The machine facts are the second input of the renderer. A machine that
	# has not run 'xghost machine detect' has no such file, and the render then
	# has the palette alone. That is not a failure here: a template that names
	# a machine fact fails the render itself, and names the value it wanted.
	#
	# Anything at that path is passed on, whatever it is. A directory or a link
	# that points at nothing is a broken file rather than an absent one, and
	# facts_load names which of the two it found. Testing for a regular file
	# here would report a missing value instead of a broken file.
	THEME_FACTS_FILE=
	if theme_facts_file=$(facts_path) &&
		{ [ -e "$theme_facts_file" ] || [ -L "$theme_facts_file" ]; }; then
		THEME_FACTS_FILE=$theme_facts_file
	fi

	# The knobs are the third input. A machine that has never changed a
	# preference has no such file, and every knob then takes the default of the
	# schema, so the render succeeds and the desktop carries the values the
	# project chose. That is the whole difference from the machine facts: a knob
	# always has a value, and a fact nobody read has none.
	#
	# Anything at that path is passed on, whatever it is, for the reason above.
	THEME_KNOBS_FILE=
	if theme_knobs_file=$(knobs_path) &&
		{ [ -e "$theme_knobs_file" ] || [ -L "$theme_knobs_file" ]; }; then
		THEME_KNOBS_FILE=$theme_knobs_file
	fi

	if ! command -v flock >/dev/null 2>&1; then
		THEME_PROBLEM="the 'flock' program is not installed, and a switch needs it to lock the state directory. It ships in util-linux."
		return 1
	fi

	if ! mkdir -p "$XGHOST_BUILDS_DIR" 2>/dev/null; then
		THEME_PROBLEM="cannot create the build directory: $XGHOST_BUILDS_DIR"
		return 1
	fi
	if ! chmod "$THEME_DIR_MODE" "$XGHOST_STATE_DIR" "$XGHOST_BUILDS_DIR" 2>/dev/null; then
		THEME_PROBLEM="cannot set the mode of the state directory: $XGHOST_STATE_DIR"
		return 1
	fi

	# The lock file is opened by descriptor and never removed, because a lock
	# on a file another process has already unlinked locks nothing.
	local lock_path=$XGHOST_STATE_DIR/$THEME_LOCK_FILE
	local lock_fd status=0
	if ! { exec {lock_fd}>"$lock_path"; } 2>/dev/null; then
		THEME_PROBLEM="cannot open the lock file $lock_path"
		return 1
	fi
	if ! flock -x "$lock_fd" 2>/dev/null; then
		{ exec {lock_fd}>&-; } 2>/dev/null
		THEME_PROBLEM="cannot lock the state directory $XGHOST_STATE_DIR"
		return 1
	fi

	theme_set_locked "$name" "$theme_dir" || status=$?

	# Closing the descriptor releases the lock.
	{ exec {lock_fd}>&-; } 2>/dev/null

	return "$status"
}

# The body of theme_set, run with the lock on the state directory held.
#
#   theme_set_locked NAME THEME_DIR
#
# Returns 1 and sets THEME_PROBLEM when the theme is not applied.
theme_set_locked() {
	local name=$1 theme_dir=$2

	local staging
	if ! staging=$(mktemp -d "$XGHOST_BUILDS_DIR/build.XXXXXXXX" 2>/dev/null); then
		THEME_PROBLEM="cannot create a build directory under $XGHOST_BUILDS_DIR"
		return 1
	fi

	# An interrupted render leaves no half-built directory behind.
	trap 'rm -rf "$staging"; exit 130' INT TERM HUP

	local problem
	if ! render_tree "$XGHOST_TEMPLATE_DIR" "$theme_dir" "$THEME_FACTS_FILE" \
		"$XGHOST_KNOBS_SCHEMA" "$THEME_KNOBS_FILE" "$staging/tree"; then
		for problem in "${RENDER_ERRORS[@]}"; do
			xghost_warn "$name: $problem"
		done
		rm -rf "$staging"
		trap - INT TERM HUP
		THEME_PROBLEM="the render of theme '$name' failed. The active theme is unchanged."
		return 1
	fi

	# The one file of the output the renderer cannot write, and the reason is
	# the path inside it. hyprpaper resolves the path of a wallpaper against the
	# working directory of the daemon, so the file names the image in full, and
	# the full path is the stable path of the generated output. The renderer is
	# a pure function of the theme, the facts and the knobs, and where its
	# output will be moved to is none of those. lib/background.sh records it.
	#
	# It is written into the build before the switch, so it lands with the
	# image it names and the two can never disagree.
	if [ -n "$RENDER_BACKGROUND_NOTE" ]; then
		xghost_warn "$name: $RENDER_BACKGROUND_NOTE"
	fi
	if ! theme_write_wallpaper "$staging/tree"; then
		rm -rf "$staging"
		trap - INT TERM HUP
		return 1
	fi

	if ! printf '%s\n' "$name" 2>/dev/null >"$staging/theme"; then
		rm -rf "$staging"
		trap - INT TERM HUP
		THEME_PROBLEM="cannot record the theme name in the build. The active theme is unchanged."
		return 1
	fi
	if ! chmod "$THEME_DIR_MODE" "$staging" 2>/dev/null ||
		! chmod "$THEME_FILE_MODE" "$staging/theme" 2>/dev/null; then
		rm -rf "$staging"
		trap - INT TERM HUP
		THEME_PROBLEM="cannot set the mode of the new build. The active theme is unchanged."
		return 1
	fi

	# The switch itself. 'mv -T' onto the link is one rename, so a reader of the
	# stable path sees either the previous build or the new one, never a
	# half-written directory.
	local pending
	pending=$(xghost_pending_path "$XGHOST_STATE_DIR" "$$")
	rm -f "$pending" 2>/dev/null
	if ! ln -s "$staging/tree" "$pending" 2>/dev/null; then
		rm -rf "$staging"
		trap - INT TERM HUP
		THEME_PROBLEM="cannot prepare the switch to theme '$name'. The active theme is unchanged."
		return 1
	fi
	if ! mv -T "$pending" "$XGHOST_GENERATED_DIR" 2>/dev/null; then
		rm -f "$pending"
		rm -rf "$staging"
		trap - INT TERM HUP
		THEME_PROBLEM="cannot move the new output into place at $XGHOST_GENERATED_DIR. The active theme is unchanged."
		return 1
	fi

	trap - INT TERM HUP

	# Drop the builds the stable path no longer points at. This runs after the
	# rename, and under the lock, so every directory it can reach is a build
	# that some switch finished. A directory another switch is still writing is
	# therefore out of its reach.
	theme_prune_builds
}

# Write the hyprpaper file that names the background of one build.
#
#   theme_write_wallpaper TREE
#
# TREE is the output directory the renderer has just filled. The file lands
# inside it, so it is moved into place by the same rename as everything else
# and a reader sees the image and the file that names it together.
#
# The path it holds is the stable path, not the path of this build. A build
# directory is replaced by the next switch, and the stable path is the one the
# desktop is configured against, so a daemon that reads this file after a
# switch reads the wallpaper of the theme that is active.
#
# Returns 1 and sets THEME_PROBLEM when the file cannot be written.
theme_write_wallpaper() {
	local tree=$1
	local destination=$tree/$BACKGROUND_WALLPAPER_RELATIVE
	local image=

	if [ -n "$RENDER_BACKGROUND" ]; then
		image=$XGHOST_GENERATED_DIR/$RENDER_BACKGROUND
	fi

	if ! mkdir -p "${destination%/*}" 2>/dev/null; then
		THEME_PROBLEM="cannot create the directory that holds the wallpaper file: ${destination%/*}. The active theme is unchanged."
		return 1
	fi
	if ! background_wallpaper_conf "$image" "$RENDER_BACKGROUND_NOTE" \
		2>/dev/null >"$destination"; then
		THEME_PROBLEM="cannot write the wallpaper file at $destination. The active theme is unchanged."
		return 1
	fi
	if ! chmod "$THEME_DIR_MODE" "${destination%/*}" 2>/dev/null ||
		! chmod "$THEME_FILE_MODE" "$destination" 2>/dev/null; then
		THEME_PROBLEM="cannot set the mode of the wallpaper file at $destination. The active theme is unchanged."
		return 1
	fi
}

# Drop every build directory the stable path does not point at.
#
# The caller holds the lock on the state directory, and has already moved the
# new build into place.
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
		# The switch has already happened, so a build that cannot be dropped is
		# wasted space and nothing worse. It is named, and it does not turn a
		# finished switch into a failure.
		if ! rm -rf "$path" 2>/dev/null; then
			xghost_warn "cannot drop the old build $path. The new theme is in place all the same."
		fi
	done

	return 0
}
