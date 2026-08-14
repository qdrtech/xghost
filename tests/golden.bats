#!/usr/bin/env bats
#
# Golden-file tests for the xghost renderer.
#
# Every shipped theme is rendered against every shipped template, and the result
# is compared with the expected output committed under tests/golden/. A template
# change that breaks any theme fails here.
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

	# The shipped commands, never the fixture directory of another test file.
	export XGHOST_COMMAND_DIR="$BATS_TEST_DIRNAME/../commands"

	# The renderer writes under the state directory of the user, so each test
	# gets a home of its own and touches nothing outside it.
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_STATE_HOME"

	GENERATED="$XDG_STATE_HOME/xghost/generated"
}

@test "the shipped themes are the two themes ported from dotfiles" {
	run "$XGHOST" theme list
	[ "$status" -eq 0 ]
	[ "$output" = "macos-dark
tokyonight" ]
}

@test "every theme renders exactly the committed golden output" {
	local theme count=0
	while IFS= read -r theme; do
		[ -n "$theme" ]
		[ -d "$GOLDEN_DIR/$theme" ]
		"$XGHOST" theme set "$theme" >/dev/null
		diff -ru "$GOLDEN_DIR/$theme" "$GENERATED"
		count=$((count + 1))
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

@test "every golden directory names a theme that exists" {
	local themes path name
	themes=$("$XGHOST" theme list)
	for path in "$GOLDEN_DIR"/*; do
		[ -d "$path" ]
		name=${path##*/}
		[[ $'\n'$themes$'\n' == *$'\n'"$name"$'\n'* ]]
	done
}

@test "the golden output of every theme holds every template" {
	local theme path relative
	while IFS= read -r theme; do
		while IFS= read -r path; do
			relative=${path#"$TEMPLATE_DIR/"}
			[ -f "$GOLDEN_DIR/$theme/$relative" ]
		done < <(find "$TEMPLATE_DIR" -type f)
	done < <("$XGHOST" theme list)
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
		"$source_dir/templates" "$source_dir/themes" "$project/"
	cp "$BATS_TEST_DIRNAME/regenerate-golden" "$project/tests/regenerate-golden"

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
		HOME="$BATS_TEST_TMPDIR/home" \
		"$project/tests/regenerate-golden" --update
	[ "$status" -eq 1 ]
	[[ $output == *"cannot render the theme 'broken'"* ]]
	[[ $output == *"tests/golden is unchanged."* ]]

	[ -f "$project/tests/golden/keep/marker" ]
	[ "$(cat "$project/tests/golden/keep/marker")" = reference ]
	[ ! -e "$project/tests/golden/tokyonight" ]
}
