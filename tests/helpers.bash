#!/usr/bin/env bash
#
# Shared helpers for the bats suites.
#
# This file holds what more than one suite needs. A suite sources it from its
# own setup(). It is not a test file, so 'bats tests' never collects it.

# Give the commands the fixed machine facts under tests/fixtures/machine.
#
# A template may make a structural choice from a machine fact, and the renderer
# then needs that fact before it can write anything at all. The Hyprland bundle
# is the first to do it: the monitor layout and the workspace assignment are
# both chosen by MACHINE_MONITOR_COUNT. A render of the shipped templates
# therefore fails, by name, on a machine that has never run 'xghost machine
# detect'.
#
# The consequence reaches every suite, not only the suite of the bundle that
# added the template. A suite that renders a shipped theme needs machine facts
# even when it asserts nothing about a monitor, because the render is what it
# depends on. tests/renderer.bats and tests/ghostty.bats are both in that
# position, and each later bundle puts one more suite there.
#
# The facts are the fixed ones the golden output is built from, so every suite
# renders the same machine and no assertion depends on the hardware that ran
# the tests. tests/regenerate-golden reads the same file.
#
# The commands are pointed at a copy of the fixture, never at the fixture
# itself. 'xghost machine detect' writes the path XGHOST_MACHINE_FACTS names,
# and it leaves a '.previous' copy beside it, so a suite that ever runs that
# command against the fixture itself would rewrite a committed file and drop an
# untracked one into the working tree. No suite runs it today. The copy is what
# keeps that true of every suite written later.
#
# Call this from setup(). A suite that proves the behaviour when facts are
# absent does not call it, and writes facts of its own instead:
# tests/hyprland.bats and tests/facts.bats both do that.
use_fixed_machine_facts() {
	local facts=$BATS_TEST_DIRNAME/fixtures/machine/golden.conf
	local copy=$BATS_TEST_TMPDIR/machine.conf

	# A fixture that moved would otherwise reach the suite as a render error
	# that names a missing fact, which sends the reader to the templates rather
	# than to this file.
	if [ ! -f "$facts" ]; then
		printf 'the fixed machine facts are missing: %s\n' "$facts" >&2
		return 1
	fi
	if ! cp -- "$facts" "$copy"; then
		printf 'cannot copy the fixed machine facts to %s\n' "$copy" >&2
		return 1
	fi

	export XGHOST_MACHINE_FACTS=$copy
}

# Give the commands a knobs file of this test, at a path that holds no file.
#
# The knobs are the third input of the renderer, and an absent file means every
# knob takes the default of the schema. That is what a machine which has never
# run 'xghost settings set' renders with, and it is the state every suite wants
# unless it says otherwise: without this, a knobs file in the config directory
# of whoever runs the suite would reach the render and change what it produces.
#
# A test that wants a knob at another value writes the file this names, or runs
# 'xghost settings set'. The schema stays the shipped one, because the project
# owns it and a test of a schema of its own would prove nothing about the knobs
# this desktop offers.
#
# Call this from setup().
use_own_knobs() {
	export XGHOST_KNOBS_FILE=$BATS_TEST_TMPDIR/knobs.conf
	unset XGHOST_KNOBS_SCHEMA
}
