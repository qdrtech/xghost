#!/usr/bin/env bats
#
# Golden-file tests for the xghost renderer.
#
# Every shipped theme is rendered against every shipped template, at every knob
# set, and the result is compared with the expected output committed under
# tests/golden/<knob set>/<theme>/. A template change that breaks any theme
# fails here, and so does a knob change that reaches no template.
#
# There are two knob sets, because one alone would pass with a knob that nothing
# consumes:
#
#   default    no knobs file at all, so every knob holds the default of
#              schema/knobs.conf.
#   alternate  tests/fixtures/knobs/alternate.conf, which holds every knob at a
#              value that is not its default.
#
# Each test drives the real command, so it asserts what lands on disk. No test
# reaches into an internal function.
#
# When a change to a template, a palette, or the renderer is intentional, run
#
#   tests/regenerate-golden --update
#
# and read the difference before committing it. That script refuses to run when
# CI is set, so continuous integration can only prove the committed output.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	GOLDEN_DIR="$BATS_TEST_DIRNAME/golden"
	TEMPLATE_DIR="$BATS_TEST_DIRNAME/../templates"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$BATS_TEST_DIRNAME/../commands"

	# Every path the commands read comes from this setup, so no override that
	# the person who runs the tests happens to export reaches a command. A
	# developer with XGHOST_TEMPLATE_DIR exported would otherwise render from
	# templates that are not the ones these tests compare against, and every
	# assertion below would still pass.
	unset XGHOST_ROOT
	unset XGHOST_THEMES_DIR
	unset XGHOST_TEMPLATE_DIR
	unset XGHOST_CONFIG_SOURCE
	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR
	unset XGHOST_KNOBS_SCHEMA

	# The renderer writes under the state directory of the user, so each test
	# gets a home of its own and touches nothing outside it.
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_STATE_HOME"

	# The fixed machine facts of the golden output, which ADR 0001 names as the
	# second input of these tests. tests/regenerate-golden reads the same file,
	# so the committed output never depends on the hardware of whoever runs it.
	# One test below copies the fixture into a project of its own, so the path
	# is kept as well as exported.
	use_fixed_machine_facts
	MACHINE_FACTS="$XGHOST_MACHINE_FACTS"

	# The knobs are the third input, and the same rule holds for them: the
	# committed output must not depend on the preferences of whoever runs the
	# suite. use_own_knobs points the commands at a path that holds no file,
	# which is the 'default' knob set.
	use_own_knobs
	ALTERNATE_KNOBS="$BATS_TEST_DIRNAME/fixtures/knobs/alternate.conf"
	KNOB_SETS=(default alternate)

	GENERATED="$XDG_STATE_HOME/xghost/generated"

	# The two files of the generated output that are not committed here, and
	# the reason each one is left out:
	#
	#   hypr/background.png   an image of several megapixels, drawn per theme.
	#                         Criterion 7 of issue #20 keeps a generated image
	#                         out of the repository, so a curl install stays a
	#                         quick clone.
	#   hypr/wallpaper.conf   it names the image by the stable path of the
	#                         generated output, which is a path of the machine
	#                         that rendered it. docs/backgrounds.md records why
	#                         that path cannot be relative.
	#
	# Neither is left unproved: tests/background.bats renders both and asserts
	# the size, the colours and the text of them.
	GOLDEN_EXCLUDED=(-x background.png -x wallpaper.conf)
}

# Render every following command with one knob set.
#
#   use_knob_set default | alternate
use_knob_set() {
	case $1 in
	default) export XGHOST_KNOBS_FILE="$BATS_TEST_TMPDIR/knobs.conf" ;;
	alternate) export XGHOST_KNOBS_FILE="$ALTERNATE_KNOBS" ;;
	*) return 1 ;;
	esac
	[ ! -e "$XGHOST_KNOBS_FILE" ] || [ "$1" = alternate ]
}

# Print the path one template takes in the generated output.
#
# A file inside a structural choice is a fragment rather than a template of its
# own: the renderer writes one of them, at the path the choice directory names.
# Every other template keeps its own relative path.
output_path() {
	local relative=$1
	local parent=${relative%/*}
	local base=${parent##*/}

	if [ "$parent" = "$relative" ]; then
		printf '%s\n' "$relative"
		return 0
	fi
	case $base in
	*.choice.*)
		base=${base%.choice.*}
		parent=${parent%/*}
		if [ "$parent" = "${relative%/*}" ]; then
			printf '%s\n' "$base"
		else
			printf '%s/%s\n' "$parent" "$base"
		fi
		;;
	*)
		printf '%s\n' "$relative"
		;;
	esac
}

@test "the shipped themes are the two themes ported from dotfiles" {
	run "$XGHOST" theme list
	[ "$status" -eq 0 ]
	[ "$output" = "macos-dark
tokyonight" ]
}

@test "every theme renders exactly the committed golden output, at every knob set" {
	local set theme count=0
	for set in "${KNOB_SETS[@]}"; do
		use_knob_set "$set"
		while IFS= read -r theme; do
			[ -n "$theme" ]
			[ -d "$GOLDEN_DIR/$set/$theme" ]
			"$XGHOST" theme set "$theme" >/dev/null
			diff -ru "${GOLDEN_EXCLUDED[@]}" "$GOLDEN_DIR/$set/$theme" "$GENERATED"
			count=$((count + 1))
		done < <("$XGHOST" theme list)
	done
	[ "$count" -gt 0 ]
}

@test "every golden directory names a knob set and a theme that exist" {
	local themes path name set count=0
	themes=$("$XGHOST" theme list)
	for path in "$GOLDEN_DIR"/*; do
		[ -d "$path" ]
		set=${path##*/}
		[[ " ${KNOB_SETS[*]} " == *" $set "* ]]
		for name in "$path"/*; do
			[ -d "$name" ]
			name=${name##*/}
			[[ $'\n'$themes$'\n' == *$'\n'"$name"$'\n'* ]]
			count=$((count + 1))
		done
	done
	[ "$count" -gt 0 ]
}

# Every knob set holds a directory for every theme, so a knob set that was never
# regenerated is a failure rather than a comparison nobody makes.
@test "every knob set holds every theme" {
	local set theme
	for set in "${KNOB_SETS[@]}"; do
		[ -d "$GOLDEN_DIR/$set" ]
		while IFS= read -r theme; do
			[ -d "$GOLDEN_DIR/$set/$theme" ]
		done < <("$XGHOST" theme list)
	done
}

@test "the golden output of every theme holds every template" {
	local set theme path relative
	for set in "${KNOB_SETS[@]}"; do
		while IFS= read -r theme; do
			while IFS= read -r path; do
				relative=$(output_path "${path#"$TEMPLATE_DIR/"}")
				[ -f "$GOLDEN_DIR/$set/$theme/$relative" ]
			done < <(find "$TEMPLATE_DIR" -type f)
		done < <("$XGHOST" theme list)
	done
}

# A knob that no template consumes renders two identical trees, and a knob that
# no template consumes is not a knob. The comparison is of the committed output,
# so this holds whether or not the renderer runs.
@test "the two knob sets render different output" {
	local theme count=0
	while IFS= read -r theme; do
		run diff -r "$GOLDEN_DIR/default/$theme" "$GOLDEN_DIR/alternate/$theme"
		[ "$status" -ne 0 ]
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

# The three knobs of schema/knobs.conf, each one at both of its golden values.
# A knob reaches a real file of a real bundle, and this is where that is proved
# against committed text rather than against a render.
@test "each knob reaches the generated output at both knob sets" {
	local theme
	while IFS= read -r theme; do
		# KNOB_ANIMATIONS is structural: one whole fragment per value.
		run grep -Fx '    enabled = true' "$GOLDEN_DIR/default/$theme/hypr/animation.conf"
		[ "$status" -eq 0 ]
		run grep -Fx '    enabled = false' "$GOLDEN_DIR/alternate/$theme/hypr/animation.conf"
		[ "$status" -eq 0 ]

		# KNOB_GAP_SIZE is a scalar, and it reaches the Hyprland window gaps.
		run grep -Fx '    gaps_in = 10' "$GOLDEN_DIR/default/$theme/hypr/knobs.conf"
		[ "$status" -eq 0 ]
		run grep -Fx '    gaps_in = 20' "$GOLDEN_DIR/alternate/$theme/hypr/knobs.conf"
		[ "$status" -eq 0 ]

		# KNOB_FONT is a scalar, and it reaches two bundles.
		run grep -Fx '    font_family = JetBrainsMono Nerd Font' \
			"$GOLDEN_DIR/default/$theme/hypr/knobs.conf"
		[ "$status" -eq 0 ]
		run grep -Fx 'font-family = JetBrainsMono Nerd Font' \
			"$GOLDEN_DIR/default/$theme/ghostty/font.conf"
		[ "$status" -eq 0 ]
		run grep -Fx '    font_family = CaskaydiaCove Nerd Font' \
			"$GOLDEN_DIR/alternate/$theme/hypr/knobs.conf"
		[ "$status" -eq 0 ]
		run grep -Fx 'font-family = CaskaydiaCove Nerd Font' \
			"$GOLDEN_DIR/alternate/$theme/ghostty/font.conf"
		[ "$status" -eq 0 ]
	done < <("$XGHOST" theme list)
}

# One fragment of a structural choice reaches the output, and it is the one the
# value selects. A test that only asked for the output file to exist would pass
# with every fragment written over the top of the last.
@test "a structural choice writes one fragment and names no other" {
	local theme count=0
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		# The fixed facts declare two monitors, so the two-monitor fragment is
		# the one that lands.
		run grep -Fx '# This fragment is the one for 2 monitors.' \
			"$GENERATED/hypr/monitors.conf"
		[ "$status" -eq 0 ]
		run grep -Fx '# This fragment is the one for 2 monitors.' \
			"$GENERATED/hypr/workspaces.conf"
		[ "$status" -eq 0 ]
		[ ! -e "$GENERATED/hypr/monitors.conf.choice.MACHINE_MONITOR_COUNT" ]
		[ ! -e "$GENERATED/hypr/workspaces.conf.choice.MACHINE_MONITOR_COUNT" ]

		# A knob drives a structural choice the same way a machine fact does,
		# and the default of KNOB_ANIMATIONS is 'on'.
		run grep -Fx "# This fragment is the one for 'KNOB_ANIMATIONS=on'." \
			"$GENERATED/hypr/animation.conf"
		[ "$status" -eq 0 ]
		[ ! -e "$GENERATED/hypr/animation.conf.choice.KNOB_ANIMATIONS" ]
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

@test "the golden output carries no unsubstituted placeholder" {
	run grep -rE '@[A-Z][A-Z0-9_]*@' "$GOLDEN_DIR"
	[ "$status" -ne 0 ]
}

@test "the regeneration flag is required" {
	run "$BATS_TEST_DIRNAME/regenerate-golden"
	[ "$status" -eq 2 ]
	[[ $output == *"Usage: regenerate-golden --update"* ]]
}

@test "the regeneration script refuses to run in continuous integration" {
	CI=true run "$BATS_TEST_DIRNAME/regenerate-golden" --update
	[ "$status" -eq 1 ]
	[[ $output == *"CI is set"* ]]
}

# The script renders every theme first and replaces tests/golden/ only once all
# of them have succeeded. A copy of the project is used, so the test can add a
# theme that cannot render without touching the committed reference files.
@test "a regeneration that cannot render a theme leaves the golden output in place" {
	local project="$BATS_TEST_TMPDIR/project"
	local source_dir="$BATS_TEST_DIRNAME/.."
	mkdir -p "$project/tests"
	cp -R "$source_dir/bin" "$source_dir/lib" "$source_dir/commands" \
		"$source_dir/templates" "$source_dir/themes" "$source_dir/schema" \
		"$project/"
	cp "$BATS_TEST_DIRNAME/regenerate-golden" "$project/tests/regenerate-golden"

	# The script reads the fixed machine facts and the alternate knobs, and it
	# stops when either is missing. The copy needs both, so the failure this
	# test asserts on is the theme that cannot render and nothing else.
	mkdir -p "$project/tests/fixtures/machine" "$project/tests/fixtures/knobs"
	cp "$MACHINE_FACTS" "$project/tests/fixtures/machine/golden.conf"
	cp "$ALTERNATE_KNOBS" "$project/tests/fixtures/knobs/alternate.conf"

	# The reference files that must survive the failure.
	mkdir -p "$project/tests/golden/keep"
	printf 'reference\n' >"$project/tests/golden/keep/marker"

	# A theme that sorts first and names none of the values the templates need.
	mkdir -p "$project/themes/broken"
	printf 'UNUSED=#000000\n' >"$project/themes/broken/palette.conf"

	# Every override of this test file is dropped, so the script drives the
	# copy of the project rather than the checkout it was copied from.
	run env -u CI -u XGHOST_COMMAND_DIR -u XGHOST_ROOT \
		-u XGHOST_THEMES_DIR -u XGHOST_TEMPLATE_DIR \
		-u XGHOST_KNOBS_FILE -u XGHOST_KNOBS_SCHEMA \
		HOME="$BATS_TEST_TMPDIR/home" \
		"$project/tests/regenerate-golden" --update
	[ "$status" -eq 1 ]
	[[ $output == *"cannot render the theme 'broken'"* ]]
	[[ $output == *"tests/golden is unchanged."* ]]

	[ -f "$project/tests/golden/keep/marker" ]
	[ "$(cat "$project/tests/golden/keep/marker")" = reference ]
	[ ! -e "$project/tests/golden/default" ]
	[ ! -e "$project/tests/golden/tokyonight" ]
}
