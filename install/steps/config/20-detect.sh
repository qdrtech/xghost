# Config: read this computer and write the machine facts.
#
# The render needs the machine facts, because the Hyprland monitor layout and
# the workspace assignment are both chosen by MACHINE_MONITOR_COUNT. A render
# with no facts file at all fails by name on that value, so this step runs
# before the theme step.
#
# One fact a first installation cannot read: hyprctl answers only inside a
# running Hyprland session, and there is no session during an installation. A
# first run therefore records MACHINE_MONITOR_COUNT=unknown, and the monitor
# layout the theme step renders is the 'default' fragment of the bundle, which
# lets Hyprland lay the displays out itself. Detection names every source it
# could not read on standard error, so the reader sees that here rather than
# guessing at it later.
#
# The monitors are read at the first login instead, by 'xghost machine refresh'
# in the autostart of the session. Running detection twice is safe, and
# docs/machine-facts.md and docs/installing.md both record why the order is this
# one.
#
# A later run of this step is run from a terminal as often as not, and hyprctl
# does not answer there either. It does not put the monitors back to 'unknown'
# all the same: detection keeps the value of the previous run for a fact whose
# source did not answer, so an installation that is run again on a machine that
# has been read keeps the layout it was reading. lib/detect.sh holds that rule.
#
# Detection needs no root, it changes no system setting, and it writes the same
# file when it reads the same machine, so this step is idempotent.

if [ "$INSTALL_DRY_RUN" = yes ]; then
	install_would "run: xghost machine detect"
	install_would "record MACHINE_MONITOR_COUNT=unknown, because no Hyprland session is running yet, unless a previous detection read the monitors"
	exit 0
fi

if ! "$INSTALL_XGHOST" machine detect; then
	install_fail \
		"'xghost machine detect' could not write the machine facts" \
		"read the report above. It names the file it could not write. Fix that, then run './install.sh' again."
fi
