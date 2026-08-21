# Post-install: record every migration as applied, without running one.
#
# A migration moves a machine from a state an earlier version of this project
# left it in. A machine that is being installed today was never in one of those
# states: the checkout it just made is the current one, and the prescribed
# configuration it links is the current one. So a new user replays nothing, and
# ADR 0001 says so.
#
# This runs on a first installation and on no other. The test is the migration
# state directory. An installation that finds one has been installed before, and
# marking its pending migrations applied would take a fix away from that machine
# in silence, which is the one thing this step must never do.
#
# It runs here rather than in the config group because it records that an
# installation happened, and the installation has happened once the desktop is
# in place. A run that stopped before this step leaves the state directory
# absent, so the next run of the installer is still a first one.

. "$INSTALL_LIB_DIR/migrate.sh"

if [ "$INSTALL_DRY_RUN" = yes ]; then
	install_would "record every migration as applied, because a first installation replays none"
	exit 0
fi

if ! migrate_mark_fresh_install; then
	install_fail \
		"$MIGRATE_PROBLEM" \
		"check that the state directory can be written, then run './install.sh' again. Nothing else was changed."
fi
