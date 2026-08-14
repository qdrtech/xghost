# Config: link the prescribed configuration into the config directory.
#
# 'xghost config link --backup' is the whole step. The linker is idempotent: a
# path that already points at the prescribed entry is adopted and reported as
# already linked, so a second run creates nothing and reports no error.
#
# '--backup' is what backs existing configuration up. The linker moves a path
# that is in the way into a backup directory of its own, prints the exact path
# it moved it to, and only then creates the link. The backup is the original
# file, because the path is moved and never copied. docs/linking.md records the
# rule, and this project has one backup mechanism rather than two.
#
# This step runs before detection and before the render, because the bridge it
# creates is the path every prescribed file reaches the generated output
# through. docs/installing.md records the order.

if [ "$INSTALL_DRY_RUN" = yes ]; then
	if ! "$INSTALL_XGHOST" config link --backup --dry-run; then
		install_fail \
			"'xghost config link' reported a problem it would meet" \
			"read the report above. Nothing was changed, because this is a dry run."
	fi
	exit 0
fi

if ! "$INSTALL_XGHOST" config link --backup; then
	install_fail \
		"'xghost config link --backup' could not link the prescribed configuration" \
		"read the report above. It names every path it could not handle. Fix those, then run './install.sh' again: a path that is already linked is passed over on the second run."
fi
