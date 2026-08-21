#!/usr/bin/env bash
#
# The one thing that is true of every suite: nothing here reloads a desktop.
#
# lib/reload.sh is what a render now ends with, so 'xghost theme set' and
# 'xghost settings set' signal the running components. Eighteen suites of this
# project run one of those two commands, most of them for a reason that has
# nothing to do with the reload, and the machine this desktop is developed on
# runs a live Hyprland, a live bar, a live notification centre and a live
# terminal. Without this file, one run of 'bats tests' reloads all four, once
# per test.
#
# So the reload is off for the whole suite, and the two suites that mean to
# exercise it turn it back on for themselves after they have put a stub of
# every program it can reach first on the PATH. tests/reload.bats and
# tests/update.bats are those two, and each one asserts the stubs are first
# before any test body runs.
#
# This is the safe default rather than the convenient one. A suite written later
# is covered by it without doing anything, and a suite that wants the reload has
# to say so in the same breath as it installs its stubs.
#
# bats loads this file once per run, and an export made here reaches every test
# of every file, including a run of one file and a run filtered with '-f'. That
# last form is what tests/negative-control uses.

setup_suite() {
	export XGHOST_RELOAD=no
}
