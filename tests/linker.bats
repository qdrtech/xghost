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
	[[ $output != *"conflict"* ]]
	[ "$(readlink "$CONFIG_HOME/hypr")" = "$XGHOST_CONFIG_SOURCE/hypr" ]
}

@test "a second link run does not record the same link twice" {
	prescribe_directory hypr
	run "$XGHOST" config link
	[ "$status" -eq 0 ]
	run "$XGHOST" config link
	[ "$status" -eq 0 ]

	[ "$(wc -l <"$RECORD")" -eq 1 ]
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
