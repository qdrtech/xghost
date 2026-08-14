#!/usr/bin/env bats
#
# Tests for the theme commands and the renderer behind them.
#
# Every test runs the real command and asserts external behaviour: what lands on
# disk, what is printed, and which exit status is returned. No test reaches into
# an internal function.
#
# The golden-file comparison of every theme against every template lives in
# tests/golden.bats.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR=$(cd -P "$BATS_TEST_DIRNAME/.." && pwd)

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# The renderer writes under the state directory of the user, so each test
	# gets a home of its own and touches nothing outside it.
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_STATE_HOME"

	STATE_DIR="$XDG_STATE_HOME/xghost"
	GENERATED="$STATE_DIR/generated"
	BUILDS="$STATE_DIR/builds"
}

# Point the commands at a theme directory and a template directory of this test,
# so a test may describe the exact inputs it needs.
use_own_inputs() {
	export XGHOST_THEMES_DIR="$BATS_TEST_TMPDIR/themes"
	export XGHOST_TEMPLATE_DIR="$BATS_TEST_TMPDIR/templates"
	mkdir -p "$XGHOST_THEMES_DIR" "$XGHOST_TEMPLATE_DIR"
}

# Write one file from standard input, and create the directory that holds it.
# A relative path without a separator lands in the base directory itself.
make_file() {
	local base=$1 relative=$2
	local dir=$base
	if [[ $relative == */* ]]; then
		dir=$base/${relative%/*}
	fi
	mkdir -p "$dir"
	cat >"$base/$relative"
}

# Write the palette of one theme from standard input.
make_theme() {
	local name=$1
	make_file "$XGHOST_THEMES_DIR/$name" palette.conf
}

# Write one hand-written file of one theme from standard input.
make_theme_file() {
	local name=$1 relative=$2
	make_file "$XGHOST_THEMES_DIR/$name/files" "$relative"
}

# Write one template from standard input.
make_template() {
	local relative=$1
	make_file "$XGHOST_TEMPLATE_DIR" "$relative"
}

# A palette that carries one colour of each digit case.
plain_palette() {
	cat <<-'EOF'
		BG=#1a2b3c
		ACCENT=#0A84FF
		FONT=Inter
	EOF
}

# The number of entries in the build directory.
build_count() {
	find "$BUILDS" -mindepth 1 -maxdepth 1 | wc -l
}

# --- listing ----------------------------------------------------------------

@test "theme list names every shipped theme, one per line, sorted" {
	run "$XGHOST" theme list
	[ "$status" -eq 0 ]
	[ "$output" = "macos-dark
tokyonight" ]
}

@test "theme list leaves out a directory that ships no palette" {
	use_own_inputs
	plain_palette | make_theme sound
	mkdir -p "$XGHOST_THEMES_DIR/unsound"
	run "$XGHOST" theme list
	[ "$status" -eq 0 ]
	[ "$output" = "sound" ]
}

@test "theme list reports a theme directory that holds no theme" {
	use_own_inputs
	run "$XGHOST" theme list
	[ "$status" -eq 1 ]
	[[ $output == *"no theme is installed in"* ]]
}

@test "theme list takes no argument" {
	run "$XGHOST" theme list extra
	[ "$status" -eq 2 ]
	[[ $output == *"takes no argument"* ]]
}

# --- the active theme -------------------------------------------------------

@test "theme current reports that no theme is active before the first switch" {
	run "$XGHOST" theme current
	[ "$status" -eq 1 ]
	[[ $output == *"no theme is active"* ]]
}

@test "theme current reports the theme that theme set applied" {
	run "$XGHOST" theme set tokyonight
	[ "$status" -eq 0 ]
	run "$XGHOST" theme current
	[ "$status" -eq 0 ]
	[ "$output" = "tokyonight" ]
}

@test "theme current follows a second switch" {
	"$XGHOST" theme set tokyonight
	"$XGHOST" theme set macos-dark
	run "$XGHOST" theme current
	[ "$status" -eq 0 ]
	[ "$output" = "macos-dark" ]
}

@test "theme current reports the theme name of a theme whose name holds a hyphen" {
	"$XGHOST" theme set macos-dark
	run "$XGHOST" theme current
	[ "$status" -eq 0 ]
	[ "$output" = "macos-dark" ]
}

@test "theme current takes no argument" {
	run "$XGHOST" theme current extra
	[ "$status" -eq 2 ]
	[[ $output == *"takes no argument"* ]]
}

# --- the output path --------------------------------------------------------

@test "the generated output lands under the state directory of the user" {
	"$XGHOST" theme set tokyonight
	[ -d "$GENERATED" ]
	[ -f "$GENERATED/shell/colors.sh" ]
}

@test "the generated output lands outside the repository working tree" {
	local resolved
	"$XGHOST" theme set tokyonight
	resolved=$(readlink -f "$GENERATED")
	[ -n "$resolved" ]
	[[ $resolved != "$ROOT_DIR"/* ]]
}

@test "the generated output falls back to the default state directory" {
	unset XDG_STATE_HOME
	run "$XGHOST" theme set tokyonight
	[ "$status" -eq 0 ]
	[ -f "$HOME/.local/state/xghost/generated/shell/colors.sh" ]
}

@test "a relative XDG_STATE_HOME is ignored, as the specification requires" {
	cd "$BATS_TEST_TMPDIR"
	export XDG_STATE_HOME=relative/state
	run "$XGHOST" theme set tokyonight
	[ "$status" -eq 0 ]
	[ -f "$HOME/.local/state/xghost/generated/shell/colors.sh" ]
	[ ! -e "$BATS_TEST_TMPDIR/relative" ]
}

@test "the stable path does not move between switches" {
	"$XGHOST" theme set tokyonight
	local first
	first=$(readlink -f "$GENERATED/shell/colors.sh")
	"$XGHOST" theme set macos-dark
	[ -f "$GENERATED/shell/colors.sh" ]
	[ "$first" != "$(readlink -f "$GENERATED/shell/colors.sh")" ]
}

# --- scalar substitution ----------------------------------------------------

@test "a scalar substitutes in its plain form" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template plain.conf <<-'EOF'
		bg=@BG@
		accent=@ACCENT@
		font=@FONT@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/plain.conf"
	[ "$output" = "bg=#1a2b3c
accent=#0A84FF
font=Inter" ]
}

@test "a colour substitutes in the form without a leading hash" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template hex.conf <<-'EOF'
		bg=@BG_HEX@
		accent=@ACCENT_HEX@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/hex.conf"
	[ "$output" = "bg=1a2b3c
accent=0A84FF" ]
}

@test "a colour substitutes in its decimal component form" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template rgb.conf <<-'EOF'
		bg=@BG_RGB@
		accent=@ACCENT_RGB@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/rgb.conf"
	[ "$output" = "bg=26, 43, 60
accent=10, 132, 255" ]
}

@test "a value that is not a colour carries no derived form" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template font.conf <<-'EOF'
		font=@FONT_HEX@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"font.conf: the palette has no value for 'FONT_HEX'"* ]]
}

@test "the renderer keeps the case the theme author wrote" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template case.conf <<-'EOF'
		@ACCENT@ @ACCENT_HEX@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/case.conf"
	[ "$output" = "#0A84FF 0A84FF" ]
}

@test "the renderer walks a template directory that holds subdirectories" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template one/two/deep.conf <<-'EOF'
		bg=@BG@
	EOF
	"$XGHOST" theme set demo
	[ -f "$GENERATED/one/two/deep.conf" ]
}

@test "an executable template produces an executable file" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template run.sh <<-'EOF'
		#!/usr/bin/env bash
		printf '%s\n' '@BG@'
	EOF
	chmod +x "$XGHOST_TEMPLATE_DIR/run.sh"
	"$XGHOST" theme set demo
	[ -x "$GENERATED/run.sh" ]
}

# --- the hand-written file a theme ships ------------------------------------

@test "a hand-written file is not overwritten by the template of the same name" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template gtk/colors.css <<-'EOF'
		generated @BG@
	EOF
	make_theme_file demo gtk/colors.css <<-'EOF'
		hand written
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/gtk/colors.css"
	[ "$output" = "hand written" ]
}

@test "a hand-written file is copied even when no template matches it" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	make_theme_file demo extra/notes.txt <<-'EOF'
		notes
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/extra/notes.txt"
	[ "$output" = "notes" ]
	[ -f "$GENERATED/plain.conf" ]
}

@test "a hand-written file is copied unchanged, placeholders included" {
	use_own_inputs
	plain_palette | make_theme demo
	make_theme_file demo raw.conf <<-'EOF'
		bg=@BG@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/raw.conf"
	[ "$output" = "bg=@BG@" ]
}

@test "the templates a hand-written file does not replace are still generated" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template gtk/colors.css <<-'EOF'
		generated @BG@
	EOF
	make_template hypr/colors.conf <<-'EOF'
		$bg = rgb(@BG_HEX@)
	EOF
	make_theme_file demo gtk/colors.css <<-'EOF'
		hand written
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/hypr/colors.conf"
	[ "$output" = "\$bg = rgb(1a2b3c)" ]
}

# --- a failed switch leaves the previous theme intact -----------------------

@test "an unknown theme is reported and the active theme is unchanged" {
	"$XGHOST" theme set tokyonight
	run "$XGHOST" theme set nosuchtheme
	[ "$status" -eq 1 ]
	[[ $output == *"unknown theme 'nosuchtheme'"* ]]
	run "$XGHOST" theme current
	[ "$output" = "tokyonight" ]
}

@test "a theme name that holds a path separator is refused" {
	run "$XGHOST" theme set ../etc
	[ "$status" -eq 1 ]
	[[ $output == *"is not a theme name"* ]]
}

@test "theme set needs a theme name" {
	run "$XGHOST" theme set
	[ "$status" -eq 2 ]
	[[ $output == *"needs a theme name"* ]]
}

@test "theme set takes one theme name" {
	run "$XGHOST" theme set one two
	[ "$status" -eq 2 ]
	[[ $output == *"takes one theme name"* ]]
}

@test "a template that names a value the palette lacks fails the render" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template broken.conf <<-'EOF'
		a=@BG@
		b=@NOSUCH@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"broken.conf: the palette has no value for 'NOSUCH'"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

@test "a failed render leaves every file of the previous theme in place" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	"$XGHOST" theme set demo

	make_template broken.conf <<-'EOF'
		b=@NOSUCH@
	EOF
	plain_palette | make_theme other
	run "$XGHOST" theme set other
	[ "$status" -eq 1 ]

	run "$XGHOST" theme current
	[ "$output" = "demo" ]
	run cat "$GENERATED/plain.conf"
	[ "$output" = "bg=#1a2b3c" ]
	[ ! -e "$GENERATED/broken.conf" ]
}

@test "a failed render leaves no half-built directory behind" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	"$XGHOST" theme set demo

	make_template broken.conf <<-'EOF'
		b=@NOSUCH@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[ "$(build_count)" -eq 1 ]
}

@test "the renderer reports every problem of one render, not only the first" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template first.conf <<-'EOF'
		a=@MISSING_ONE@
	EOF
	make_template second.conf <<-'EOF'
		b=@MISSING_TWO@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"MISSING_ONE"* ]]
	[[ $output == *"MISSING_TWO"* ]]
}

# --- the palette is data, and it is validated -------------------------------

@test "a palette key that is given twice is reported" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=#111111
		BG=#222222
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"line 2: 'BG' is given more than once"* ]]
}

@test "a palette key that is not upper case is reported" {
	use_own_inputs
	make_theme demo <<-'EOF'
		bg=#111111
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"'bg' is not a palette key"* ]]
}

@test "a palette key that collides with a derived form is reported" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=#111111
		BG_HEX=222222
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"'BG_HEX' ends in '_HEX' or '_RGB'"* ]]
}

@test "a palette line that is not a pair is reported with its line number" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=#111111
		this is not a pair
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"line 2: expected 'KEY=value'"* ]]
}

@test "a palette key with no value is reported" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"'BG' has no value"* ]]
}

@test "a palette that declares nothing is reported" {
	use_own_inputs
	make_theme demo <<-'EOF'
		# a comment and nothing else
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"the palette declares no value"* ]]
}

@test "a palette accepts a quoted value and a comment" {
	use_own_inputs
	make_theme demo <<-'EOF'
		# The palette of the demo theme.
		BG="#1a2b3c"
		FONT="Inter Display"
	EOF
	make_template quoted.conf <<-'EOF'
		@BG@|@FONT@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/quoted.conf"
	[ "$output" = "#1a2b3c|Inter Display" ]
}

@test "the renderer never runs the text of a palette" {
	use_own_inputs
	local evidence="$BATS_TEST_TMPDIR/evidence"
	make_theme demo <<-EOF
		BG=\$(touch "$evidence")
	EOF
	make_template value.conf <<-'EOF'
		bg=@BG@
	EOF
	"$XGHOST" theme set demo
	[ ! -e "$evidence" ]
	run cat "$GENERATED/value.conf"
	[ "$output" = "bg=\$(touch \"$evidence\")" ]
}

# --- the renderer is a pure function ----------------------------------------

@test "the same theme rendered twice produces the same output" {
	local first="$BATS_TEST_TMPDIR/first"
	"$XGHOST" theme set tokyonight
	mkdir -p "$first"
	cp -R "$GENERATED/." "$first/"
	"$XGHOST" theme set tokyonight
	diff -ru "$first" "$GENERATED"
}

@test "a switch away and back reproduces the first output" {
	local first="$BATS_TEST_TMPDIR/first"
	"$XGHOST" theme set tokyonight
	mkdir -p "$first"
	cp -R "$GENERATED/." "$first/"
	"$XGHOST" theme set macos-dark
	run diff -ru "$first" "$GENERATED"
	[ "$status" -ne 0 ]
	"$XGHOST" theme set tokyonight
	diff -ru "$first" "$GENERATED"
}

@test "a render writes nothing into the theme directory or the template directory" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	local before after
	before=$(find "$XGHOST_THEMES_DIR" "$XGHOST_TEMPLATE_DIR" | LC_ALL=C sort)
	"$XGHOST" theme set demo
	after=$(find "$XGHOST_THEMES_DIR" "$XGHOST_TEMPLATE_DIR" | LC_ALL=C sort)
	[ "$before" = "$after" ]
}
