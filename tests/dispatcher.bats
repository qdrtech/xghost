#!/usr/bin/env bats
#
# Unit tests for the xghost dispatcher.
#
# Every test runs the dispatcher against a fixture command directory and
# asserts external behaviour: what the dispatcher prints, which script it runs,
# and which exit status it returns. No test reaches into an internal function.
#
# The options of the 'run' command, such as '--separate-stderr', need
# bats-core 1.5.0 or later.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	VALID_DIR="$BATS_TEST_DIRNAME/fixtures/commands"
	MALFORMED_DIR="$BATS_TEST_DIRNAME/fixtures/commands-malformed"
	export XGHOST_COMMAND_DIR="$VALID_DIR"
}

# --- grouped help ----------------------------------------------------------

@test "no argument prints the usage line" {
	run "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output == *"Usage: xghost <group> <verb> [argument ...]"* ]]
}

@test "no argument groups the commands under their group name" {
	run "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output == *$'\nsystem\n'* ]]
	[[ $output == *$'\ntheme\n'* ]]
}

@test "help takes each summary from the metadata of the command" {
	run "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output == *"Set the active theme."* ]]
	[[ $output == *"List the available themes."* ]]
	[[ $output == *"Update the packages and xghost itself."* ]]
}

@test "help marks a command that needs elevated privileges" {
	run "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output == *"Update the packages and xghost itself.  (needs root)"* ]]
}

@test "help does not mark a command that needs no elevated privileges" {
	run "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output == *"Set the active theme."* ]]
	[[ $output != *"Set the active theme.  (needs root)"* ]]
}

@test "help hides an internal command" {
	run "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output != *"reload-cache"* ]]
	[[ $output != *"Rebuild the theme cache."* ]]
}

@test "help hides a group whose commands are all internal" {
	run "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output != *"hidden"* ]]
	[[ $output != *"Probe the display server."* ]]
}

@test "-h and --help print the same help as no argument" {
	run "$XGHOST"
	local plain=$output
	run "$XGHOST" -h
	[ "$status" -eq 0 ]
	[ "$output" = "$plain" ]
	run "$XGHOST" --help
	[ "$status" -eq 0 ]
	[ "$output" = "$plain" ]
}

# --- group help ------------------------------------------------------------

@test "a group name alone lists only the verbs of that group" {
	run "$XGHOST" theme
	[ "$status" -eq 0 ]
	[[ $output == *"Usage: xghost theme <verb> [argument ...]"* ]]
	[[ $output == *"set"* ]]
	[[ $output == *"list"* ]]
	[[ $output != *"update"* ]]
}

@test "an unknown group is reported" {
	run "$XGHOST" nosuchgroup
	[ "$status" -eq 127 ]
	[[ $output == *"unknown group 'nosuchgroup'"* ]]
}

# --- routing ---------------------------------------------------------------

@test "a group and a verb route to the matching command script" {
	run "$XGHOST" theme set nord
	[ "$status" -eq 0 ]
	[[ $output == "theme-set ran with: nord" ]]
}

@test "routing passes every argument through unchanged" {
	run "$XGHOST" theme set one two three
	[ "$status" -eq 0 ]
	[[ $output == "theme-set ran with: one two three" ]]
}

@test "routing reaches a verb that contains a hyphen" {
	run "$XGHOST" theme reload-cache
	[ "$status" -eq 0 ]
	[[ $output == "theme-reload-cache ran" ]]
}

@test "an internal command still routes" {
	run "$XGHOST" hidden probe
	[ "$status" -eq 0 ]
	[[ $output == "hidden-probe ran" ]]
}

@test "the exit status of the command reaches the caller" {
	run "$XGHOST" system check
	[ "$status" -eq 3 ]
	[[ $output == "system-check ran" ]]
}

@test "an unknown verb is reported with its group" {
	run "$XGHOST" theme nosuchverb
	[ "$status" -eq 127 ]
	[[ $output == *"unknown verb 'nosuchverb' in group 'theme'"* ]]
}

@test "a group name with a path separator does not escape the command directory" {
	run "$XGHOST" ../etc passwd
	[ "$status" -eq 127 ]
	[[ $output == *"unknown group '../etc'"* ]]
}

# --- command detail --------------------------------------------------------

@test "command help builds the usage line from the argument metadata" {
	run "$XGHOST" theme set --help
	[ "$status" -eq 0 ]
	[[ $output == *"Usage: xghost theme set NAME"* ]]
}

@test "command help lists the arguments from the metadata" {
	run "$XGHOST" theme set --help
	[ "$status" -eq 0 ]
	[[ $output == *"Arguments:"* ]]
	[[ $output == *"NAME"* ]]
	[[ $output == *"The theme to activate."* ]]
}

@test "command help shows the examples from the metadata" {
	run "$XGHOST" theme set --help
	[ "$status" -eq 0 ]
	[[ $output == *"Examples:"* ]]
	[[ $output == *"xghost theme set nord"* ]]
}

@test "command help states that a command needs elevated privileges" {
	run "$XGHOST" system update --help
	[ "$status" -eq 0 ]
	[[ $output == *"This command needs elevated privileges."* ]]
}

@test "command help omits the argument section when the command takes none" {
	run "$XGHOST" theme list --help
	[ "$status" -eq 0 ]
	[[ $output != *"Arguments:"* ]]
}

# --- metadata problems are reported ----------------------------------------

@test "lint reports no problem for a sound command directory" {
	run "$XGHOST" --lint
	[ "$status" -eq 0 ]
	[[ $output == *"6 command files, no metadata problem"* ]]
}

@test "lint ignores a dot file in the command directory" {
	[ -e "$VALID_DIR/.gitkeep" ]
	run "$XGHOST" --lint
	[ "$status" -eq 0 ]
	[[ $output != *".gitkeep"* ]]
}

@test "lint exits non-zero when a command has a metadata problem" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"7 of 8 command files have a metadata problem"* ]]
}

@test "lint reports a missing metadata block" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"bad-nometa: no metadata block"* ]]
}

@test "lint reports a metadata block without a summary" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"bad-nosummary: the metadata block has no 'summary' key"* ]]
}

@test "lint reports an unknown metadata key with its line number" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"bad-unknownkey: line 4: unknown key 'colour'"* ]]
}

@test "lint reports a flag that is neither yes nor no" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"bad-elevated: line 4: 'elevated' takes 'yes' or 'no', found 'maybe'"* ]]
}

@test "lint reports a command file that is not executable" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"bad-notexecutable: the file is not executable"* ]]
}

@test "lint reports a file name that is not group and verb" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"nohyphen: the file name must be <group>-<verb>"* ]]
}

@test "lint reports an entry that is not a regular file" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"subgroup: not a regular file"* ]]
}

@test "help warns on standard error about a malformed command" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run --separate-stderr "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $stderr == *"bad-nometa: no metadata block"* ]]
	[[ $output != *"bad-nometa"* ]]
}

@test "help still lists the sound commands beside a malformed one" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run --separate-stderr "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output == *"A command whose metadata is correct."* ]]
}

@test "routing warns about malformed metadata and still runs the command" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run --separate-stderr "$XGHOST" bad nometa
	[ "$status" -eq 0 ]
	[[ $output == "bad-nometa ran" ]]
	[[ $stderr == *"bad-nometa: no metadata block"* ]]
}

@test "routing refuses to run a command file that is not executable" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" bad notexecutable
	[ "$status" -eq 126 ]
	[[ $output == *"cannot run 'bad notexecutable'"* ]]
}

@test "command help refuses to describe a command with a metadata problem" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" bad elevated --help
	[ "$status" -eq 1 ]
	[[ $output == *"cannot describe 'bad elevated'"* ]]
}

@test "a missing command directory is reported" {
	XGHOST_COMMAND_DIR="$BATS_TEST_TMPDIR/absent" run "$XGHOST"
	[ "$status" -eq 1 ]
	[[ $output == *"the command directory does not exist"* ]]
}

# --- completion ------------------------------------------------------------

@test "--complete-groups lists every visible group once, sorted" {
	run "$XGHOST" --complete-groups
	[ "$status" -eq 0 ]
	[ "$output" = "system
theme" ]
}

@test "--complete-groups omits a group whose commands are all internal" {
	run "$XGHOST" --complete-groups
	[ "$status" -eq 0 ]
	[[ $output != *"hidden"* ]]
}

@test "--complete-verbs prints the verb and its summary for one group" {
	run "$XGHOST" --complete-verbs theme
	[ "$status" -eq 0 ]
	[ "$output" = "list:List the available themes.
set:Set the active theme." ]
}

@test "--complete-verbs omits an internal verb" {
	run "$XGHOST" --complete-verbs theme
	[ "$status" -eq 0 ]
	[[ $output != *"reload-cache"* ]]
}

@test "--complete-verbs prints nothing for an unknown group" {
	run "$XGHOST" --complete-verbs nosuchgroup
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "--complete-verbs without a group is a usage error" {
	run "$XGHOST" --complete-verbs
	[ "$status" -eq 2 ]
	[[ $output == *"needs a group name"* ]]
}

@test "completion output stays clean when a command is malformed" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run --separate-stderr "$XGHOST" --complete-groups
	[ "$status" -eq 0 ]
	[ "$output" = "good" ]
	[[ $stderr == *"bad-nometa"* ]]
}

# --- options ---------------------------------------------------------------

@test "an unknown option is reported" {
	run "$XGHOST" --nosuchoption
	[ "$status" -eq 2 ]
	[[ $output == *"unknown option '--nosuchoption'"* ]]
}
