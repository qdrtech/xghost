# Post-install: prove the end state, then report it.
#
# The proof is 'xghost theme current'. It reads the name out of the build the
# stable path points at, so it answers only when the render finished and the
# generated output is in place. That is the closest this installer gets to
# proving that the terminal is themed without starting a terminal.
#
# The report then states what happens at the first login, because one fact is
# still missing at this point and the reader should not have to find that out
# from a monitor layout.

if [ "$INSTALL_DRY_RUN" = yes ]; then
	install_would "check that a theme is active, then report the end state"
	exit 0
fi

if ! theme=$("$INSTALL_XGHOST" theme current); then
	install_fail \
		"no theme is active, so the generated configuration the prescribed files include is not there" \
		"run './install.sh' again. The config group reports why the render did not finish."
fi

install_say ""
install_say "the desktop is installed:"
install_say "  the theme '$theme' is rendered, and the terminal reads its colours from it"
install_say "  the prescribed configuration is linked into your config directory"
install_say "  the machine facts are written"
install_say ""
install_say "log in to Hyprland. The session starts with the monitor layout Hyprland"
install_say "works out itself, because the monitors could not be read before a session"
install_say "existed. 'xghost machine refresh' runs at the start of that session, records"
install_say "the monitors, and renders the theme again, so the prescribed layout is in"
install_say "place from the next login."
