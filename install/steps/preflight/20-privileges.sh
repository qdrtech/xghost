# Preflight: who is running this, and what they can raise.
#
# The installation belongs to one user. The linker links the prescribed
# configuration into that user's config directory and detection writes the
# machine facts into it, so the user who runs this is the user who gets the
# desktop.
#
# This step reads. It changes nothing.

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
	install_fail \
		"this is running as root, and an xghost desktop belongs to the user who uses it. Run as root, the prescribed configuration and the machine facts would both land in the home directory of root" \
		"run './install.sh' as your own user. The packaging step is the one step that needs root, and it raises its own privileges with sudo."
fi

if [ -z "${HOME:-}" ]; then
	install_fail \
		"HOME is not set, so the config directory and the state directory of this user have no home" \
		"run './install.sh' from a login shell of the user who will use the desktop."
fi

if ! command -v sudo >/dev/null 2>&1; then
	install_fail \
		"the 'sudo' program is not installed, and the packaging step installs packages with it" \
		"install sudo, or install the packages of install/packages/base.txt by hand and then run './install.sh' again. The packaging step reports every package as already installed and passes over."
fi

install_say "the user is $(id -un), and sudo is available for the packaging step"
