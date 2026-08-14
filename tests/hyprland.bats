#!/usr/bin/env bats
#
# Tests for the Hyprland bundle: the prescribed configuration under config/hypr
# and the templates under templates/hypr.
#
# This is the first bundle whose output depends on the machine, so most of these
# tests render against machine facts written by the test rather than read from
# the computer that runs it. Nothing here asserts on the hardware of that
# computer, and nothing here needs a Hyprland session.
#
# The tests that need Hyprland itself run 'Hyprland --verify-config' and skip
# when Hyprland is not installed, so the suite passes in continuous integration.
# That option parses the configuration and prints the result. It starts no
# compositor: it opens no Wayland socket, it creates no instance, and it runs no
# 'exec' line. It is the only offline check Hyprland has, and it is the one this
# bundle proves itself with, because a running compositor cannot be restarted
# under test.
#
# The design of the bundle is recorded in docs/bundles/hyprland.md.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR="$BATS_TEST_DIRNAME/.."
	PRESCRIBED_DIR="$ROOT_DIR/config/hypr"
	TEMPLATE_DIR="$ROOT_DIR/templates/hypr"
	MONITOR_CHOICE="$TEMPLATE_DIR/monitors.conf.choice.MACHINE_MONITOR_COUNT"
	WORKSPACE_CHOICE="$TEMPLATE_DIR/workspaces.conf.choice.MACHINE_MONITOR_COUNT"

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# Every path the commands read comes from this setup, so no test touches the
	# home directory of the person who runs them, and no override that person
	# happens to export reaches a command.
	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR
	unset XGHOST_CONFIG_SOURCE
	unset XGHOST_ROOT
	unset XGHOST_THEMES_DIR
	unset XGHOST_TEMPLATE_DIR
	unset XGHOST_MACHINE_FACTS

	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	GENERATED="$XDG_STATE_HOME/xghost/generated"
	FACTS="$BATS_TEST_TMPDIR/machine.conf"

	BRIDGE_NAME=xghost-generated

	# A monitor output name, as the kernel names a connector. No file the
	# project owns may hold one.
	CONNECTOR_PATTERN='(^|[^A-Za-z0-9-])(eDP|DP|HDMI-A|HDMI-B|DVI-D|DVI-I|DVI-A|VGA|LVDS|DSI|Virtual)-[0-9]+'
}

# Write a machine facts file describing a monitor set.
#
#   write_facts COUNT NAME:MODE:POSITION:SCALE:TRANSFORM ...
#
# The facts are written by the test, so no assertion below depends on the
# displays of the computer that runs the suite.
write_facts() {
	local count=$1
	shift
	local index=1 entry
	local -a field

	{
		printf 'MACHINE_FACTS_VERSION=1\n'
		printf 'MACHINE_COMPOSITOR=hyprland\n'
		printf 'MACHINE_MONITOR_COUNT=%s\n' "$count"
		for entry in "$@"; do
			IFS=: read -r -a field <<<"$entry"
			printf 'MACHINE_MONITOR_%s_NAME=%s\n' "$index" "${field[0]}"
			printf 'MACHINE_MONITOR_%s_MODE=%s\n' "$index" "${field[1]}"
			printf 'MACHINE_MONITOR_%s_POSITION=%s\n' "$index" "${field[2]}"
			printf 'MACHINE_MONITOR_%s_SCALE=%s\n' "$index" "${field[3]}"
			printf 'MACHINE_MONITOR_%s_TRANSFORM=%s\n' "$index" "${field[4]}"
			index=$((index + 1))
		done
		if [ -n "${1:-}" ]; then
			printf 'MACHINE_PRIMARY_MONITOR=%s\n' "${1%%:*}"
		fi
	} >"$FACTS"
	export XGHOST_MACHINE_FACTS="$FACTS"
}

# The three monitor sets the tests render. Every one of them differs from the
# displays of the maintainer, which is the case criterion 6 of issue #10 names.
facts_one() {
	write_facts 1 'eDP-1:1920x1200@60.00:0x0:1.5:0'
}

facts_two() {
	write_facts 2 \
		'DP-3:3440x1440@175.00:0x0:1:0' \
		'eDP-1:1920x1200@60.00:3440x300:1.5:0'
}

facts_three() {
	write_facts 3 \
		'DP-1:2560x1440@165.00:0x0:1:0' \
		'DP-2:1920x1080@60.00:2560x0:1:3' \
		'HDMI-A-2:3840x2160@30.00:4480x0:2:0'
}

# Link the prescribed configuration of the checkout into the config directory.
link_prescribed() {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config link
}

# Print every 'monitor =' line of the generated layout.
monitor_lines() {
	grep '^monitor = ' "$GENERATED/hypr/monitors.conf"
}

# Print every 'workspace =' line of the generated assignment.
workspace_lines() {
	grep '^workspace = ' "$GENERATED/hypr/workspaces.conf"
}

# A test that needs Hyprland itself. Continuous integration has none.
#
# '--verify-config' parses the configuration and prints the result. It starts no
# compositor and it touches no running session.
require_hyprland() {
	if ! command -v Hyprland >/dev/null 2>&1; then
		skip "Hyprland is not installed"
	fi
}

# Parse the linked configuration with Hyprland and print the result.
verify_config() {
	Hyprland --verify-config 2>&1
}

# --- the shape of the bundle -------------------------------------------------

@test "the Hyprland configuration is prescribed configuration" {
	[ -d "$PRESCRIBED_DIR" ]
	[ ! -L "$PRESCRIBED_DIR" ]
	[ -f "$PRESCRIBED_DIR/hyprland.conf" ]
	[ -f "$PRESCRIBED_DIR/hypridle.conf" ]
	[ -f "$PRESCRIBED_DIR/hyprlock.conf" ]
	[ -f "$PRESCRIBED_DIR/hyprpaper.conf" ]
	[ -d "$PRESCRIBED_DIR/conf" ]
}

@test "'config link' places the Hyprland configuration as a symbolic link" {
	run link_prescribed
	[ "$status" -eq 0 ]
	[ -L "$XDG_CONFIG_HOME/hypr" ]
	[ "$(readlink "$XDG_CONFIG_HOME/hypr")" = "$PRESCRIBED_DIR" ]
	[ -f "$XDG_CONFIG_HOME/hypr/hyprland.conf" ]
}

# Criterion 2 of issue #10, and the reason this bundle consumes machine facts at
# all. The check covers the whole prescribed configuration directory, not only
# the Hyprland part of it.
@test "no monitor output name appears in any prescribed file" {
	run grep -rnE "$CONNECTOR_PATTERN" "$ROOT_DIR/config"
	[ "$status" -ne 0 ]
}

@test "no monitor output name appears in any template" {
	run grep -rnE "$CONNECTOR_PATTERN" "$ROOT_DIR/templates"
	[ "$status" -ne 0 ]
}

# The include is relative and it reaches the generated output through the bridge
# 'xghost config link' creates. Both ends therefore follow the environment. A
# path written out in full would be right only while XDG_STATE_HOME holds its
# default.
@test "the prescribed configuration includes the generated files through the bridge" {
	local include
	for include in colors monitors workspaces theme; do
		run grep -Fx "source = ../$BRIDGE_NAME/hypr/$include.conf" \
			"$PRESCRIBED_DIR/hyprland.conf"
		[ "$status" -eq 0 ]
	done

	# And no include names a home directory or a state directory in full.
	run grep -nE '^[[:space:]]*source[[:space:]]*=.*(~|\$HOME|\.local/state)' \
		"$PRESCRIBED_DIR/hyprland.conf"
	[ "$status" -ne 0 ]
}

# The dead 'xdg.sh' reference of the dotfiles, and every other reference to a
# script file that this project does not ship. A prescribed file cannot write
# its own location, so an 'exec' line names a program on the PATH.
@test "no autostart or keybinding line names a script file" {
	run grep -rnE '^[[:space:]]*(exec|exec-once|exec-shutdown)[[:space:]]*=.*\.sh' \
		"$PRESCRIBED_DIR"
	[ "$status" -ne 0 ]
	run grep -rn 'xdg.sh' "$ROOT_DIR/config"
	[ "$status" -ne 0 ]
}

# Every '$variable' a prescribed file names has to be defined by a prescribed
# file or by a generated one. The dotfiles bound two keys to '$SUPER_SHIFT',
# which no file ever defined, so neither key worked.
@test "every keybinding names a modifier variable that is defined" {
	run grep -n 'SUPER_SHIFT' "$PRESCRIBED_DIR/conf/keybinding.conf"
	[ "$status" -ne 0 ]
	run grep -Fx '$mainMod = SUPER' "$PRESCRIBED_DIR/conf/keybinding.conf"
	[ "$status" -eq 0 ]
}

@test "hyprpaper names no wallpaper file, because the backgrounds are issue #20" {
	run grep -nE '^[[:space:]]*(preload|wallpaper)' "$PRESCRIBED_DIR/hyprpaper.conf"
	[ "$status" -ne 0 ]
	run grep -n 'issue #20' "$PRESCRIBED_DIR/hyprpaper.conf"
	[ "$status" -eq 0 ]
}

# --- the monitor layout ------------------------------------------------------

@test "one monitor renders one monitor line from the machine facts" {
	facts_one
	"$XGHOST" theme set tokyonight >/dev/null

	run monitor_lines
	[ "$status" -eq 0 ]
	[ "$output" = 'monitor = eDP-1,1920x1200@60.00,0x0,1.5,transform,0' ]
}

@test "two monitors render two monitor lines from the machine facts" {
	facts_two
	"$XGHOST" theme set tokyonight >/dev/null

	run monitor_lines
	[ "$status" -eq 0 ]
	[ "$output" = 'monitor = DP-3,3440x1440@175.00,0x0,1,transform,0
monitor = eDP-1,1920x1200@60.00,3440x300,1.5,transform,0' ]
}

@test "three monitors render three monitor lines from the machine facts" {
	facts_three
	"$XGHOST" theme set tokyonight >/dev/null

	run monitor_lines
	[ "$status" -eq 0 ]
	[ "$output" = 'monitor = DP-1,2560x1440@165.00,0x0,1,transform,0
monitor = DP-2,1920x1080@60.00,2560x0,1,transform,3
monitor = HDMI-A-2,3840x2160@30.00,4480x0,2,transform,0' ]
}

# A count the project prescribes no layout for. The fallback names no output and
# leaves the arrangement to Hyprland, which is a correct desktop rather than a
# guessed one.
@test "a monitor count with no fragment falls back to the automatic layout" {
	write_facts 4 \
		'DP-1:1920x1080@60.00:0x0:1:0' \
		'DP-2:1920x1080@60.00:1920x0:1:0' \
		'DP-3:1920x1080@60.00:3840x0:1:0' \
		'DP-4:1920x1080@60.00:5760x0:1:0'
	"$XGHOST" theme set tokyonight >/dev/null

	run monitor_lines
	[ "$status" -eq 0 ]
	[ "$output" = 'monitor = ,preferred,auto,auto' ]

	# The names of the four monitors are facts, and none of them reaches the
	# output through the fallback.
	run grep -E "$CONNECTOR_PATTERN" "$GENERATED/hypr/monitors.conf"
	[ "$status" -ne 0 ]
}

# A machine detection could not read records the count as 'unknown'. The same
# fallback covers it, so a desktop still comes up.
@test "an unknown monitor count falls back to the automatic layout" {
	write_facts unknown
	"$XGHOST" theme set tokyonight >/dev/null

	run monitor_lines
	[ "$status" -eq 0 ]
	[ "$output" = 'monitor = ,preferred,auto,auto' ]
}

# --- the workspace assignment ------------------------------------------------

@test "one monitor takes all ten workspaces" {
	facts_one
	"$XGHOST" theme set tokyonight >/dev/null

	run workspace_lines
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | wc -l)" -eq 10 ]
	[ "$(printf '%s\n' "$output" | grep -c 'monitor:eDP-1')" -eq 10 ]
	[ "$(printf '%s\n' "$output" | grep -c 'default:true')" -eq 1 ]
	run grep -Fx 'workspace = 1, monitor:eDP-1, default:true' \
		"$GENERATED/hypr/workspaces.conf"
	[ "$status" -eq 0 ]
}

@test "two monitors share the ten workspaces five and five" {
	facts_two
	"$XGHOST" theme set tokyonight >/dev/null

	run workspace_lines
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | wc -l)" -eq 10 ]
	[ "$(printf '%s\n' "$output" | grep -c 'monitor:DP-3')" -eq 5 ]
	[ "$(printf '%s\n' "$output" | grep -c 'monitor:eDP-1')" -eq 5 ]

	# Each monitor opens on the first of its own workspaces.
	run grep -Fx 'workspace = 1, monitor:DP-3, default:true' \
		"$GENERATED/hypr/workspaces.conf"
	[ "$status" -eq 0 ]
	run grep -Fx 'workspace = 6, monitor:eDP-1, default:true' \
		"$GENERATED/hypr/workspaces.conf"
	[ "$status" -eq 0 ]
}

@test "three monitors share the ten workspaces four, three and three" {
	facts_three
	"$XGHOST" theme set tokyonight >/dev/null

	run workspace_lines
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | wc -l)" -eq 10 ]
	[ "$(printf '%s\n' "$output" | grep -c 'monitor:DP-1')" -eq 4 ]
	[ "$(printf '%s\n' "$output" | grep -c 'monitor:DP-2')" -eq 3 ]
	[ "$(printf '%s\n' "$output" | grep -c 'monitor:HDMI-A-2')" -eq 3 ]
	[ "$(printf '%s\n' "$output" | grep -c 'default:true')" -eq 3 ]
}

@test "a monitor count with no fragment pins no workspace" {
	write_facts unknown
	"$XGHOST" theme set tokyonight >/dev/null

	[ -f "$GENERATED/hypr/workspaces.conf" ]
	run workspace_lines
	[ "$status" -ne 0 ]
}

# --- the colours -------------------------------------------------------------

@test "every theme renders the Hyprland colours from its own palette" {
	facts_two
	local theme value count=0
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null

		value=$(sed -n 's/^ACCENT=//p' "$ROOT_DIR/themes/$theme/palette.conf")
		[ -n "$value" ]
		run grep -Fx "\$accent = rgb(${value#\#})" "$GENERATED/hypr/colors.conf"
		[ "$status" -eq 0 ]

		value=$(sed -n 's/^TEXT_MUTED=//p' "$ROOT_DIR/themes/$theme/palette.conf")
		[ -n "$value" ]
		run grep -Fx "    col.active_border = rgb(${value#\#})" \
			"$GENERATED/hypr/theme.conf"
		[ "$status" -eq 0 ]

		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

@test "no generated Hyprland file carries an unsubstituted placeholder" {
	facts_three
	local theme
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		run grep -rE '@[A-Z][A-Z0-9_]*@' "$GENERATED/hypr"
		[ "$status" -ne 0 ]
	done < <("$XGHOST" theme list)
}

# --- the structural choice ---------------------------------------------------

@test "the monitor layout is one fragment per count, and a fallback" {
	local count
	for count in 1 2 3 default; do
		[ -f "$MONITOR_CHOICE/$count" ]
		[ -f "$WORKSPACE_CHOICE/$count" ]
	done
}

# Every fragment names the facts of exactly the monitors its count has, so a
# fragment can never name a monitor the machine does not report.
@test "each monitor fragment names as many monitors as its own name" {
	local count index
	for count in 1 2 3; do
		for index in 1 2 3; do
			run grep -F "@MACHINE_MONITOR_${index}_NAME@" "$MONITOR_CHOICE/$count"
			if [ "$index" -le "$count" ]; then
				[ "$status" -eq 0 ]
			else
				[ "$status" -ne 0 ]
			fi
		done
	done
}

# The renderer is told the layout by a fact, so a machine that has never run
# detection is named rather than given a layout the project guessed at.
@test "a render without machine facts names the fact it wanted" {
	run "$XGHOST" theme set tokyonight
	[ "$status" -ne 0 ]
	[[ $output == *"MACHINE_MONITOR_COUNT"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

# --- Hyprland itself ---------------------------------------------------------

@test "Hyprland parses the configuration for one, two and three monitors" {
	require_hyprland
	run link_prescribed
	[ "$status" -eq 0 ]

	local set
	for set in facts_one facts_two facts_three; do
		"$set"
		"$XGHOST" theme set tokyonight >/dev/null
		run verify_config
		[ "$status" -eq 0 ]
		[[ $output == *"config ok"* ]]
	done
}

@test "Hyprland parses the configuration for a monitor count with no fragment" {
	require_hyprland
	run link_prescribed
	[ "$status" -eq 0 ]
	write_facts unknown
	"$XGHOST" theme set tokyonight >/dev/null

	run verify_config
	[ "$status" -eq 0 ]
	[[ $output == *"config ok"* ]]
}

# Hyprland has no optional include, so a generated file that is not there yet is
# a named error rather than a desktop with no colours. This is the behaviour the
# bundle chose, and the reason 'xghost theme set' has to run before the first
# session. docs/bundles/hyprland.md records that ordering.
@test "Hyprland names the missing include before the first theme is set" {
	require_hyprland
	run link_prescribed
	[ "$status" -eq 0 ]

	run verify_config
	[ "$status" -ne 0 ]
	[[ $output == *"source="* ]]
	[[ $output == *"hyprland.conf"* ]]
}

# The bridge is what makes the relative include resolve. Without it the include
# reaches nothing at all, which proves that the path travels through the bridge
# rather than through the checkout.
@test "Hyprland finds nothing when the bridge is missing" {
	require_hyprland
	run link_prescribed
	[ "$status" -eq 0 ]
	facts_two
	"$XGHOST" theme set tokyonight >/dev/null

	run verify_config
	[ "$status" -eq 0 ]

	rm "$XDG_CONFIG_HOME/$BRIDGE_NAME"
	run verify_config
	[ "$status" -ne 0 ]
	[[ $output == *"source="* ]]
}
