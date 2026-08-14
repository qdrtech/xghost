#!/usr/bin/env bats
#
# Unit tests for the linker, which is 'xghost config link' and
# 'xghost config unlink'.
#
# Every test runs against a temporary home directory and a prescribed
# configuration directory the test builds itself. No test depends on the
# content of config/ in the repository, because that content arrives bundle by
# bundle.
#
# Every test asserts external behaviour: what is on disk afterwards, and what
# the command printed. No test reaches into an internal function.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"

	# The linker takes every path from an override, so the tests never touch
	# the home directory of the person who runs them.
	unset XGHOST_COMMAND_DIR
	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR
	unset XDG_CONFIG_HOME
	unset XDG_STATE_HOME

	export HOME="$BATS_TEST_TMPDIR/home"
	export XGHOST_CONFIG_SOURCE="$BATS_TEST_TMPDIR/source"
	mkdir -p "$HOME" "$XGHOST_CONFIG_SOURCE"

	CONFIG_HOME="$HOME/.config"
	STATE_DIR="$HOME/.local/state/xghost"
	RECORD="$STATE_DIR/links"
	BACKUP_DIR="$STATE_DIR/backups"

	# The bridge to the generated output, and the path it reaches. The linker
	# creates it beside the prescribed entries, so a prescribed file can reach
	# the generated output by a relative path.
	BRIDGE="$CONFIG_HOME/xghost-generated"
	GENERATED="$STATE_DIR/generated"
}

# A test that takes a permission away must give it back, or the temporary
# directory of that test cannot be removed.
teardown() {
	chmod -R u+rwX "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# A permission stops every user except the one that owns the machine. A test
# that works by taking a permission away proves nothing as root.
skip_when_root() {
	if [ "$(id -u)" -eq 0 ]; then
		skip "file permissions do not stop the root user"
	fi
}

# Add one prescribed directory with one file in it.
prescribe_directory() {
	local name=$1
	mkdir -p "$XGHOST_CONFIG_SOURCE/$name"
	printf 'prescribed %s\n' "$name" >"$XGHOST_CONFIG_SOURCE/$name/settings.conf"
}

# Add one prescribed regular file.
prescribe_file() {
	local name=$1
	printf 'prescribed %s\n' "$name" >"$XGHOST_CONFIG_SOURCE/$name"
}

# Print the backup path the command reported for one destination.
reported_backup_path() {
	local destination=$1
	printf '%s\n' "$output" | sed -n "s|^backup: moved $destination to ||p" | head -n 1
}

# --- creation --------------------------------------------------------------

@test "link creates a symbolic link for every prescribed directory" {
	prescribe_directory hypr
	prescribe_directory waybar

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -L "$CONFIG_HOME/hypr" ]
	[ -L "$CONFIG_HOME/waybar" ]
	[ "$(readlink "$CONFIG_HOME/hypr")" = "$XGHOST_CONFIG_SOURCE/hypr" ]
	[ "$(readlink "$CONFIG_HOME/waybar")" = "$XGHOST_CONFIG_SOURCE/waybar" ]
}

@test "link reaches the prescribed content through the link" {
	prescribe_directory hypr

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ "$(cat "$CONFIG_HOME/hypr/settings.conf")" = "prescribed hypr" ]
}

@test "link creates the config directory when it does not exist" {
	prescribe_directory hypr
	[ ! -e "$CONFIG_HOME" ]

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -d "$CONFIG_HOME" ]
}

@test "link creates a symbolic link for a prescribed regular file" {
	prescribe_file mimeapps.list

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -L "$CONFIG_HOME/mimeapps.list" ]
	[ "$(readlink "$CONFIG_HOME/mimeapps.list")" = "$XGHOST_CONFIG_SOURCE/mimeapps.list" ]
}

@test "link reports the exact path of every link it creates" {
	prescribe_directory hypr

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[[ $output == *"linked: $CONFIG_HOME/hypr -> $XGHOST_CONFIG_SOURCE/hypr"* ]]
}

@test "link handles a prescribed name that holds a space" {
	mkdir -p "$XGHOST_CONFIG_SOURCE/two words"

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -L "$CONFIG_HOME/two words" ]
	[ "$(readlink "$CONFIG_HOME/two words")" = "$XGHOST_CONFIG_SOURCE/two words" ]
}

@test "link does not link an entry whose name starts with a dot" {
	prescribe_directory hypr
	: >"$XGHOST_CONFIG_SOURCE/.gitkeep"

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -L "$CONFIG_HOME/hypr" ]
	[ ! -e "$CONFIG_HOME/.gitkeep" ]
	[ ! -L "$CONFIG_HOME/.gitkeep" ]
}

@test "link reports that there is nothing to link when no prescribed entry exists" {
	: >"$XGHOST_CONFIG_SOURCE/.gitkeep"

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[[ $output == *"nothing to link"* ]]
	[ ! -e "$CONFIG_HOME" ]
}

@test "link reports a prescribed configuration directory that does not exist" {
	export XGHOST_CONFIG_SOURCE="$BATS_TEST_TMPDIR/absent"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"$BATS_TEST_TMPDIR/absent"* ]]
}

@test "link honours XDG_CONFIG_HOME" {
	prescribe_directory hypr
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg"

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -L "$XDG_CONFIG_HOME/hypr" ]
	[ ! -e "$CONFIG_HOME/hypr" ]
}

# --- idempotency -----------------------------------------------------------

@test "a second link run changes nothing and reports no error" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[[ $output == *"already linked: $CONFIG_HOME/hypr"* ]]
	[[ $output != *"conflict:"* ]]
	[[ $output == *"0 in conflict"* ]]
	[ "$(readlink "$CONFIG_HOME/hypr")" = "$XGHOST_CONFIG_SOURCE/hypr" ]
}

@test "a second link run does not record the same link twice" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	# One line for the prescribed entry, one for the bridge to the generated
	# output, and no line written twice.
	[ "$(wc -l <"$RECORD")" -eq 2 ]
	[ "$(sort -u "$RECORD" | wc -l)" -eq 2 ]
}

@test "a link run adds a prescribed entry that arrived later" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	prescribe_directory waybar
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -L "$CONFIG_HOME/hypr" ]
	[ -L "$CONFIG_HOME/waybar" ]
}

# --- refusal to clobber ----------------------------------------------------

@test "link never clobbers an existing regular file" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[ ! -L "$CONFIG_HOME/hypr" ]
	[ -f "$CONFIG_HOME/hypr" ]
	[ "$(cat "$CONFIG_HOME/hypr")" = "the work of the user" ]
}

@test "link never clobbers an existing directory" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME/hypr"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr/mine.conf"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[ ! -L "$CONFIG_HOME/hypr" ]
	[ -d "$CONFIG_HOME/hypr" ]
	[ "$(cat "$CONFIG_HOME/hypr/mine.conf")" = "the work of the user" ]
}

@test "link never clobbers a symbolic link that points somewhere else" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME" "$BATS_TEST_TMPDIR/elsewhere"
	ln -s "$BATS_TEST_TMPDIR/elsewhere" "$CONFIG_HOME/hypr"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[ "$(readlink "$CONFIG_HOME/hypr")" = "$BATS_TEST_TMPDIR/elsewhere" ]
	# The link is not followed either, so nothing is written inside the
	# directory that the link points at.
	[ ! -e "$BATS_TEST_TMPDIR/elsewhere/hypr" ]
}

@test "a conflict names the exact path and the regular file in the way" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"conflict: $CONFIG_HOME/hypr is a regular file"* ]]
}

@test "a conflict names the directory in the way" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME/hypr"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"conflict: $CONFIG_HOME/hypr is a directory"* ]]
}

@test "a conflict names the target of the symbolic link in the way" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME" "$BATS_TEST_TMPDIR/elsewhere"
	ln -s "$BATS_TEST_TMPDIR/elsewhere" "$CONFIG_HOME/hypr"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"conflict: $CONFIG_HOME/hypr is a symbolic link to $BATS_TEST_TMPDIR/elsewhere"* ]]
}

@test "a conflict does not stop the other prescribed entries" {
	prescribe_directory hypr
	prescribe_directory waybar
	mkdir -p "$CONFIG_HOME"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[ -L "$CONFIG_HOME/waybar" ]
	[ -f "$CONFIG_HOME/hypr" ]
}

@test "a path in conflict is not recorded, so unlink leaves it alone" {
	prescribe_directory hypr
	prescribe_directory waybar
	mkdir -p "$CONFIG_HOME"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr"
	run "$XGHOST" config link
	[ "$status" -eq 1 ]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ -f "$CONFIG_HOME/hypr" ]
	[ "$(cat "$CONFIG_HOME/hypr")" = "the work of the user" ]
}

# --- dry run ---------------------------------------------------------------

@test "a link dry run creates no link and no directory" {
	prescribe_directory hypr

	run "$XGHOST" config link --dry-run
	[ "$status" -eq 0 ]
	[[ $output == *"would link: $CONFIG_HOME/hypr -> $XGHOST_CONFIG_SOURCE/hypr"* ]]
	[ ! -e "$CONFIG_HOME" ]
	[ ! -e "$STATE_DIR" ]
}

@test "a link dry run reports the conflict it would meet and changes nothing" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr"

	run "$XGHOST" config link --dry-run
	[ "$status" -eq 1 ]
	[[ $output == *"conflict: $CONFIG_HOME/hypr is a regular file"* ]]
	[ -f "$CONFIG_HOME/hypr" ]
	[ "$(cat "$CONFIG_HOME/hypr")" = "the work of the user" ]
	[ ! -e "$RECORD" ]
}

@test "a link dry run with --backup writes no backup" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr"

	run "$XGHOST" config link --dry-run --backup
	[ "$status" -eq 0 ]
	[[ $output == *"would move $CONFIG_HOME/hypr into $BACKUP_DIR"* ]]
	[ ! -e "$BACKUP_DIR" ]
	[ ! -L "$CONFIG_HOME/hypr" ]
	[ "$(cat "$CONFIG_HOME/hypr")" = "the work of the user" ]
}

@test "an unlink dry run removes no link" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	run "$XGHOST" config unlink --dry-run
	[ "$status" -eq 0 ]
	[[ $output == *"would remove: $CONFIG_HOME/hypr"* ]]
	[ -L "$CONFIG_HOME/hypr" ]
	[ -f "$RECORD" ]
}

# --- backup ----------------------------------------------------------------

@test "--backup moves an existing regular file aside and reports its exact path" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr"

	run "$XGHOST" config link --backup
	[ "$status" -eq 0 ]

	local backup_path
	backup_path=$(reported_backup_path "$CONFIG_HOME/hypr")
	[ -n "$backup_path" ]
	[ -f "$backup_path" ]
	[ "$(cat "$backup_path")" = "the work of the user" ]
	[[ $backup_path == "$BACKUP_DIR"/* ]]
	[ -L "$CONFIG_HOME/hypr" ]
	[ "$(readlink "$CONFIG_HOME/hypr")" = "$XGHOST_CONFIG_SOURCE/hypr" ]
}

@test "--backup moves an existing directory aside with everything in it" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME/hypr/themes"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr/themes/mine.conf"

	run "$XGHOST" config link --backup
	[ "$status" -eq 0 ]

	local backup_path
	backup_path=$(reported_backup_path "$CONFIG_HOME/hypr")
	[ -d "$backup_path" ]
	[ "$(cat "$backup_path/themes/mine.conf")" = "the work of the user" ]
	[ -L "$CONFIG_HOME/hypr" ]
}

@test "--backup reports the backup path before it creates the link" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr"

	run "$XGHOST" config link --backup
	[ "$status" -eq 0 ]
	[[ $output == *"backup: moved $CONFIG_HOME/hypr to "*"linked: $CONFIG_HOME/hypr"* ]]
}

@test "--backup leaves a path alone when nothing is in the way" {
	prescribe_directory hypr

	run "$XGHOST" config link --backup
	[ "$status" -eq 0 ]
	[ ! -e "$BACKUP_DIR" ]
	[ -L "$CONFIG_HOME/hypr" ]
}

# --- unlink ----------------------------------------------------------------

@test "unlink removes the links it created" {
	prescribe_directory hypr
	prescribe_directory waybar
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ ! -L "$CONFIG_HOME/hypr" ]
	[ ! -e "$CONFIG_HOME/hypr" ]
	[ ! -L "$CONFIG_HOME/waybar" ]
	[[ $output == *"removed: $CONFIG_HOME/hypr"* ]]
}

@test "unlink leaves the prescribed configuration in place" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ "$(cat "$XGHOST_CONFIG_SOURCE/hypr/settings.conf")" = "prescribed hypr" ]
}

@test "unlink leaves a file that xghost did not create alone" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	printf 'the work of the user\n' >"$CONFIG_HOME/notes.txt"

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ -f "$CONFIG_HOME/notes.txt" ]
	[ "$(cat "$CONFIG_HOME/notes.txt")" = "the work of the user" ]
}

@test "unlink leaves a symbolic link the user made to the same prescribed entry alone" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	ln -s "$XGHOST_CONFIG_SOURCE/hypr" "$CONFIG_HOME/hypr"

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[[ $output == *"nothing to remove"* ]]
	[ -L "$CONFIG_HOME/hypr" ]
	[ "$(readlink "$CONFIG_HOME/hypr")" = "$XGHOST_CONFIG_SOURCE/hypr" ]
}

@test "unlink leaves a recorded path alone when the link now points somewhere else" {
	prescribe_directory hypr
	prescribe_directory waybar
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	rm "$CONFIG_HOME/hypr"
	mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
	ln -s "$BATS_TEST_TMPDIR/elsewhere" "$CONFIG_HOME/hypr"

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[[ $output == *"left alone: $CONFIG_HOME/hypr"* ]]
	[ "$(readlink "$CONFIG_HOME/hypr")" = "$BATS_TEST_TMPDIR/elsewhere" ]
	[ ! -e "$CONFIG_HOME/waybar" ]
}

@test "unlink leaves a recorded path alone when a regular file has taken its place" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	rm "$CONFIG_HOME/hypr"
	printf 'the work of the user\n' >"$CONFIG_HOME/hypr"

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[[ $output == *"left alone: $CONFIG_HOME/hypr is a regular file"* ]]
	[ "$(cat "$CONFIG_HOME/hypr")" = "the work of the user" ]
}

@test "unlink removes a link whose prescribed entry no longer exists" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	rm -r "$XGHOST_CONFIG_SOURCE/hypr"

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ ! -L "$CONFIG_HOME/hypr" ]
}

@test "unlink reports that there is nothing to remove when no link was created" {
	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[[ $output == *"nothing to remove"* ]]
}

@test "a second unlink run reports no error" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[[ $output != *"cannot"* ]]
}

@test "link after unlink creates the links again" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -L "$CONFIG_HOME/hypr" ]
}

# --- the bridge to the generated output --------------------------------------
#
# A prescribed file cannot name the state directory in full: the components
# this project prescribes expand no environment variable, so such a path is
# wrong the moment XDG_STATE_HOME is not the default, and the include then
# misses in silence. The bridge gives the generated output one fixed name
# inside the config directory, and a prescribed file reaches it by a relative
# path. See docs/linking.md.

@test "link creates the bridge to the generated output" {
	prescribe_directory ghostty

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -L "$BRIDGE" ]
	[ "$(readlink "$BRIDGE")" = "$GENERATED" ]
	[[ $output == *"linked: $BRIDGE -> $GENERATED"* ]]
}

@test "the bridge is created before the generated output exists" {
	prescribe_directory ghostty
	[ ! -e "$GENERATED" ]

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	# 'xghost theme set' has not run yet, so the bridge points at a path that
	# is not there. The include of a prescribed file is optional for exactly
	# this moment, and the link is right the moment the path appears.
	[ -L "$BRIDGE" ]
	[ ! -e "$BRIDGE" ]
	[ "$(readlink "$BRIDGE")" = "$GENERATED" ]
}

@test "the bridge follows XDG_STATE_HOME" {
	prescribe_directory ghostty
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ "$(readlink "$BRIDGE")" = "$XDG_STATE_HOME/xghost/generated" ]
}

@test "the bridge is recorded, so unlink removes it" {
	prescribe_directory ghostty
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	# The record holds one line per link: the link path, a tab, then the path
	# it points at.
	run grep -Fx "$(printf '%s\t%s' "$BRIDGE" "$GENERATED")" "$RECORD"
	[ "$status" -eq 0 ]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[[ $output == *"removed: $BRIDGE"* ]]
	[ ! -L "$BRIDGE" ]
	[ ! -e "$BRIDGE" ]
}

@test "unlink leaves the generated output in place" {
	prescribe_directory ghostty
	mkdir -p "$GENERATED/ghostty"
	printf 'generated\n' >"$GENERATED/ghostty/colors.conf"
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	# Removing a symbolic link never touches what it points at.
	[ "$(cat "$GENERATED/ghostty/colors.conf")" = generated ]
}

@test "link never clobbers a path that is already at the bridge name" {
	prescribe_directory ghostty
	mkdir -p "$BRIDGE"
	printf 'the work of the user\n' >"$BRIDGE/mine.conf"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"conflict: $BRIDGE is a directory"* ]]
	[ ! -L "$BRIDGE" ]
	[ "$(cat "$BRIDGE/mine.conf")" = "the work of the user" ]

	# The path is in conflict, so it was never recorded, and 'unlink' leaves
	# it exactly where it is.
	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ "$(cat "$BRIDGE/mine.conf")" = "the work of the user" ]
}

@test "unlink leaves a bridge the user made by hand alone" {
	prescribe_directory ghostty
	mkdir -p "$CONFIG_HOME"
	ln -s "$GENERATED" "$BRIDGE"

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[[ $output == *"nothing to remove"* ]]
	[ -L "$BRIDGE" ]
	[ "$(readlink "$BRIDGE")" = "$GENERATED" ]
}

@test "a link dry run creates no bridge" {
	prescribe_directory ghostty

	run "$XGHOST" config link --dry-run
	[ "$status" -eq 0 ]
	[[ $output == *"would link: $BRIDGE -> $GENERATED"* ]]
	[ ! -e "$BRIDGE" ]
	[ ! -L "$BRIDGE" ]
}

@test "no prescribed configuration means no bridge" {
	: >"$XGHOST_CONFIG_SOURCE/.gitkeep"

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[[ $output == *"nothing to link"* ]]
	# Nothing includes the generated output when nothing is prescribed.
	[ ! -e "$CONFIG_HOME" ]
}

# --- options ---------------------------------------------------------------

@test "link reports an unknown option and changes nothing" {
	prescribe_directory hypr

	run "$XGHOST" config link --nosuchoption
	[ "$status" -eq 2 ]
	[[ $output == *"unknown option '--nosuchoption'"* ]]
	[ ! -e "$CONFIG_HOME" ]
}

@test "unlink reports an unknown option and changes nothing" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	run "$XGHOST" config unlink --nosuchoption
	[ "$status" -eq 2 ]
	[[ $output == *"unknown option '--nosuchoption'"* ]]
	[ -L "$CONFIG_HOME/hypr" ]
}

@test "a path override that is not absolute is reported" {
	prescribe_directory hypr
	export XGHOST_CONFIG_HOME=relative/path

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"is not absolute"* ]]
}

@test "a path override that holds a control character is reported" {
	prescribe_directory hypr
	export XGHOST_CONFIG_HOME="$BATS_TEST_TMPDIR/two"$'\n'"lines"
	mkdir -p "$XGHOST_CONFIG_HOME"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"holds a control character"* ]]
	# One record line would become two, and 'unlink' would then act on a path
	# that xghost never wrote.
	[ ! -e "$RECORD" ]
	[ ! -L "$XGHOST_CONFIG_HOME/hypr" ]
}

@test "a state directory path that holds a control character is reported" {
	prescribe_directory hypr
	export XGHOST_STATE_DIR="$BATS_TEST_TMPDIR/state"$'\n'"two"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"holds a control character"* ]]
	[ ! -L "$CONFIG_HOME/hypr" ]
}

# --- the destination and the prescribed entry are one file ------------------

@test "link refuses when the config directory is the prescribed configuration directory" {
	prescribe_directory nvim
	export XGHOST_CONFIG_HOME="$XGHOST_CONFIG_SOURCE"

	run "$XGHOST" config link --backup
	[ "$status" -eq 1 ]
	[[ $output == *"are the same directory"* ]]
	# The prescribed configuration is still where it belongs.
	[ -d "$XGHOST_CONFIG_SOURCE/nvim" ]
	[ "$(cat "$XGHOST_CONFIG_SOURCE/nvim/settings.conf")" = "prescribed nvim" ]
	[ ! -e "$BACKUP_DIR" ]
}

@test "link refuses when the config directory reaches the prescribed configuration directory through a symbolic link" {
	prescribe_directory nvim
	# The user already points the config directory at the checkout.
	ln -s "$XGHOST_CONFIG_SOURCE" "$CONFIG_HOME"

	run "$XGHOST" config link --backup
	[ "$status" -eq 1 ]
	[[ $output == *"are the same directory"* ]]
	[ -d "$XGHOST_CONFIG_SOURCE/nvim" ]
	[ "$(cat "$XGHOST_CONFIG_SOURCE/nvim/settings.conf")" = "prescribed nvim" ]
	[ ! -e "$BACKUP_DIR" ]
}

@test "unlink refuses when the config directory is the prescribed configuration directory" {
	prescribe_directory nvim
	export XGHOST_CONFIG_HOME="$XGHOST_CONFIG_SOURCE"

	run "$XGHOST" config unlink
	[ "$status" -eq 1 ]
	[[ $output == *"are the same directory"* ]]
	[ -d "$XGHOST_CONFIG_SOURCE/nvim" ]
}

@test "link reports a destination that is the same file as its prescribed entry" {
	# The prescribed entry points back at the path it would be linked to.
	mkdir -p "$CONFIG_HOME/nvim"
	printf 'the work of the user\n' >"$CONFIG_HOME/nvim/init.lua"
	ln -s "$CONFIG_HOME/nvim" "$XGHOST_CONFIG_SOURCE/nvim"

	run "$XGHOST" config link --backup
	[ "$status" -eq 1 ]
	[[ $output == *"are the same file"* ]]
	# Nothing was moved aside, and no link points at itself.
	[ ! -e "$BACKUP_DIR" ]
	[ ! -L "$CONFIG_HOME/nvim" ]
	[ "$(cat "$CONFIG_HOME/nvim/init.lua")" = "the work of the user" ]
}

@test "link reports a destination that is a hard link to its prescribed entry" {
	prescribe_file mimeapps.list
	mkdir -p "$CONFIG_HOME"
	ln "$XGHOST_CONFIG_SOURCE/mimeapps.list" "$CONFIG_HOME/mimeapps.list"

	run "$XGHOST" config link --backup
	[ "$status" -eq 1 ]
	[[ $output == *"are the same file"* ]]
	[ ! -e "$BACKUP_DIR" ]
	[ "$(cat "$XGHOST_CONFIG_SOURCE/mimeapps.list")" = "prescribed mimeapps.list" ]
}

# --- the link record ---------------------------------------------------------

@test "link refuses when the link record path is a directory" {
	prescribe_directory hypr
	mkdir -p "$RECORD"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"must be a regular file"* ]]
	# A link that cannot be recorded is a link 'unlink' cannot remove, so no
	# link is created at all.
	[ ! -L "$CONFIG_HOME/hypr" ]
	[ -z "$(ls -A "$RECORD")" ]
}

@test "unlink refuses when the link record path is a directory" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	ln -s "$XGHOST_CONFIG_SOURCE/hypr" "$CONFIG_HOME/hypr"
	mkdir -p "$RECORD"

	run "$XGHOST" config unlink
	[ "$status" -eq 1 ]
	[[ $output == *"must be a regular file"* ]]
	# To report that there is nothing to remove would be a false report.
	[[ $output != *"nothing to remove"* ]]
}

@test "link creates no link when the state directory cannot be written" {
	skip_when_root
	prescribe_directory hypr
	mkdir -p "$STATE_DIR"
	chmod 500 "$STATE_DIR"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"cannot write in the state directory"* ]]
	# The module knows it can undo the change before it makes it.
	[ ! -L "$CONFIG_HOME/hypr" ]
	[ ! -e "$CONFIG_HOME/hypr" ]
}

@test "link creates no link when the link record cannot be read" {
	skip_when_root
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	prescribe_directory waybar
	chmod 000 "$RECORD"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"cannot read the link record"* ]]
	[[ $output != *"Permission denied"* ]]
	[ ! -L "$CONFIG_HOME/waybar" ]
}

@test "unlink reports a link record it cannot read and removes nothing" {
	skip_when_root
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	chmod 000 "$RECORD"

	run "$XGHOST" config unlink
	[ "$status" -eq 1 ]
	# The failure is reported in the words of the module, not as a line
	# number of a shell script.
	[[ $output == *"xghost: cannot read the link record $RECORD"* ]]
	[[ $output != *"Permission denied"* ]]
	[ -L "$CONFIG_HOME/hypr" ]
}

# --- one run at a time -------------------------------------------------------

@test "two link runs at one moment record every link they create" {
	local one="$BATS_TEST_TMPDIR/source-one"
	local two="$BATS_TEST_TMPDIR/source-two"
	mkdir -p "$one/alpha" "$one/beta" "$two/gamma" "$two/delta"

	(
		while [ ! -e "$BATS_TEST_TMPDIR/go" ]; do :; done
		XGHOST_CONFIG_SOURCE="$one" "$XGHOST" config link
	) >/dev/null 2>&1 &
	local first=$!
	(
		while [ ! -e "$BATS_TEST_TMPDIR/go" ]; do :; done
		XGHOST_CONFIG_SOURCE="$two" "$XGHOST" config link
	) >/dev/null 2>&1 &
	local second=$!

	: >"$BATS_TEST_TMPDIR/go"
	wait "$first"
	wait "$second"

	# An unrecorded link is an orphan that 'unlink' never removes, so the
	# record holds one line for every link on disk: the four prescribed
	# entries, and the one bridge the two runs share.
	[ "$(find "$CONFIG_HOME" -maxdepth 1 -type l | wc -l)" -eq 5 ]
	[ "$(wc -l <"$RECORD")" -eq 5 ]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ "$(find "$CONFIG_HOME" -maxdepth 1 -type l | wc -l)" -eq 0 ]
}

@test "two backup runs at one moment keep both files" {
	prescribe_directory hypr
	local shared="$BATS_TEST_TMPDIR/backups"
	mkdir -p "$shared" "$BATS_TEST_TMPDIR/one/.config" "$BATS_TEST_TMPDIR/two/.config"
	printf 'the work of one\n' >"$BATS_TEST_TMPDIR/one/.config/hypr"
	printf 'the work of two\n' >"$BATS_TEST_TMPDIR/two/.config/hypr"

	(
		while [ ! -e "$BATS_TEST_TMPDIR/go" ]; do :; done
		XGHOST_CONFIG_HOME="$BATS_TEST_TMPDIR/one/.config" \
			XGHOST_STATE_DIR="$BATS_TEST_TMPDIR/one/state" \
			XGHOST_BACKUP_DIR="$shared" \
			"$XGHOST" config link --backup
	) >/dev/null 2>&1 &
	local first=$!
	(
		while [ ! -e "$BATS_TEST_TMPDIR/go" ]; do :; done
		XGHOST_CONFIG_HOME="$BATS_TEST_TMPDIR/two/.config" \
			XGHOST_STATE_DIR="$BATS_TEST_TMPDIR/two/state" \
			XGHOST_BACKUP_DIR="$shared" \
			"$XGHOST" config link --backup
	) >/dev/null 2>&1 &
	local second=$!

	: >"$BATS_TEST_TMPDIR/go"
	wait "$first"
	wait "$second"

	# Both runs back up a path called 'hypr'. Neither file may land on the
	# other one.
	run grep -rlx 'the work of one' "$shared"
	[ "$status" -eq 0 ]
	run grep -rlx 'the work of two' "$shared"
	[ "$status" -eq 0 ]
	[ "$(find "$shared" -type f | wc -l)" -eq 2 ]
}

# --- one backup directory for one run ----------------------------------------

@test "one link run puts every backup in one directory" {
	prescribe_directory hypr
	prescribe_directory waybar
	mkdir -p "$CONFIG_HOME"
	printf 'the hypr of the user\n' >"$CONFIG_HOME/hypr"
	printf 'the waybar of the user\n' >"$CONFIG_HOME/waybar"

	run "$XGHOST" config link --backup
	[ "$status" -eq 0 ]
	[ "$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
	[ "$(find "$BACKUP_DIR" -type f | wc -l)" -eq 2 ]
}

@test "two link runs in the same second use two backup directories" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	printf 'the first file\n' >"$CONFIG_HOME/hypr"
	run "$XGHOST" config link --backup
	[ "$status" -eq 0 ]
	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]

	printf 'the second file\n' >"$CONFIG_HOME/hypr"
	run "$XGHOST" config link --backup
	[ "$status" -eq 0 ]

	[ "$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 2 ]
	run grep -rlx 'the first file' "$BACKUP_DIR"
	[ "$status" -eq 0 ]
	run grep -rlx 'the second file' "$BACKUP_DIR"
	[ "$status" -eq 0 ]
}

@test "--backup writes out the target of a relative symbolic link in full" {
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME" "$HOME/dots/hypr"
	printf 'the work of the user\n' >"$HOME/dots/hypr/mine.conf"
	ln -s ../dots/hypr "$CONFIG_HOME/hypr"

	run "$XGHOST" config link --backup
	[ "$status" -eq 0 ]

	local backup_path
	backup_path=$(reported_backup_path "$CONFIG_HOME/hypr")
	[ -L "$backup_path" ]
	# The backup reaches the file the original link reached.
	[ "$(cat "$backup_path/mine.conf")" = "the work of the user" ]
}

# --- a link that cannot be created -------------------------------------------

@test "a link that cannot be created is counted apart from a conflict" {
	skip_when_root
	prescribe_directory hypr
	mkdir -p "$CONFIG_HOME"
	chmod 500 "$CONFIG_HOME"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"cannot create the symbolic link $CONFIG_HOME/hypr"* ]]
	[[ $output == *"0 in conflict"* ]]
	# The prescribed entry and the bridge both fail on the same permission,
	# and neither one is a conflict with something the user put in the way.
	[[ $output == *"2 failed"* ]]
}

@test "a skipped entry is named in the message" {
	mkdir -p "$XGHOST_CONFIG_SOURCE/$(printf 'alpha\tone')"
	mkdir -p "$XGHOST_CONFIG_SOURCE/$(printf 'beta\ttwo')"

	run "$XGHOST" config link
	[ "$status" -eq 1 ]
	[[ $output == *"skipped: the name \$'alpha\tone'"* ]]
	[[ $output == *"skipped: the name \$'beta\ttwo'"* ]]
}

# --- one file, two names -----------------------------------------------------

@test "a trailing slash on the prescribed configuration directory writes one link text" {
	prescribe_directory hypr
	export XGHOST_CONFIG_SOURCE="$BATS_TEST_TMPDIR/source/"

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ "$(readlink "$CONFIG_HOME/hypr")" = "$BATS_TEST_TMPDIR/source/hypr" ]

	export XGHOST_CONFIG_SOURCE="$BATS_TEST_TMPDIR/source"
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[[ $output == *"already linked: $CONFIG_HOME/hypr"* ]]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ ! -L "$CONFIG_HOME/hypr" ]
}

@test "an install location reached through a symbolic link leaves no orphan" {
	mkdir -p "$BATS_TEST_TMPDIR/real/hypr"
	ln -s "$BATS_TEST_TMPDIR/real" "$BATS_TEST_TMPDIR/reached"
	export XGHOST_CONFIG_SOURCE="$BATS_TEST_TMPDIR/reached"

	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ "$(readlink "$CONFIG_HOME/hypr")" = "$BATS_TEST_TMPDIR/reached/hypr" ]

	# The same install location, reached by its own name this time.
	export XGHOST_CONFIG_SOURCE="$BATS_TEST_TMPDIR/real"
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[[ $output == *"already linked: $CONFIG_HOME/hypr"* ]]

	run "$XGHOST" config unlink
	[ "$status" -eq 0 ]
	[ ! -L "$CONFIG_HOME/hypr" ]
}
