# Post-install: prove the end state, then report it.
#
# The proof is 'xghost theme current'. It reads the name out of the build the
# stable path points at, so it answers only when the render finished and the
# generated output is in place. That is the closest this installer gets to
# proving that the terminal is themed without starting a terminal.
#
# The report then states what happens at the first login, and it states it only
# when it is true. The Hyprland autostart runs 'xghost machine refresh' by name,
# so that line works only if the command runs by name. Arch does not put
# ~/.local/bin on the PATH of a login shell: /etc/profile does not name it, and
# nothing this installer does changes the PATH of a shell it is not running in.
# A run that cannot reach the command therefore reports the PATH edit as the one
# step the reader still has to make, rather than promising a refresh that fails
# at every login.

if [ "$INSTALL_DRY_RUN" = yes ]; then
	install_would "check that a theme is active, then report the end state"
	exit 0
fi

if ! theme=$("$INSTALL_XGHOST" theme current); then
	install_fail \
		"no theme is active, so the generated configuration the prescribed files include is not there" \
		"run './install.sh' again. The config group reports why the render did not finish."
fi

# The PATH of this shell is the PATH of the shell the user ran the installer
# from, which is the closest this step can get to the PATH of the session. The
# command has to be the one this installation linked: another program of the
# same name on the PATH is not this installation, and the autostart would run
# that one.
bin_dir=${XGHOST_BIN_DIR:-$HOME/.local/bin}
link=$bin_dir/$XGHOST_INSTALL_PROGRAM
resolved=$(command -v "$XGHOST_INSTALL_PROGRAM" 2>/dev/null || true)

reachable=no
if [ -n "$resolved" ] &&
	[ "$(readlink -f "$resolved" || true)" = "$(readlink -f "$INSTALL_XGHOST" || true)" ]; then
	reachable=yes
fi

install_say ""
install_say "the desktop is installed:"
install_say "  the theme '$theme' is rendered, and the terminal reads its colours from it"
install_say "  the prescribed configuration is linked into your config directory"
install_say "  the machine facts are written"
install_say ""

if [ "$reachable" = yes ]; then
	install_say "log in to Hyprland. The session starts with the monitor layout Hyprland"
	install_say "works out itself, because the monitors could not be read before a session"
	install_say "existed. 'xghost machine refresh' runs at the start of that session, records"
	install_say "the monitors, and renders the theme again, so the prescribed layout is in"
	install_say "place from the next login."
	exit 0
fi

install_warn "one step is left, and it is yours to make: '$XGHOST_INSTALL_PROGRAM' does not run by name on this PATH"
if [ -n "$resolved" ]; then
	install_warn "the '$XGHOST_INSTALL_PROGRAM' this PATH finds is $resolved, and this installation linked $link"
fi
install_warn "what to do: put $bin_dir on the PATH of your login shell, then log out and log in again. Add this line to the file your login shell reads, such as ~/.bash_profile or ~/.zprofile:"
install_warn "    export PATH=\"$bin_dir:\$PATH\""
install_warn "why it matters: the Hyprland autostart runs 'xghost machine refresh' by name. Until the command runs by name, that line fails at every login, the monitors are never read, and the session keeps the layout Hyprland works out itself. Everything else above is already in place."
