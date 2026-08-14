# Preflight: the checkout this installation runs from, and the theme it was
# asked for.
#
# Two facts about this run decide whether it can finish, and both are knowable
# before anything changes.
#
# The 'xghost' command has to be executable. Three config steps run it and the
# post-install step links it, so a checkout that lost the execute bit — a
# download of a source archive rather than a clone, or an unpack through a file
# system that carries no mode — installs every package of the manifest first and
# then fails in the config group with a raw 'Permission denied'. The test costs
# nothing and belongs where the other refusals are.
#
# The theme name has to be one this checkout carries. The theme is rendered by
# the last config step, which runs after the prescribed configuration has been
# linked. A name with a typo in it stops the installation there, and it stops it
# in the one state this installer is written to avoid: the config directory
# holds a link to a Hyprland configuration whose 'source' lines name generated
# files that were never rendered, Hyprland reports a missing source as an error,
# and the session does not come up. The name is knowable here, so it is refused
# here.
#
# This step reads. It changes nothing, whether it passes or refuses.

if [ ! -x "$INSTALL_XGHOST" ]; then
	install_fail \
		"the xghost command is not an executable file: $INSTALL_XGHOST" \
		"run 'chmod +x $INSTALL_XGHOST', or check the repository out again with git, which carries the execute bit. Nothing was changed."
fi

if ! themes=$("$INSTALL_XGHOST" theme list); then
	install_fail \
		"'xghost theme list' could not name the themes of this checkout" \
		"read the report above. It names the directory it could not read. Fix that, then run './install.sh' again. Nothing was changed."
fi

found=no
names=
while IFS= read -r name; do
	if [ -z "$name" ]; then
		continue
	fi
	if [ "$name" = "$INSTALL_THEME" ]; then
		found=yes
	fi
	names="${names:+$names }$name"
done <<<"$themes"

if [ "$found" = no ]; then
	if [ "$INSTALL_THEME_GIVEN" = yes ]; then
		install_fail \
			"there is no theme named '$INSTALL_THEME', and '--theme' named it" \
			"run './install.sh --theme NAME' with one of these: $names. Nothing was changed, so nothing has been linked and no package has been installed."
	fi
	install_fail \
		"the theme this installation would set is not in this checkout: '$INSTALL_THEME'" \
		"check the repository out again, or name a theme this checkout carries with '--theme': $names. Nothing was changed."
fi

install_say "the xghost command is executable, and the theme '$INSTALL_THEME' is one of: $names"
