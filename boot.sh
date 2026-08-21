#!/bin/sh
#
# xghost — the one command that installs the desktop.
#
# This script does three things and nothing else. It installs git when git is
# missing, it clones this repository to the install location, and it hands off
# to the installer inside that clone:
#
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/qdrtech/xghost/main/boot.sh)"
#
# Every choice about the desktop is made on the other side of the hand-off, by
# install.sh and the steps under install/steps/, where each one is grouped,
# idempotent and tested. docs/installing.md records them. Nothing belongs here
# that could belong there.
#
# Read it before you run it. Being this short is the point:
#
#   curl -fsSLO https://raw.githubusercontent.com/qdrtech/xghost/main/boot.sh
#   less boot.sh
#   sh boot.sh
#
# This is POSIX shell rather than bash, because it runs on a machine before
# anything has been installed onto it. It uses nothing beyond what any /bin/sh
# provides, so the command above is right whichever shell reads it.
#
# Environment:
#   XGHOST_REPO         The repository to clone. The tests use this.
#   XGHOST_INSTALL_DIR  The install location. The tests use this.

set -eu

say() {
	printf '%s\n' "$*"
}

# Stop with a report. The first argument is the problem, the second is what the
# reader does about it. The installer stops the same way and for the same
# reason: a script that stops without saying what to do next leaves the reader
# with a half-installed machine and no move.
fail() {
	printf 'xghost: %s\n' "$1" >&2
	printf 'xghost: what to do: %s\n' "$2" >&2
	exit 1
}

# The install location is under the home directory of the user who runs this,
# so an unset HOME has to be named here. Under 'set -u' it would otherwise
# reach the reader as a diagnostic from the shell itself.
[ -n "${HOME:-}" ] ||
	fail "HOME is not set, so the install location has no home directory to sit in" \
		"run this from a login shell of the user who will use the desktop."

XGHOST_REPO=${XGHOST_REPO:-https://github.com/qdrtech/xghost.git}
XGHOST_INSTALL_DIR=${XGHOST_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/xghost}

# git, when this machine has none. It is the one package this script installs
# and the one command it runs as root. Every other package is installed by the
# packaging steps, from the manifests under install/packages/.
if ! command -v git >/dev/null 2>&1; then
	command -v pacman >/dev/null 2>&1 ||
		fail "git is not installed, and this machine has no 'pacman' to install it with" \
			"install xghost on Arch Linux. Nothing was changed."
	command -v sudo >/dev/null 2>&1 ||
		fail "git is not installed, and installing a package needs 'sudo'" \
			"install sudo, or install git by hand, then run this again. Nothing was changed."

	say ""
	say "the next command needs root, and it is the only one this script runs as root:"
	say "  sudo pacman -S --needed -- git"
	say "sudo asks for your password now, unless it has one from this terminal already."
	say ""

	sudo pacman -S --needed -- git ||
		fail "pacman could not install git" \
			"read the pacman report above, fix what it names, then run this again."
fi

# The clone. An install location that already holds a checkout is left exactly
# as it is: this script never pulls, resets or removes anything, and the steps
# of the installer are idempotent, so running this again on an installed
# machine is safe without the script being clever about it.
if [ -e "$XGHOST_INSTALL_DIR/install.sh" ]; then
	say "xghost is already cloned to $XGHOST_INSTALL_DIR, and this changed nothing there."
	say "to update that checkout first: git -C $XGHOST_INSTALL_DIR pull"
else
	say "cloning $XGHOST_REPO into $XGHOST_INSTALL_DIR"
	git clone -- "$XGHOST_REPO" "$XGHOST_INSTALL_DIR" ||
		fail "the clone into $XGHOST_INSTALL_DIR failed" \
			"read the git report above. A run that was killed part way through can leave that path holding an incomplete clone, so look at it and move it aside before you run this again. This script removes nothing itself."
fi

[ -x "$XGHOST_INSTALL_DIR/install.sh" ] ||
	fail "$XGHOST_INSTALL_DIR holds no install.sh this can run, so there is nothing to hand off to" \
		"look at that path and move it aside, then run this again."

# The hand-off. Everything the desktop is made of happens after this line, and
# none of it happens here.
say "handing off to $XGHOST_INSTALL_DIR/install.sh"
exec "$XGHOST_INSTALL_DIR/install.sh" "$@"
