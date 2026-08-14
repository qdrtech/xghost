#!/usr/bin/env bats
#
# Tests for the Ghostty bundle: the prescribed configuration under
# config/ghostty and the colour template under templates/ghostty.
#
# The bundle is the first one that joins the linker and the renderer, so these
# tests drive both real commands against a temporary home directory and assert
# what lands on disk.
#
# No test runs Ghostty. Continuous integration has no Ghostty, and
# 'ghostty +validate-config' is run by hand on a machine that has it. The
# design of the bundle is recorded in docs/bundles/ghostty.md.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR="$BATS_TEST_DIRNAME/.."
	PRESCRIBED="$ROOT_DIR/config/ghostty/config"
	TEMPLATE="$ROOT_DIR/templates/ghostty/colors.conf"

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# Every path the commands read comes from an override, so no test touches
	# the home directory of the person who runs them.
	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR

	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	GENERATED="$XDG_STATE_HOME/xghost/generated"

	# The line the prescribed configuration carries, and the path it reaches.
	# The path is the default state directory written out in full, because
	# Ghostty expands no environment variable. docs/bundles/ghostty.md records
	# that decision.
	INCLUDE_PATH='~/.local/state/xghost/generated/ghostty/colors.conf'
	INCLUDE_LINE="config-file = ?$INCLUDE_PATH"
}

@test "the Ghostty configuration is prescribed configuration" {
	[ -f "$PRESCRIBED" ]
	[ ! -L "$ROOT_DIR/config/ghostty" ]
}

@test "'config link' places the Ghostty configuration as a symbolic link" {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" run "$XGHOST" config link
	[ "$status" -eq 0 ]
	[ -L "$XDG_CONFIG_HOME/ghostty" ]
	[ "$(readlink "$XDG_CONFIG_HOME/ghostty")" = "$ROOT_DIR/config/ghostty" ]
	[ -f "$XDG_CONFIG_HOME/ghostty/config" ]
}

@test "the prescribed configuration includes the generated colours, optionally" {
	run grep -Fx "$INCLUDE_LINE" "$PRESCRIBED"
	[ "$status" -eq 0 ]
}

# The include names one path and the renderer writes another. The two are
# compared here, so a change to either one fails a test rather than a terminal.
@test "the include reaches the file the renderer writes" {
	local resolved="$HOME/${INCLUDE_PATH#'~/'}"
	[ "$resolved" = "$GENERATED/ghostty/colors.conf" ]

	"$XGHOST" theme set tokyonight >/dev/null
	[ -f "$resolved" ]
}

@test "the prescribed configuration names a font that exists on Arch" {
	# One 'font-family' line, and it names the font the Arch package
	# 'ttf-jetbrains-mono-nerd' provides.
	run grep -E '^[[:space:]]*font-family' "$PRESCRIBED"
	[ "$status" -eq 0 ]
	[ "$output" = 'font-family = JetBrainsMono Nerd Font' ]

	# '.SF NS Mono' is the macOS system font, and no Arch machine has it. The
	# comments still name it as the font that was replaced, so the test reads
	# the settings alone: a comment line starts with a hash.
	run grep -E '^[^#]*\.SF NS Mono' "$PRESCRIBED"
	[ "$status" -ne 0 ]
}

@test "every theme renders the Ghostty colours from its own palette" {
	local theme key value count=0
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		[ -f "$GENERATED/ghostty/colors.conf" ]
		for key in BG SURFACE TEXT ACCENT ACCENT_ALT WARN ERROR SUCCESS; do
			value=$(sed -n "s/^$key=//p" "$ROOT_DIR/themes/$theme/palette.conf")
			[ -n "$value" ]
			grep -Fq "$value" "$GENERATED/ghostty/colors.conf"
		done
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

@test "the Ghostty template names only values the palettes declare" {
	local theme
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		run grep -E '@[A-Z][A-Z0-9_]*@' "$GENERATED/ghostty/colors.conf"
		[ "$status" -ne 0 ]
	done < <("$XGHOST" theme list)
}

@test "the colour template holds every one of the sixteen terminal slots" {
	local slot
	for slot in $(seq 0 15); do
		run grep -E "^palette = $slot=@[A-Z][A-Z0-9_]*@\$" "$TEMPLATE"
		[ "$status" -eq 0 ]
	done
}
