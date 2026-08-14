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

	# The renderer writes under the state directory of the user, so each test
	# gets a home of its own and touches nothing outside it.
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_STATE_HOME="$HOME/.local/state"
	mkdir -p "$XDG_STATE_HOME"

	# The fixed machine facts of the golden output, which ADR 0001 names as the
	# second input of these tests. tests/regenerate-golden reads the same file,
	# so the committed output never depends on the hardware of whoever runs it.
	MACHINE_FACTS="$BATS_TEST_DIRNAME/fixtures/machine/golden.conf"
	export XGHOST_MACHINE_FACTS="$MACHINE_FACTS"

	GENERATED="$XDG_STATE_HOME/xghost/generated"
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
			relative=$(output_path "${path#"$TEMPLATE_DIR/"}")
			[ -f "$GOLDEN_DIR/$theme/$relative" ]
		done < <(find "$TEMPLATE_DIR" -type f)
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
		"$source_dir/templates" "$source_dir/themes" "$project/"
	cp "$BATS_TEST_DIRNAME/regenerate-golden" "$project/tests/regenerate-golden"

	# The script reads the fixed machine facts, and it stops when they are
	# missing. The copy needs them, so the failure this test asserts on is the
	# theme that cannot render and nothing else.
	mkdir -p "$project/tests/fixtures/machine"
	cp "$MACHINE_FACTS" "$project/tests/fixtures/machine/golden.conf"

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
