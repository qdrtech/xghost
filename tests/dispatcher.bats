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

# Write one command file from standard input into a command directory of its
# own, and print the path of that directory. The argument is the file name, so
# it carries the group and the verb.
#
# A file whose content or permission bits cannot be committed to git, such as a
# file the dispatcher may not read, belongs here rather than in fixtures/.
make_command_dir() {
	local name=$1
	local dir="$BATS_TEST_TMPDIR/$name.d"
	mkdir -p "$dir"
	cat >"$dir/$name"
	chmod +x "$dir/$name"
	printf '%s\n' "$dir"
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

# --- the dispatcher owns -h and --help in two positions ---------------------

@test "--help in the verb position prints the group help" {
	run "$XGHOST" theme
	local group_help=$output
	run "$XGHOST" theme --help
	[ "$status" -eq 0 ]
	[ "$output" = "$group_help" ]
}

@test "-h in the verb position prints the group help" {
	run "$XGHOST" theme
	local group_help=$output
	run "$XGHOST" theme -h
	[ "$status" -eq 0 ]
	[ "$output" = "$group_help" ]
}

@test "--help in the verb position of an unknown group is reported" {
	run "$XGHOST" nosuchgroup --help
	[ "$status" -eq 127 ]
	[[ $output == *"unknown group 'nosuchgroup'"* ]]
}

@test "-h in the first argument position prints the same command help as --help" {
	run "$XGHOST" theme set --help
	local command_help=$output
	run "$XGHOST" theme set -h
	[ "$status" -eq 0 ]
	[ "$output" = "$command_help" ]
}

@test "--help after the first argument reaches the command unchanged" {
	run "$XGHOST" theme set nord --help
	[ "$status" -eq 0 ]
	[ "$output" = "theme-set ran with: nord --help" ]
}

@test "-h after the first argument reaches the command unchanged" {
	run "$XGHOST" theme set nord -h
	[ "$status" -eq 0 ]
	[ "$output" = "theme-set ran with: nord -h" ]
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
	[[ $output == *"8 of 9 command files have a metadata problem"* ]]
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

@test "lint reports a broken symbolic link" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"bad-brokenlink: a broken symbolic link"* ]]
}

@test "routing reports a broken symbolic link and refuses to run it" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run --separate-stderr "$XGHOST" bad brokenlink
	[ "$status" -eq 126 ]
	[[ $stderr == *"bad-brokenlink: a broken symbolic link"* ]]
	[[ $stderr == *"cannot run 'bad brokenlink'"* ]]
}

@test "help leaves a broken symbolic link out and warns about it" {
	XGHOST_COMMAND_DIR="$MALFORMED_DIR" run --separate-stderr "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output != *"brokenlink"* ]]
	[[ $stderr == *"bad-brokenlink: a broken symbolic link"* ]]
}

@test "lint reports a command file it cannot read" {
	if [ "$(id -u)" -eq 0 ]; then
		skip "root reads a file whatever its permission bits are"
	fi
	local dir="$BATS_TEST_TMPDIR/unreadable"
	mkdir -p "$dir"
	cp "$VALID_DIR/theme-list" "$dir/theme-list"
	chmod 111 "$dir/theme-list"
	XGHOST_COMMAND_DIR="$dir" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"theme-list: the file cannot be read"* ]]
	[[ $output != *"Permission denied"* ]]
	[[ $output != *"no metadata block"* ]]
}

@test "lint does not pass when the command directory holds no entry" {
	mkdir -p "$BATS_TEST_TMPDIR/empty"
	XGHOST_COMMAND_DIR="$BATS_TEST_TMPDIR/empty" run "$XGHOST" --lint
	[ "$status" -eq 3 ]
	[[ $output == *"no command file to check"* ]]
}

@test "lint does not pass when the command directory holds only a dot file" {
	mkdir -p "$BATS_TEST_TMPDIR/dotonly"
	touch "$BATS_TEST_TMPDIR/dotonly/.gitkeep"
	XGHOST_COMMAND_DIR="$BATS_TEST_TMPDIR/dotonly" run "$XGHOST" --lint
	[ "$status" -eq 3 ]
	[[ $output == *"no command file to check"* ]]
}

# --- the metadata contract --------------------------------------------------

@test "lint reports a repeated key" {
	local dir
	dir=$(make_command_dir meta-repeat <<-'EOF'
		#!/usr/bin/env bash
		# @xghost-meta
		# summary: The first value.
		# summary: The second value.
		# @end-xghost-meta
		printf 'meta-repeat ran\n'
	EOF
	)
	XGHOST_COMMAND_DIR="$dir" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"line 4: 'summary' is given more than once"* ]]
}

@test "lint reports a second metadata block and still checks its keys" {
	local dir
	dir=$(make_command_dir meta-second <<-'EOF'
		#!/usr/bin/env bash
		# @xghost-meta
		# summary: A command that carries two metadata blocks.
		# @end-xghost-meta

		# @xghost-meta
		# colour: blue
		# @end-xghost-meta
		printf 'meta-second ran\n'
	EOF
	)
	XGHOST_COMMAND_DIR="$dir" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"line 6: a second metadata block starts here"* ]]
	[[ $output == *"line 7: unknown key 'colour'"* ]]
}

@test "lint reports a line in the block that is not a comment and checks the keys below it" {
	local dir strays
	dir=$(make_command_dir meta-stray <<-'EOF'
		#!/usr/bin/env bash
		# @xghost-meta
		# summary: A command whose block holds a line that is not a comment.
		printf 'first stray line\n'
		# colour: blue
		printf 'second stray line\n'
		# @end-xghost-meta
		printf 'meta-stray ran\n'
	EOF
	)
	XGHOST_COMMAND_DIR="$dir" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"line 4: the metadata block holds a line that is not a comment"* ]]
	[[ $output == *"line 5: unknown key 'colour'"* ]]
	strays=$(printf '%s\n' "$output" | grep -c 'is not a comment' || true)
	[ "$strays" -eq 1 ]
}

@test "lint reports a metadata block that carries no end marker" {
	local dir
	dir=$(make_command_dir meta-open <<-'EOF'
		#!/usr/bin/env bash
		# @xghost-meta
		# summary: A command whose block carries no end marker.
		printf 'meta-open ran\n'
	EOF
	)
	XGHOST_COMMAND_DIR="$dir" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"the metadata block is not closed with '# @end-xghost-meta'"* ]]
}

@test "lint reports a summary that holds a tab" {
	local dir
	dir=$(printf '#!/usr/bin/env bash\n# @xghost-meta\n# summary: A summary with a\ttab.\n# @end-xghost-meta\nprintf "meta-tab ran\\n"\n' |
		make_command_dir meta-tab)
	XGHOST_COMMAND_DIR="$dir" run "$XGHOST" --lint
	[ "$status" -eq 1 ]
	[[ $output == *"line 3: 'summary' holds a control character"* ]]
}

@test "a summary that holds a tab never reaches the help output" {
	local dir
	dir=$(printf '#!/usr/bin/env bash\n# @xghost-meta\n# summary: A summary with a\ttab.\n# @end-xghost-meta\nprintf "meta-tab ran\\n"\n' |
		make_command_dir meta-tab)
	XGHOST_COMMAND_DIR="$dir" run --separate-stderr "$XGHOST"
	[ "$status" -eq 0 ]
	[[ $output != *"A summary with a"* ]]
	[[ $stderr == *"holds a control character"* ]]
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

@test "an empty group name is a usage error" {
	run "$XGHOST" ""
	[ "$status" -eq 2 ]
	[[ $output == *"the group name is empty"* ]]
}

@test "an empty group name before a verb is a usage error" {
	run "$XGHOST" "" list
	[ "$status" -eq 2 ]
	[[ $output == *"the group name is empty"* ]]
}

# --- shell options from the environment -------------------------------------

@test "dotglob in the environment does not turn a dot file into a command" {
	run env BASHOPTS=dotglob "$XGHOST" --lint
	[ "$status" -eq 0 ]
	[[ $output == *"6 command files, no metadata problem"* ]]
	[[ $output != *".gitkeep"* ]]
}

@test "noglob in the environment does not hide the command files" {
	run env SHELLOPTS=noglob "$XGHOST" --lint
	[ "$status" -eq 0 ]
	[[ $output == *"6 command files, no metadata problem"* ]]
}

@test "failglob in the environment does not break the empty directory case" {
	mkdir -p "$BATS_TEST_TMPDIR/failglob"
	XGHOST_COMMAND_DIR="$BATS_TEST_TMPDIR/failglob" run env BASHOPTS=failglob "$XGHOST" --lint
	[ "$status" -eq 3 ]
	[[ $output == *"no command file to check"* ]]
}

@test "nocaseglob in the environment does not change which files are commands" {
	run env BASHOPTS=nocaseglob "$XGHOST" --lint
	[ "$status" -eq 0 ]
	[[ $output == *"6 command files, no metadata problem"* ]]
}
