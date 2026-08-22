#!/usr/bin/env bash
#
# Where this project keeps what it writes.
#
# The generated output lands under the state directory of the user, and two
# modules need to know where that is. lib/theme.sh renders into it. lib/reload.sh
# names a file of it in a request it sends to a running daemon. A copy of the
# rule in each module is two answers to one question, and the day they disagree
# the reload names a file the render never wrote.
#
# So the rule lives here, and both modules read it.
#
# lib/reload.sh cannot read it through lib/theme.sh instead. That module sources
# the palette reader, the machine facts, the knobs, the background and the
# renderer, which is the whole render, and the reload runs four commands and
# writes nothing.
#
# The rule itself is the XDG base directory specification. The specification
# says a relative XDG_STATE_HOME is invalid and has to be ignored, so a relative
# value falls back to '$HOME/.local/state' rather than being used.
#
# lib/linker.sh keeps a rule of its own and it is a different rule: it reads an
# XGHOST_STATE_DIR override, and it refuses a relative path with a diagnostic
# instead of ignoring it, because that path is written into the link record it
# owns. Moving it here would change what the linker does with a relative value,
# which is a change to the linker rather than to this file.
#
# Environment:
#   XDG_STATE_HOME   The state directory, per the XDG base directory
#                    specification. An empty or relative value is ignored, as
#                    the specification requires.
#   HOME             The directory the fallback is built from.

# The include sentinel. A library may be sourced more than once, because two
# modules may each need it. The second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_PATHS_SOURCED:-}" ]; then
	return 0
fi
XGHOST_PATHS_SOURCED=1

# The directory of this project inside the state directory of the user, and the
# name of the stable path inside that. They are constants rather than the
# XGHOST_PROGRAM variable, which is the name a report calls the program by: a
# command that changed that name for a message would otherwise move the
# generated output.
readonly XGHOST_STATE_SUBDIR=xghost
readonly XGHOST_GENERATED_NAME=generated

# The state directory of the user, per the XDG base directory specification.
# The specification says a relative value is invalid and must be ignored.
#
# Prints the directory. Returns 1 when neither XDG_STATE_HOME nor HOME says
# where it is.
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

# The stable path of the generated output.
#
# This is the path the desktop is configured against. It is a symbolic link
# that 'xghost theme set' replaces in one step, so a program that reads through
# it after a switch reads the theme that is now active.
#
# Prints the directory. Returns 1 when the state directory has no home.
xghost_generated_dir() {
	local base
	base=$(xghost_state_home) || return 1
	printf '%s\n' "$base/$XGHOST_STATE_SUBDIR/$XGHOST_GENERATED_NAME"
}
