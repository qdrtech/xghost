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

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# The renderer writes under the state directory of the user, so each test
	# gets a home of its own and touches nothing outside it.
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_STATE_HOME"

	# Several tests below render a shipped theme, and the shipped templates
	# make a structural choice from a machine fact. Without facts every one of
	# those renders fails on the fact it wanted, whatever the test is about.
	# tests/helpers.bash records why this is a suite-wide need.
	#
	# A test that describes its own inputs with use_own_inputs renders no
	# shipped template, so the facts reach nothing it asserts on.
	use_fixed_machine_facts

	# The knobs are the third input. Every test here renders with the shipped
	# schema and no knobs file, so every knob holds its default and no
	# preference of whoever runs the suite reaches a render.
	use_own_knobs

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
	[[ $output == *"font.conf: no value for 'FONT_HEX' in the theme palette, the machine facts or the knobs"* ]]
}

@test "a value that holds an ampersand reaches the output unchanged" {
	use_own_inputs
	make_theme demo <<-'EOF'
		FONT=Gill Sans & Co
	EOF
	make_template font.conf <<-'EOF'
		font=@FONT@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/font.conf"
	[ "$output" = 'font=Gill Sans & Co' ]
}

# --- a value a generated file cannot carry ----------------------------------
#
# The renderer writes a value into a file another program reads as code, and it
# cannot know where in that file the value lands. So the rule is the value: six
# characters are refused, whatever the template and whichever of the three
# sources declared the value. Each one has a test below, and the failure is the
# whole render.

@test "a value that holds a quotation mark fails the render" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=#1a2b3c", os.execute("touch /tmp/evidence
	EOF
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"plain.conf: the value of 'BG' holds a quotation mark"* ]]
	[ ! -e "$GENERATED/plain.conf" ]
}

@test "a value that holds an apostrophe fails the render" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=#1a2b3c'; touch /tmp/evidence; :'
	EOF
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"plain.conf: the value of 'BG' holds an apostrophe"* ]]
	[ ! -e "$GENERATED/plain.conf" ]
}

@test "a value that holds a backtick fails the render" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=`touch /tmp/evidence`
	EOF
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"plain.conf: the value of 'BG' holds a backtick"* ]]
	[ ! -e "$GENERATED/plain.conf" ]
}

# A backslash reached the output unchanged until issue #48. It escapes the
# character after it, so a value of one backslash turns the closing quotation
# mark of 'templates/nvim/colors.lua' into an ordinary character and the string
# runs on into the next line of the file.
@test "a value that holds a backslash fails the render" {
	use_own_inputs
	make_theme demo <<-'EOF'
		ONE=a\b
		TWO=a\\b
	EOF
	make_template slash.conf <<-'EOF'
		one=@ONE@
		two=@TWO@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"slash.conf: the value of 'ONE' holds a backslash: 'a\\b'"* ]]
	[[ $output == *"slash.conf: the value of 'TWO' holds a backslash: 'a\\\\b'"* ]]
	[ ! -e "$GENERATED/slash.conf" ]
}

@test "a value that ends in a backslash fails the render" {
	use_own_inputs
	make_theme demo <<-'EOF'
		ONE=trailing\
	EOF
	make_template trailing.conf <<-'EOF'
		one=@ONE@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"trailing.conf: the value of 'ONE' holds a backslash"* ]]
	[ ! -e "$GENERATED/trailing.conf" ]
}

@test "a value that holds a dollar sign fails the render" {
	use_own_inputs
	make_theme demo <<-'EOF'
		BG=$(touch /tmp/evidence)
	EOF
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"plain.conf: the value of 'BG' holds a dollar sign"* ]]
	[ ! -e "$GENERATED/plain.conf" ]
}

# The palette reader drops the white space at both ends of a value, so a tab
# reaches the table only from the middle of one. It ends no line here, and it
# is refused all the same: 'templates/hypr/knobs.conf' puts a value on a line
# of its own with no literal around it at all.
@test "a value that holds a control character fails the render" {
	use_own_inputs
	printf 'FONT=Inter\tDisplay\n' | make_theme demo
	make_template font.conf <<-'EOF'
		font=@FONT@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"font.conf: the value of 'FONT' holds a control character"* ]]
	[ ! -e "$GENERATED/font.conf" ]
}

# The rule is the renderer's, so it reaches every source of a value and not the
# theme palette alone. A machine fact is the source a user edits by hand.
@test "a machine fact that holds a quotation mark fails the render" {
	use_own_inputs
	plain_palette | make_theme demo
	cat >"$XGHOST_MACHINE_FACTS" <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_MONITOR_1_NAME=DP-1", os.execute("touch /tmp/evidence
	EOF
	make_template monitor.conf <<-'EOF'
		name=@MACHINE_MONITOR_1_NAME@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"monitor.conf: the value of 'MACHINE_MONITOR_1_NAME' holds a quotation mark"* ]]
	[ ! -e "$GENERATED/monitor.conf" ]
}

# Criterion 3 of issue #48: the report names the theme, the value and the
# template, so the reader knows which of the three inputs to correct without
# rendering again.
@test "the report of a refused value names the theme, the value and the template" {
	use_own_inputs
	make_theme sunken <<-'EOF'
		BG=#1a2b3c"
	EOF
	make_template deep/plain.conf <<-'EOF'
		bg=@BG@
	EOF
	run "$XGHOST" theme set sunken
	[ "$status" -eq 1 ]
	[[ $output == *"sunken: deep/plain.conf: the value of 'BG' holds a quotation mark: '#1a2b3c\"'."* ]]
	[[ $output == *"the render of theme 'sunken' failed. The active theme is unchanged."* ]]
}

# A value that carries no character of the six still reaches the output as the
# text it is. Without this the rule above could be widened to every value and
# every test here would still pass.
@test "a value that holds an ampersand, a hash and a comma still renders" {
	use_own_inputs
	make_theme demo <<-'EOF'
		FONT=Gill Sans & Co
		BG=#1a2b3c
		LIST=26, 43, 60
	EOF
	make_template mixed.conf <<-'EOF'
		font=@FONT@
		bg=@BG@
		list=@LIST@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/mixed.conf"
	[ "$output" = 'font=Gill Sans & Co
bg=#1a2b3c
list=26, 43, 60' ]
}

# Criterion 5 of issue #48. Both files are executed rather than parsed as data:
# Neovim loads the first as a Lua chunk and a shell sources the second. The
# theme here is a shipped palette with one colour perturbed, and the render
# runs against the shipped templates, so this test names the real files.
@test "a value that would close a literal is refused in the two executed templates" {
	unset XGHOST_TEMPLATE_DIR
	export XGHOST_THEMES_DIR="$BATS_TEST_TMPDIR/themes"
	mkdir -p "$XGHOST_THEMES_DIR"
	cp -R "$ROOT_DIR/themes/tokyonight" "$XGHOST_THEMES_DIR/broken"
	sed -i 's/^BG=.*/BG=#1A1B26", os.execute("touch \/tmp\/evidence/' \
		"$XGHOST_THEMES_DIR/broken/palette.conf"

	run "$XGHOST" theme set broken
	[ "$status" -eq 1 ]
	[[ $output == *"nvim/colors.lua: the value of 'BG' holds a quotation mark"* ]]
	[[ $output == *"shell/colors.sh: the value of 'BG' holds a quotation mark"* ]]
	[ ! -e "$GENERATED/nvim/colors.lua" ]
	[ ! -e "$GENERATED/shell/colors.sh" ]
}

# Criterion 3 of issue #48, and the part of it that goes wrong quietly. The
# renderer builds a whole tree and lib/theme.sh moves it into place, so a
# refused value has to leave the tree that is already there untouched, byte for
# byte. This renders the shipped templates, so it compares a whole desktop
# rather than one file.
#
# The value that is perturbed is a machine fact rather than a palette colour.
# A colour that carries a quotation mark stops matching '#rrggbb', so it loses
# its two derived forms and the render would fail on a missing '@BG_HEX@'
# whatever this rule did. A monitor name carries no derived form, so the
# quotation mark is the one and only reason this render is refused.
@test "a refused value leaves the previous generated output byte for byte" {
	unset XGHOST_TEMPLATE_DIR

	"$XGHOST" theme set tokyonight
	local before="$BATS_TEST_TMPDIR/before"
	cp -RL "$GENERATED" "$before"

	sed -i 's/^MACHINE_MONITOR_1_NAME=.*/MACHINE_MONITOR_1_NAME=DP-1", os.execute("touch \/tmp\/evidence/' \
		"$XGHOST_MACHINE_FACTS"

	run "$XGHOST" theme set macos-dark
	[ "$status" -eq 1 ]
	[[ $output == *"the value of 'MACHINE_MONITOR_1_NAME' holds a quotation mark"* ]]

	# The theme did not change, the tree did not change, and no build was left
	# behind for the next switch to trip over.
	run "$XGHOST" theme current
	[ "$output" = "tokyonight" ]
	run diff -r "$before" "$GENERATED"
	[ "$status" -eq 0 ]
	[ "$(build_count)" -eq 1 ]

	# The text that would have closed a literal is nowhere in the output.
	run grep -rF 'os.execute' "$GENERATED"
	[ "$status" -ne 0 ]
}

@test "a value that holds a placeholder is not substituted again" {
	use_own_inputs
	make_theme demo <<-'EOF'
		AAA=@ZZZ@
		ZZZ=hello
	EOF
	make_template pass.conf <<-'EOF'
		a=@AAA@
		z=@ZZZ@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/pass.conf"
	[ "$output" = 'a=@ZZZ@
z=hello' ]
}

# The same shape with the two names swapped. The old renderer walked the
# palette in the order the associative array happened to hold its keys, so one
# of the two rendered twice and the other failed the render.
@test "the substitution does not depend on the order of the palette keys" {
	use_own_inputs
	make_theme demo <<-'EOF'
		ZZZ=@AAA@
		AAA=hello
	EOF
	make_template pass.conf <<-'EOF'
		z=@ZZZ@
		a=@AAA@
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/pass.conf"
	[ "$output" = 'z=@AAA@
a=hello' ]
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

@test "a template that is a symbolic link is rendered" {
	use_own_inputs
	plain_palette | make_theme demo
	printf 'bg=@BG@\n' >"$BATS_TEST_TMPDIR/upstream.conf"
	ln -s "$BATS_TEST_TMPDIR/upstream.conf" "$XGHOST_TEMPLATE_DIR/linked.conf"
	"$XGHOST" theme set demo
	run cat "$GENERATED/linked.conf"
	[ "$output" = "bg=#1a2b3c" ]
	[ ! -L "$GENERATED/linked.conf" ]
}

@test "a template whose link points at nothing is reported by name" {
	use_own_inputs
	plain_palette | make_theme demo
	ln -s "$BATS_TEST_TMPDIR/gone.conf" "$XGHOST_TEMPLATE_DIR/dangling.conf"
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"dangling.conf: the symbolic link points at nothing"* ]]
}

@test "a template that holds a NUL byte is refused by name" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template good.conf <<-'EOF'
		bg=@BG@
	EOF
	printf 'a\0b\n' >"$XGHOST_TEMPLATE_DIR/binary.conf"
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"binary.conf: the template holds a NUL byte"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

# The renderer says it is a pure function, so its output may not change with
# the umask of whoever called it.
@test "the modes of the generated output do not follow the umask of the caller" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template sub/deep.conf <<-'EOF'
		bg=@BG@
	EOF
	make_template run.sh <<-'EOF'
		#!/usr/bin/env bash
		printf '%s\n' '@BG@'
	EOF
	chmod +x "$XGHOST_TEMPLATE_DIR/run.sh"
	make_theme_file demo hand.conf <<-'EOF'
		hand written
	EOF

	(
		umask 077
		"$XGHOST" theme set demo >/dev/null
	)

	[ "$(stat -c %a "$GENERATED/sub/deep.conf")" = 644 ]
	[ "$(stat -c %a "$GENERATED/hand.conf")" = 644 ]
	[ "$(stat -c %a "$GENERATED/run.sh")" = 755 ]
	[ "$(stat -c %a "$GENERATED/sub")" = 755 ]
	[ "$(stat -c %a "$(readlink -f "$GENERATED")")" = 755 ]
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

# A theme whose upstream is a stow-managed dotfiles repository ships a link
# where another theme ships a file, and the two must mean the same thing.
@test "a hand-written file that is a symbolic link is copied" {
	use_own_inputs
	plain_palette | make_theme demo
	printf 'hand written waybar\n' >"$BATS_TEST_TMPDIR/upstream.conf"
	mkdir -p "$XGHOST_THEMES_DIR/demo/files"
	ln -s "$BATS_TEST_TMPDIR/upstream.conf" "$XGHOST_THEMES_DIR/demo/files/waybar.conf"
	"$XGHOST" theme set demo
	run cat "$GENERATED/waybar.conf"
	[ "$output" = "hand written waybar" ]
	# The output holds the file itself, never a link back into the theme.
	[ ! -L "$GENERATED/waybar.conf" ]
}

# A directory is not a file the theme ships. The copy loop reads the files of
# the theme, so a directory at that path puts nothing into the output, and
# treating it as a hand-written file would suppress the template and leave the
# output holding nothing at all at that path.
@test "a directory at the path of a hand-written file does not suppress the template" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template gtk/colors.css <<-'EOF'
		generated @BG@
	EOF
	mkdir -p "$XGHOST_THEMES_DIR/demo/files/gtk/colors.css"
	run "$XGHOST" theme set demo
	[ "$status" -eq 0 ]
	run cat "$GENERATED/gtk/colors.css"
	[ "$output" = "generated #1a2b3c" ]
}

# Issue #42, at the first of the three sites that ask what the theme ships.
#
# A symbolic link to a directory is what '-f' does not catch and '-L' does, so
# the renderer read it as a file the theme ships and passed the template over.
# 'find -L' named neither the link nor a file at that path, so the copy loop
# wrote nothing there either and the render reported success with the file
# missing. The link here points at a directory that holds a file, which is the
# worse face of it: those contents ARE walked, so the output held a DIRECTORY
# at the path of a configuration file.
#
# A theme is set first, so the assertion that the previous output survived is
# compared against a tree that really exists. Against the unfixed renderer this
# render succeeds, the active theme becomes 'demo', and 'gtk/colors.css' is a
# directory, so both assertions below fail.
@test "a link to a directory at the path of a hand-written file fails the render" {
	use_own_inputs
	plain_palette | make_theme demo
	plain_palette | make_theme good
	make_template gtk/colors.css <<-'EOF'
		generated @BG@
	EOF
	"$XGHOST" theme set good

	mkdir -p "$XGHOST_THEMES_DIR/demo/files/gtk" "$BATS_TEST_TMPDIR/upstream"
	printf 'a stray file\n' >"$BATS_TEST_TMPDIR/upstream/stray.txt"
	ln -s "$BATS_TEST_TMPDIR/upstream" "$XGHOST_THEMES_DIR/demo/files/gtk/colors.css"

	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"gtk/colors.css: the theme ships a symbolic link here and it points at a directory"* ]]
	[[ $output == *"The active theme is unchanged."* ]]

	run "$XGHOST" theme current
	[ "$output" = "good" ]
	run cat "$GENERATED/gtk/colors.css"
	[ "$output" = "generated #1a2b3c" ]
}

@test "a hand-written file whose link points at nothing is reported by name" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	mkdir -p "$XGHOST_THEMES_DIR/demo/files"
	ln -s "$BATS_TEST_TMPDIR/gone.conf" "$XGHOST_THEMES_DIR/demo/files/waybar.conf"
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"waybar.conf: the symbolic link points at nothing"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

# The renderer follows links now, so it must prove that following one cannot
# carry a write out of the directory it was given.
@test "a hand-written file cannot write outside the generated output" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF

	local outside="$BATS_TEST_TMPDIR/outside"
	mkdir -p "$outside" "$XGHOST_THEMES_DIR/demo/files"
	printf 'untouched\n' >"$outside/target.conf"
	ln -s "$outside" "$XGHOST_THEMES_DIR/demo/files/escape"

	"$XGHOST" theme set demo

	# The content is read in. It is never written back out.
	[ -f "$GENERATED/escape/target.conf" ]
	[ ! -L "$GENERATED/escape" ]
	[ "$(cat "$outside/target.conf")" = untouched ]
	[ "$(find "$outside" -mindepth 1 | wc -l)" -eq 1 ]
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

# --- the structural choice --------------------------------------------------
#
# The second substitution mechanism of ADR 0001. tests/hyprland.bats proves the
# case it was built for, against the shipped templates. These tests prove the
# mechanism itself, and every way one can be wrong, against templates the test
# writes.

# Write one fragment of one structural choice from standard input.
#
#   make_fragment CHOICE_DIRECTORY FRAGMENT
make_fragment() {
	make_file "$XGHOST_TEMPLATE_DIR/$1" "$2"
}

@test "a choice writes the fragment its value names, and writes nothing else" {
	use_own_inputs
	plain_palette | make_theme demo
	make_fragment pick.conf.choice.FONT Inter <<-'EOF'
		the fragment for Inter
	EOF
	make_fragment pick.conf.choice.FONT default <<-'EOF'
		the fallback
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/pick.conf"
	[ "$output" = "the fragment for Inter" ]
	[ ! -e "$GENERATED/pick.conf.choice.FONT" ]
}

# The same rule on the path a structural choice names.
@test "a directory at the path a choice names does not suppress the fragment" {
	use_own_inputs
	plain_palette | make_theme demo
	make_fragment pick.conf.choice.FONT default <<-'EOF'
		the fallback
	EOF
	mkdir -p "$XGHOST_THEMES_DIR/demo/files/pick.conf"
	run "$XGHOST" theme set demo
	[ "$status" -eq 0 ]
	run cat "$GENERATED/pick.conf"
	[ "$output" = "the fallback" ]
}

# Issue #42 at the second site. 'pick.conf' is written by the loop that renders
# the chosen fragment and by no other, because render_in_choice keeps the
# fragment out of the template loop, so this names that site and nothing else.
@test "a link to a directory at the path a choice names fails the render" {
	use_own_inputs
	plain_palette | make_theme demo
	plain_palette | make_theme good
	make_fragment pick.conf.choice.FONT default <<-'EOF'
		the fallback
	EOF
	"$XGHOST" theme set good

	mkdir -p "$XGHOST_THEMES_DIR/demo/files" "$BATS_TEST_TMPDIR/upstream"
	printf 'a stray file\n' >"$BATS_TEST_TMPDIR/upstream/stray.txt"
	ln -s "$BATS_TEST_TMPDIR/upstream" "$XGHOST_THEMES_DIR/demo/files/pick.conf"

	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"pick.conf: the theme ships a symbolic link here and it points at a directory"* ]]
	[[ $output == *"The active theme is unchanged."* ]]

	run "$XGHOST" theme current
	[ "$output" = "good" ]
	run cat "$GENERATED/pick.conf"
	[ "$output" = "the fallback" ]
}

@test "a value that no fragment names and no default fails the render" {
	use_own_inputs
	plain_palette | make_theme demo
	make_fragment pick.conf.choice.FONT Helvetica <<-'EOF'
		the fragment for Helvetica
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"pick.conf.choice.FONT: 'FONT' is 'Inter', and the structural choice has no fragment of that name and no 'default'"* ]]
	[[ $output == *"It holds: Helvetica"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
}

@test "a choice directory that holds no fragment is reported" {
	use_own_inputs
	plain_palette | make_theme demo
	mkdir -p "$XGHOST_TEMPLATE_DIR/empty.conf.choice.FONT"
	make_template plain.conf <<-'EOF'
		bg=@BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"empty.conf.choice.FONT: the structural choice holds no fragment"* ]]
}

# One choice holds fragments and nothing else. The fragments of the refused
# choice are still fragments, so the failing render reports the nesting alone
# and never the fragments at their literal paths.
@test "a choice inside a choice is refused, and its fragments stay fragments" {
	use_own_inputs
	plain_palette | make_theme demo
	make_fragment outer.conf.choice.FONT default <<-'EOF'
		the fallback
	EOF
	make_fragment outer.conf.choice.FONT/inner.conf.choice.BG default <<-'EOF'
		inner @NOSUCH@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"outer.conf.choice.FONT/inner.conf.choice.BG: a structural choice cannot hold another one, and this one is inside 'outer.conf.choice.FONT'"* ]]
	[[ $output != *"NOSUCH"* ]]
}

@test "a directory inside a choice is reported once, however many files it holds" {
	use_own_inputs
	plain_palette | make_theme demo
	make_fragment holder.conf.choice.FONT default <<-'EOF'
		the fallback
	EOF
	make_fragment holder.conf.choice.FONT sub/one <<-'EOF'
		one
	EOF
	make_fragment holder.conf.choice.FONT sub/two <<-'EOF'
		two
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"holder.conf.choice.FONT: a structural choice holds fragments and no directory, and it holds the directory 'sub'"* ]]
	[ "$(printf '%s\n' "$output" | grep -c "it holds the directory 'sub'")" -eq 1 ]
}

@test "a choice whose selector is not a name is reported" {
	use_own_inputs
	plain_palette | make_theme demo
	make_fragment bad.conf.choice.lower default <<-'EOF'
		x
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"bad.conf.choice.lower: a structural choice is named '<file>.choice.<NAME>'"* ]]
}

@test "a choice whose selector no value declares is reported" {
	use_own_inputs
	plain_palette | make_theme demo
	make_fragment pick.conf.choice.MACHINE_NOSUCH default <<-'EOF'
		x
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"pick.conf.choice.MACHINE_NOSUCH: no value for 'MACHINE_NOSUCH' in the theme palette, the machine facts or the knobs, and the structural choice is made by that value"* ]]
}

@test "two choices that write one path are reported" {
	use_own_inputs
	plain_palette | make_theme demo
	make_fragment same.conf.choice.FONT default <<-'EOF'
		one
	EOF
	make_fragment same.conf.choice.BG default <<-'EOF'
		two
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"it writes 'same.conf', and"* ]]
	[[ $output == *"writes that path as well"* ]]
}

# The same rule, with an ordinary template as the other writer. The template
# loop wrote that path first and the choice loop wrote over it, and neither
# check saw the other, so the output followed an order nobody chose.
@test "a plain template at the path a choice writes is reported" {
	use_own_inputs
	plain_palette | make_theme demo
	make_template clash.conf <<-'EOF'
		the plain template
	EOF
	make_fragment clash.conf.choice.FONT default <<-'EOF'
		the fragment
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"clash.conf.choice.FONT: it writes 'clash.conf', and 'clash.conf' writes that path as well"* ]]
	[ ! -e "$GENERATED/clash.conf" ]
}

# --- a machine fact detection could not read ---------------------------------

# 'unknown' is what lib/facts.sh writes for a fact detection could not read.
# Writing it produces a configuration file that states something about the
# machine nobody read: a Hyprland monitor line built from an unknown mode is
# refused by the compositor, and the switch that wrote it reported success.
@test "a template that names a machine fact that is unknown fails the render" {
	use_own_inputs
	plain_palette | make_theme demo
	export XGHOST_MACHINE_FACTS="$BATS_TEST_TMPDIR/unknown.conf"
	cat >"$XGHOST_MACHINE_FACTS" <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_MONITOR_COUNT=1
		MACHINE_MONITOR_1_MODE=unknown
	EOF
	make_template mode.conf <<-'EOF'
		mode=@MACHINE_MONITOR_1_MODE@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"mode.conf: 'MACHINE_MONITOR_1_MODE' is 'unknown' in the machine facts, which means detection could not read it"* ]]
	[[ $output == *"The active theme is unchanged."* ]]
	[ ! -e "$GENERATED/mode.conf" ]
}

# Selection is not substitution. A choice keyed on a fact detection could not
# read still selects its 'default' fragment, which is the fragment that names
# no fact of that source at all.
@test "a choice whose value is unknown still selects the default fragment" {
	use_own_inputs
	plain_palette | make_theme demo
	export XGHOST_MACHINE_FACTS="$BATS_TEST_TMPDIR/unknown-count.conf"
	cat >"$XGHOST_MACHINE_FACTS" <<-'EOF'
		MACHINE_FACTS_VERSION=1
		MACHINE_MONITOR_COUNT=unknown
	EOF
	make_fragment layout.conf.choice.MACHINE_MONITOR_COUNT 1 <<-'EOF'
		@MACHINE_MONITOR_1_NAME@
	EOF
	make_fragment layout.conf.choice.MACHINE_MONITOR_COUNT default <<-'EOF'
		no monitor is named
	EOF
	"$XGHOST" theme set demo
	run cat "$GENERATED/layout.conf"
	[ "$output" = "no monitor is named" ]
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
	[[ $output == *"broken.conf: no value for 'NOSUCH' in the theme palette, the machine facts or the knobs"* ]]
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

# The palette is a data file. lib/palette.sh reads it line by line and never
# sources it, so a value can never run a command however it was written. Since
# issue #48 such a value is refused before it reaches a file as well, so the
# proof is two assertions rather than one: nothing ran, and nothing was written.
@test "the renderer never runs the text of a palette" {
	use_own_inputs
	local evidence="$BATS_TEST_TMPDIR/evidence"
	make_theme demo <<-EOF
		BG=\$(touch "$evidence")
	EOF
	make_template value.conf <<-'EOF'
		bg=@BG@
	EOF
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[ ! -e "$evidence" ]
	[ ! -e "$GENERATED/value.conf" ]
	[[ $output == *"value.conf: the value of 'BG' holds a quotation mark"* ]]
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

# --- two switches at the same time ------------------------------------------

# Write enough templates that two renders started together overlap.
make_many_templates() {
	local count=$1 index
	for ((index = 1; index <= count; index++)); do
		printf 'bg=@BG@\n' >"$XGHOST_TEMPLATE_DIR/f$index.conf"
	done
}

@test "two switches that run at the same time both finish and leave a sound output" {
	use_own_inputs
	plain_palette | make_theme one
	plain_palette | make_theme two
	make_many_templates 200

	# A build to be pruned, so the prune of each switch has work to do.
	"$XGHOST" theme set one >/dev/null

	local first second
	"$XGHOST" theme set one >/dev/null 2>"$BATS_TEST_TMPDIR/first.err" &
	first=$!
	"$XGHOST" theme set two >/dev/null 2>"$BATS_TEST_TMPDIR/second.err" &
	second=$!
	wait "$first"
	wait "$second"

	# Neither switch printed anything, so neither lost its build to the other.
	[ ! -s "$BATS_TEST_TMPDIR/first.err" ]
	[ ! -s "$BATS_TEST_TMPDIR/second.err" ]

	# The stable path resolves, and it holds a whole build: the 200 templates,
	# the background image of the theme, and the file that names it.
	[ -d "$GENERATED/" ]
	[ "$(find "$GENERATED/" -type f | wc -l)" -eq 202 ]

	run "$XGHOST" theme current
	[ "$status" -eq 0 ]
	[ "$output" = one ] || [ "$output" = two ]

	# The prune ran, and it kept the build the stable path points at.
	[ "$(build_count)" -eq 1 ]
}

@test "a switch that runs beside another still names the theme it applied" {
	use_own_inputs
	plain_palette | make_theme one
	plain_palette | make_theme two
	make_many_templates 200

	local first second
	"$XGHOST" theme set one >"$BATS_TEST_TMPDIR/first.out" 2>&1 &
	first=$!
	"$XGHOST" theme set two >"$BATS_TEST_TMPDIR/second.out" 2>&1 &
	second=$!
	wait "$first"
	wait "$second"

	grep -q "the active theme is now 'one'" "$BATS_TEST_TMPDIR/first.out"
	grep -q "the active theme is now 'two'" "$BATS_TEST_TMPDIR/second.out"
	[ -d "$GENERATED/" ]
}

# --- the state directory is resolved at first use ---------------------------

@test "theme list works with neither XDG_STATE_HOME nor HOME in the environment" {
	run env -i "$XGHOST" theme list
	[ "$status" -eq 0 ]
	[ "$output" = "macos-dark
tokyonight" ]
}

@test "an empty environment does not turn a usage mistake into another error" {
	run env -i "$XGHOST" theme list extra
	[ "$status" -eq 2 ]
	[[ $output == *"takes no argument"* ]]
}

@test "theme current names the missing state directory" {
	run env -i "$XGHOST" theme current
	[ "$status" -eq 1 ]
	[[ $output == *"neither XDG_STATE_HOME nor HOME is set"* ]]
}

@test "theme set names the missing state directory" {
	run env -i "$XGHOST" theme set tokyonight
	[ "$status" -eq 1 ]
	[[ $output == *"neither XDG_STATE_HOME nor HOME is set"* ]]
}

# --- the libraries ----------------------------------------------------------

# Later slices consume these libraries, and two of them may each need the same
# one. A second source must be a no-op rather than an error.
@test "every library may be sourced twice" {
	run bash -c '
		set -euo pipefail
		. "$1/lib/palette.sh"
		. "$1/lib/palette.sh"
		. "$1/lib/json.sh"
		. "$1/lib/json.sh"
		. "$1/lib/facts.sh"
		. "$1/lib/facts.sh"
		. "$1/lib/renderer.sh"
		. "$1/lib/renderer.sh"
		. "$1/lib/detect.sh"
		. "$1/lib/detect.sh"
		. "$1/lib/theme.sh"
		. "$1/lib/theme.sh"
		. "$1/lib/linker.sh"
		. "$1/lib/linker.sh"
		printf "sound\n"
	' _ "$ROOT_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = sound ]
}

# --- the modules report, and nothing else prints ----------------------------

@test "a template that cannot be read is reported once, with no raw diagnostic" {
	if [ "$(id -u)" -eq 0 ]; then
		skip "root reads a file whose mode forbids it"
	fi
	use_own_inputs
	plain_palette | make_theme demo
	make_template locked.conf <<-'EOF'
		bg=@BG@
	EOF
	chmod 000 "$XGHOST_TEMPLATE_DIR/locked.conf"
	run "$XGHOST" theme set demo
	[ "$status" -eq 1 ]
	[[ $output == *"locked.conf: cannot read the template"* ]]
	[[ $output != *"Permission denied"* ]]
	[[ $output != *"renderer.sh: line"* ]]
}
