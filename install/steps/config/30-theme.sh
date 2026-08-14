# Config: render the theme.
#
# This is the step that makes the terminal themed and the Hyprland
# configuration complete. Every prescribed file that includes a generated file
# reaches it through the bridge the link step created, and Hyprland reports a
# missing include as an error rather than passing over it, so the render has to
# happen before the first session and not after it.
#
# An installation that finds a theme already active keeps that theme, so a
# second run never undoes a switch the user made. A theme named with '--theme'
# wins over the active one, because that is an instruction rather than a
# default.

theme=$INSTALL_THEME
kept=no

if [ "$INSTALL_DRY_RUN" = yes ]; then
	if [ "$INSTALL_THEME_GIVEN" = yes ]; then
		install_would "run: xghost theme set $theme"
	else
		install_would "run: xghost theme set $theme, or the theme that is already active"
	fi
	exit 0
fi

if [ "$INSTALL_THEME_GIVEN" = no ] && current=$("$INSTALL_XGHOST" theme current 2>/dev/null); then
	theme=$current
	kept=yes
fi

if [ "$kept" = yes ]; then
	install_say "the theme '$theme' is already active, and the installation renders that one"
fi

if ! "$INSTALL_XGHOST" theme set "$theme"; then
	install_fail \
		"'xghost theme set $theme' could not render the theme" \
		"read the report above. A fact reported as 'unknown' is corrected by editing the machine facts file, and 'xghost theme list' names every theme there is. Then run './install.sh' again."
fi
