#!/usr/bin/env bats
#
# Tests for the shell bundle: the prescribed zsh configuration under
# config/zsh, the prescribed tmux configuration under config/tmux, the starship
# template under templates/starship, and the install step that points zsh at
# the first of them.
#
# The tests that need zsh, tmux or starship skip cleanly when the program is
# absent, because continuous integration has none of the three.
#
# Two rules hold for every test in this file, and both exist because the
# machine that runs the suite is a machine somebody is using:
#
#   - No test writes a real dotfile. HOME, XDG_CONFIG_HOME, XDG_STATE_HOME,
#     XDG_CACHE_HOME and ZDOTDIR all point inside BATS_TEST_TMPDIR, so a zsh
#     started here reads the prescribed file of this checkout and nothing of
#     the person running the suite.
#   - No tmux command touches the default socket. Every one of them names a
#     socket file inside BATS_TEST_TMPDIR with '-S', and the server on it is
#     killed by that same path. A bare 'tmux kill-server' would end the
#     sessions of whoever is running the tests.
#
# The design of the bundle is recorded in docs/bundles/shell.md.
bats_require_minimum_version 1.5.0

setup() {
	XGHOST="$BATS_TEST_DIRNAME/../bin/xghost"
	ROOT_DIR="$BATS_TEST_DIRNAME/.."
	ZSHRC="$ROOT_DIR/config/zsh/.zshrc"
	TMUX_CONF="$ROOT_DIR/config/tmux/tmux.conf"
	STARSHIP_TEMPLATE="$ROOT_DIR/templates/starship/starship.toml"
	SHELL_STEP="$ROOT_DIR/install/steps/config/40-shell.sh"

	# shellcheck source=helpers.bash
	. "$BATS_TEST_DIRNAME/helpers.bash"

	export XGHOST_COMMAND_DIR="$ROOT_DIR/commands"

	# Every path the commands read comes from this setup, so an override that
	# the person running the suite happens to export reaches no command.
	unset XGHOST_CONFIG_HOME
	unset XGHOST_STATE_DIR
	unset XGHOST_BACKUP_DIR
	unset XGHOST_CONFIG_SOURCE
	unset XGHOST_ROOT
	unset XGHOST_THEMES_DIR
	unset XGHOST_TEMPLATE_DIR
	unset ZDOTDIR
	unset STARSHIP_CONFIG

	export HOME="$BATS_TEST_TMPDIR/home"

	# None of the three is the default the XDG specification gives it, and that
	# is deliberate. A test that compared an expansion against $XDG_CONFIG_HOME
	# while that variable held "$HOME/.config" would pass whether the line it
	# read expanded the variable or fell back to the default, because the two
	# are the same string. Every assertion in this file that reads one of these
	# paths is able to tell the two apart because of these three lines.
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg-config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg-state"
	export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/xdg-cache"
	mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

	use_fixed_machine_facts
	use_own_knobs

	GENERATED="$XDG_STATE_HOME/xghost/generated"

	# The private tmux socket of this test. Nothing here ever runs tmux
	# without it.
	TMUX_SOCKET="$BATS_TEST_TMPDIR/tmux.sock"

	# The name 'xghost config link' gives the generated output inside the
	# config directory.
	BRIDGE_NAME=xghost-generated
}

teardown() {
	# The server this test may have started, and no other. A socket path that
	# holds no server makes this a no-op.
	if [ -n "${TMUX_SOCKET:-}" ] && [ -S "$TMUX_SOCKET" ]; then
		tmux -S "$TMUX_SOCKET" kill-server 2>/dev/null || true
	fi
}

# Link the prescribed configuration of the checkout into the config directory.
link_prescribed() {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config link
}

unlink_prescribed() {
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config unlink "$@"
}

# Remove every startup file of zsh from the temporary home directory of this
# test, so that a case of the install step is driven from a known state.
clear_zsh_startup_files() {
	rm -f -- "$HOME/.zshenv" "$HOME/.zshrc" "$HOME/.zprofile" \
		"$HOME/.zlogin" "$HOME/.zlogout"
}

# Print the value one theme declares for one palette name.
palette_value() {
	local theme=$1 name=$2
	sed -n "s/^$name=//p" "$ROOT_DIR/themes/$theme/palette.conf"
}

# Print the every line of a file that is not a whole-line comment.
without_comments() {
	grep -v '^[[:space:]]*#' "$1"
}

# Print the STARSHIP_CONFIG line of one file, whole.
#
# The line is read out of the file rather than written again here, so a change
# to the file is what the tests below resolve. An empty result is a failure: a
# file that stopped carrying the line must fail a test rather than hand an empty
# string to the next assertion.
starship_config_line() {
	local line
	line=$(grep -m1 '^export STARSHIP_CONFIG=' "$1") || return 1
	[ -n "$line" ] || return 1
	printf '%s\n' "$line"
}

# Expand the STARSHIP_CONFIG line of one file the way a shell expands it, in the
# environment of this test.
starship_config_from() {
	local line
	line=$(starship_config_line "$1") || return 1
	(
		eval "$line"
		printf '%s\n' "$STARSHIP_CONFIG"
	)
}

# The prescribed zshrc, which is the copy an interactive shell reads.
starship_config_from_zshrc() {
	starship_config_from "$ZSHRC"
}

# The ~/.zshenv the install step writes, which is the copy every other zsh
# reads. The step has to have run for this to resolve.
starship_config_from_zshenv() {
	starship_config_from "$HOME/.zshenv"
}

# Run the install step of this bundle the way lib/install.sh runs one: in a
# shell of its own that sources the module first.
run_shell_step() {
	XGHOST_INSTALL_LIB="$ROOT_DIR/lib/install.sh" \
		XGHOST_INSTALL_STEP="$SHELL_STEP" \
		INSTALL_DRY_RUN="${INSTALL_DRY_RUN:-no}" \
		bash -c 'set -euo pipefail
. "$XGHOST_INSTALL_LIB"
install_paths
. "$XGHOST_INSTALL_STEP"'
}

require_program() {
	if ! command -v "$1" >/dev/null 2>&1; then
		skip "$1 is not installed"
	fi
}

# Start the private tmux server of this test on the configuration file given.
start_private_tmux() {
	tmux -S "$TMUX_SOCKET" -f "$1" new-session -d -s probe /bin/sh
}

tmux_option() {
	tmux -S "$TMUX_SOCKET" show-options -gqv "$1"
}

# Print the command one key is bound to, in one key table.
#
# 'list-keys' pads its columns to the widest entry of the table it prints, so
# the width depends on the other keys in that table and on the version of tmux.
# awk splits on runs of white space, so nothing here reads a column position,
# and the key is compared as a whole string rather than as a pattern.
key_command() {
	local table=$1 key=$2
	tmux -S "$TMUX_SOCKET" list-keys -T "$table" | awk -v t="$table" -v k="$key" '
		$1 == "bind-key" && $2 == "-T" && $3 == t && $4 == k {
			out = ""
			for (i = 5; i <= NF; i++) {
				out = out (i > 5 ? " " : "") $i
			}
			print out
		}'
}

# Print every prefix key that is bound to a bare split, one per line, sorted.
#
# This reads the commands rather than the keys, so it says nothing about how a
# version of tmux writes '%' or '"' in a listing. A key the prescribed file
# does not unbind appears here, which is what makes the assertion able to fail.
split_keys() {
	tmux -S "$TMUX_SOCKET" list-keys -T prefix | awk '
		$1 == "bind-key" && $2 == "-T" && $3 == "prefix" {
			cmd = ""
			for (i = 5; i <= NF; i++) {
				cmd = cmd (i > 5 ? " " : "") $i
			}
			if (cmd == "split-window -h" || cmd == "split-window -v") {
				print $4
			}
		}' | sort
}

# Print the shell the prescribed tmux configuration names.
#
# An empty result is a failure rather than an empty string. Two tests below skip
# when the path this prints is not executable, and without this guard a file
# that stopped naming a shell at all would print nothing, fail the '-x' test,
# and skip: the deletion of the line would be reported as a machine that lacks
# the shell. run_reload_binding() and starship_config_line() carry the same
# guard for the same reason.
prescribed_default_shell() {
	local shell
	shell=$(sed -n 's/^set -g default-shell //p' "$TMUX_CONF")
	[ -n "$shell" ] || return 1
	printf '%s\n' "$shell"
}

# Run the command the reload binding runs, in the private server of this test.
#
# The command is taken out of the binding rather than written again here, so a
# change to the prescribed file is what these tests resolve.
run_reload_binding() {
	local command
	command=$(sed -n 's/^bind r run-shell //p' "$TMUX_CONF")
	[ -n "$command" ] || return 1
	eval "tmux -S \"\$TMUX_SOCKET\" run-shell $command"
}

#
# The prescribed files.
#

@test "the zsh and tmux configuration is prescribed configuration" {
	[ -f "$ZSHRC" ]
	[ -f "$TMUX_CONF" ]
	[ ! -L "$ROOT_DIR/config/zsh" ]
	[ ! -L "$ROOT_DIR/config/tmux" ]
}

@test "'config link' places both prescribed directories as symbolic links" {
	run -0 link_prescribed
	[ -L "$XDG_CONFIG_HOME/zsh" ]
	[ "$(readlink "$XDG_CONFIG_HOME/zsh")" = "$ROOT_DIR/config/zsh" ]
	[ -f "$XDG_CONFIG_HOME/zsh/.zshrc" ]
	[ -L "$XDG_CONFIG_HOME/tmux" ]
	[ "$(readlink "$XDG_CONFIG_HOME/tmux")" = "$ROOT_DIR/config/tmux" ]
	[ -f "$XDG_CONFIG_HOME/tmux/tmux.conf" ]
}

@test "'config unlink' removes both links again" {
	run -0 link_prescribed
	run -0 unlink_prescribed
	[ ! -e "$XDG_CONFIG_HOME/zsh" ]
	[ ! -e "$XDG_CONFIG_HOME/tmux" ]
}

@test "the prescribed zsh configuration is a file zsh parses" {
	require_program zsh
	run -0 zsh -n "$ZSHRC"
}

#
# What was left behind in the dotfiles.
#
# The bundle carries the shell of the desktop and nothing of the person who
# wrote the dotfiles it came from. docs/bundles/shell.md lists every line and
# its reason; this test is the guard that keeps one from coming back.
#

@test "no prescribed file and no template carries personal or work-specific content" {
	local file marker
	local -a markers=(
		amazonaws docker-login-ecr get-caller-identity '[aws]' '$aws'
		term-startup.sh git-prune.sh gitprune
		figlet fastfetch
		'.config/scripts' DOTFILES_DIR 'theme-switch.sh'
		'alias ts=' 'cache/wal' FZF_DEFAULT_COMMAND
		NVM_DIR BUN_INSTALL PNPM_HOME FLYCTL_INSTALL '.opencode'
		tmux-plugins tpm continuum resurrect
		'.histfile' 'ls -G' 'zstyle :compinstall'
	)
	for file in "$ZSHRC" "$TMUX_CONF" "$STARSHIP_TEMPLATE"; do
		for marker in "${markers[@]}"; do
			if without_comments "$file" | grep -qF -- "$marker"; then
				printf '%s carries %s, which the dotfiles keep\n' \
					"${file#"$ROOT_DIR/"}" "$marker" >&2
				return 1
			fi
		done
	done
}

@test "the 'ts' alias is gone and the command that replaces it runs by name" {
	run -1 grep -q 'alias ts=' "$ZSHRC"

	# 'xghost theme set' is the replacement, and it runs by name only when the
	# directory the installer links the command into is on the PATH.
	run -0 grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$ZSHRC"
}

#
# The prompt, and the path that reaches it.
#

@test "the starship template names every colour the themes declare" {
	local theme name count=0
	while IFS= read -r theme; do
		while IFS= read -r name; do
			run -0 grep -q "@$name@" "$STARSHIP_TEMPLATE"
			count=$((count + 1))
		done < <(sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' "$ROOT_DIR/themes/$theme/palette.conf")
	done < <("$XGHOST" theme list)
	[ "$count" -gt 0 ]
}

@test "every colour of the prompt is a colour of the active theme" {
	local theme name value count=0
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		while IFS= read -r name; do
			value=$(palette_value "$theme" "$name")
			run -0 grep -Fq "\"$value\"" "$GENERATED/starship/starship.toml"
			count=$((count + 1))
		done < <(sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' "$ROOT_DIR/themes/$theme/palette.conf")
		run -1 grep -qE '@[A-Z][A-Z0-9_]*@' "$GENERATED/starship/starship.toml"
	done < <("$XGHOST" theme list)

	# A theme list that printed nothing, or a palette file that stopped being
	# read, would run neither loop and reach this line having asserted nothing.
	# The test above this one carries the same guard.
	[ "$count" -gt 0 ]
}

# starship renders a module only when the format string names it. Four sections
# of this template were named by nothing, so they set a colour and a symbol that
# starship never reached, and the colour table of docs/bundles/shell.md credited
# two palette names with a version string neither one ever drew.
@test "the format string of the prompt names every module the template configures" {
	local format section count=0
	format=$(sed -n '/^format = """/,/"""$/p' "$STARSHIP_TEMPLATE")
	[ -n "$format" ]

	while IFS= read -r section; do
		# A name with a dot is a sub-table of another section, or the palette,
		# and the format string names neither.
		case $section in
		*.*) continue ;;
		esac

		count=$((count + 1))
		[[ $format == *"\$$section"* ]] || {
			printf 'the template configures [%s] and the format string never names it, so starship renders none of it\n' \
				"$section" >&2
			return 1
		}
	done < <(sed -n 's/^\[\([a-z_.]*\)\]$/\1/p' "$STARSHIP_TEMPLATE")

	# A template whose section headers stopped matching would read no section
	# at all and pass the loop above.
	[ "$count" -gt 0 ]
}

@test "the prescribed zshrc names the generated prompt through the bridge" {
	run -0 link_prescribed
	run -0 "$XGHOST" theme set tokyonight

	local resolved
	resolved=$(starship_config_from_zshrc)
	[ "$resolved" = "$XDG_CONFIG_HOME/$BRIDGE_NAME/starship/starship.toml" ]
	[ -f "$resolved" ]
	[ "$(readlink -f "$resolved")" = "$(readlink -f "$GENERATED/starship/starship.toml")" ]
}

# The divergence ADR 0002 exists to prevent: a renderer that writes one path and
# an application that reads another, because one of the two variables moved.
@test "the prompt path is right when both XDG directories are moved" {
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/moved-config"
	export XDG_STATE_HOME="$BATS_TEST_TMPDIR/moved-state"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

	run -0 link_prescribed
	run -0 "$XGHOST" theme set tokyonight

	local resolved
	resolved=$(starship_config_from_zshrc)
	[ "$resolved" = "$XDG_CONFIG_HOME/$BRIDGE_NAME/starship/starship.toml" ]
	[ -f "$resolved" ]
	[ "$(readlink -f "$resolved")" = \
		"$(readlink -f "$XDG_STATE_HOME/xghost/generated/starship/starship.toml")" ]
}

# XDG_CONFIG_HOME is unset on most machines. The shell writes the default of
# the XDG base directory specification inline, which is the one thing ADR 0002
# records the shell as able to do.
@test "the prompt path is right when XDG_CONFIG_HOME is unset" {
	# setup() puts XDG_CONFIG_HOME somewhere that is not "$HOME/.config", so
	# the two assertions below are two different strings. They were the same
	# string while setup() used the default, and the second one could not fail.
	local config_home="$XDG_CONFIG_HOME"
	[ "$config_home" != "$HOME/.config" ]
	unset XDG_CONFIG_HOME

	local resolved
	resolved=$(starship_config_from_zshrc)

	# The inline default is what the path came from.
	[ "$resolved" = "$HOME/.config/$BRIDGE_NAME/starship/starship.toml" ]

	# And not the value the variable held, which is what a line that wrote
	# '$XDG_CONFIG_HOME' with no default would have produced, and what a line
	# that hard-coded the directory of this test would have produced too.
	[ "$resolved" != "$config_home/$BRIDGE_NAME/starship/starship.toml" ]
}

@test "starship reads the generated configuration without an error" {
	require_program starship
	run -0 "$XGHOST" theme set tokyonight

	local errors
	errors="$BATS_TEST_TMPDIR/starship.err"
	STARSHIP_CONFIG="$GENERATED/starship/starship.toml" \
		starship print-config >"$BATS_TEST_TMPDIR/starship.out" 2>"$errors"
	[ ! -s "$errors" ]
	run -0 grep -Fq "$(palette_value tokyonight ACCENT)" "$BATS_TEST_TMPDIR/starship.out"
}

# starship falls back to its own default prompt in silence when the file
# STARSHIP_CONFIG names is not there, so 'it started' proves nothing. The
# prescribed file reports that state itself, and this is that report.
@test "the shell reports a prompt configuration that is not rendered yet" {
	require_program zsh
	run -0 link_prescribed

	# Linked and not rendered, which is the state between the two install
	# steps.
	[ ! -e "$GENERATED/starship/starship.toml" ]

	run -0 env ZDOTDIR="$XDG_CONFIG_HOME/zsh" zsh -i -c 'true' </dev/null
	[[ $output == *"the generated starship configuration is missing"* ]]
	[[ $output == *"xghost theme set"* ]]
}

# The whole of criterion 5 of issue #15, proved by starting the shell the
# installation leaves behind. The zsh started here reads the prescribed file of
# this checkout, through a ZDOTDIR and a HOME inside the temporary directory of
# this test, and no file of the person running the suite.
@test "a new shell comes up with the prompt of the active theme" {
	require_program zsh
	require_program starship
	run -0 link_prescribed
	run -0 "$XGHOST" theme set tokyonight

	run -0 env ZDOTDIR="$XDG_CONFIG_HOME/zsh" zsh -i -c \
		'printf "%s\n" "$STARSHIP_CONFIG"; starship prompt' </dev/null
	[[ $output != *"the generated starship configuration is missing"* ]]
	[[ $output == *"$XDG_CONFIG_HOME/$BRIDGE_NAME/starship/starship.toml"* ]]

	# The prompt is drawn in the colours of the theme. starship writes a
	# truecolor escape per colour, so the accent of the palette is in the
	# output as its three decimal components.
	local hex red green blue
	hex=$(palette_value tokyonight ACCENT)
	red=$((16#${hex:1:2}))
	green=$((16#${hex:3:2}))
	blue=$((16#${hex:5:2}))
	[[ $output == *"$red;$green;$blue"* ]]
}

# The shell writes nothing into the checkout. compinit puts its dump file in
# ZDOTDIR unless it is told otherwise, and ZDOTDIR is the link into config/zsh.
@test "a shell that starts writes no file into the checkout" {
	require_program zsh
	run -0 link_prescribed
	run -0 "$XGHOST" theme set tokyonight

	run -0 env ZDOTDIR="$XDG_CONFIG_HOME/zsh" zsh -i -c 'true' </dev/null

	local path
	while IFS= read -r path; do
		printf 'the shell wrote %s into the checkout\n' "$path" >&2
		return 1
	done < <(find "$ROOT_DIR/config/zsh" -mindepth 1 ! -name '.zshrc')

	# The two paths it does write, and both are outside the checkout.
	#
	# The commands are piped in rather than given with '-c'. 'zsh -i -c true'
	# runs no command line, so it saves no history at all, and an assertion
	# that accepted the directory as well as the file was true whatever the
	# prescribed HISTFILE said: the 'mkdir' in that file creates the directory
	# before anything reads the setting.
	printf 'true\nexit\n' |
		env ZDOTDIR="$XDG_CONFIG_HOME/zsh" zsh -i >/dev/null 2>&1

	[ -f "$XDG_STATE_HOME/zsh/history" ]
	run -0 grep -qxF 'true' "$XDG_STATE_HOME/zsh/history"
	[ -f "$XDG_CACHE_HOME/zsh/zcompdump" ]

	# The two paths zsh and compinit use when the prescribed settings are not
	# read. Neither is written.
	[ ! -e "$HOME/.histfile" ]
	[ ! -e "$ROOT_DIR/config/zsh/.zcompdump" ]
}

#
# tmux. Every command here names the private socket of this test.
#

@test "tmux holds every setting of the prescribed configuration" {
	require_program tmux
	start_private_tmux "$TMUX_CONF"

	# Every setting here is a setting of tmux itself, so each one holds on any
	# machine that has tmux. 'default-shell' is not among them, because tmux
	# refuses a shell that is not on the machine. The two tests below cover it.
	[ "$(tmux_option mouse)" = on ]
	[ "$(tmux_option prefix)" = C-a ]
	[ "$(tmux_option base-index)" = 1 ]
	[ "$(tmux_option pane-base-index)" = 1 ]
	[ "$(tmux_option allow-rename)" = on ]
	[ "$(tmux -S "$TMUX_SOCKET" show-options -sqv escape-time)" = 0 ]
}

# The text of the setting, which is true on every machine, with tmux or
# without it. '/usr/bin/zsh' is where the Arch 'zsh' package puts the shell,
# and the manifest is what puts that package on the machine.
@test "the prescribed tmux configuration names the shell this desktop installs" {
	[ "$(prescribed_default_shell)" = /usr/bin/zsh ]

	# shellcheck source=lib/install.sh
	. "$ROOT_DIR/lib/install.sh"
	install_paths
	run -0 install_read_manifest "$ROOT_DIR/install/packages/base.txt"
	[[ $'\n'$output$'\n' == *$'\n'zsh$'\n'* ]]
}

# tmux refuses a 'default-shell' whose path is not executable, and it says
# nothing at all: the option keeps the value of $SHELL instead. So this test
# needs the shell to be on the machine, and it is the one test of this bundle
# that cannot be checked without the program it names.
#
# SHELL is set to something the prescribed file does not name, so the value
# read back proves that tmux read the line. Without that, the test passes on
# any machine whose owner already runs the shell, which is every machine this
# desktop is installed on and was how this test came to pass while proving
# nothing.
@test "tmux takes the shell of this desktop from the prescribed configuration" {
	require_program tmux
	local shell
	shell=$(prescribed_default_shell)
	if [ ! -x "$shell" ]; then
		skip "$shell is not on this machine, and tmux refuses a shell that is not there"
	fi
	[ "$shell" != /bin/sh ]

	SHELL=/bin/sh tmux -S "$TMUX_SOCKET" -f "$TMUX_CONF" \
		new-session -d -s probe /bin/sh
	[ "$(tmux_option default-shell)" = "$shell" ]
}

@test "tmux binds the four pane keys, both splits, and neither key they replace" {
	require_program tmux
	start_private_tmux "$TMUX_CONF"

	[ "$(key_command root M-h)" = "select-pane -L" ]
	[ "$(key_command root M-j)" = "select-pane -D" ]
	[ "$(key_command root M-k)" = "select-pane -U" ]
	[ "$(key_command root M-l)" = "select-pane -R" ]
	[ "$(key_command prefix C-a)" = "send-prefix" ]

	# Exactly two prefix keys split a pane, and they are the two this file
	# binds. A '%' or a '"' that the file stopped unbinding would be a third.
	[ "$(split_keys | tr '\n' ' ')" = "- | " ]
}

# The reload binding is the one line of this bundle that names its own path.
# tmux expands '$VAR' in a 'source-file' path and refuses '${VAR:-default}', so
# the path is expanded by a shell instead. This proves it with the config
# directory moved, which is the case a tmux-only path would get wrong.
#
# The assertion is on the settings the reload put back, and not on the status
# of the command. tmux reports a 'default-shell' that is not on the machine and
# carries on reading the rest of the file, so the status is 1 on a machine
# without the shell and 0 on a machine with it, while the file is read either
# way. The test below covers the status.
@test "the tmux reload binding re-reads the configuration with XDG_CONFIG_HOME moved" {
	require_program tmux
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/moved-config"
	mkdir -p "$XDG_CONFIG_HOME"
	run -0 link_prescribed

	start_private_tmux "$XDG_CONFIG_HOME/tmux/tmux.conf"

	# Two settings of the prescribed file, put to values that file never
	# names. The reload is what puts them back, so a binding that reached no
	# file fails here. Neither setting depends on a program being installed.
	tmux -S "$TMUX_SOCKET" set -g base-index 9
	tmux -S "$TMUX_SOCKET" set -g pane-base-index 9
	tmux -S "$TMUX_SOCKET" set -g prefix C-b
	[ "$(tmux_option base-index)" = 9 ]

	# The status is deliberately not asserted here. See the comment above.
	run run_reload_binding

	[ "$(tmux_option base-index)" = 1 ]
	[ "$(tmux_option pane-base-index)" = 1 ]
	[ "$(tmux_option prefix)" = C-a ]
}

# The other half of the binding. 'source-file' succeeds only when every line of
# the file is one this machine accepts, and the '&&' in the binding reaches
# 'display-message' only on that status. A machine without the prescribed shell
# gets the reload and no message, which is why this is a test of its own.
@test "the tmux reload binding ends well when the shell of this desktop is there" {
	require_program tmux
	local shell
	shell=$(prescribed_default_shell)
	if [ ! -x "$shell" ]; then
		skip "$shell is not on this machine, so 'source-file' reports that line"
	fi

	# The server keeps the environment it started in, and 'run-shell' hands
	# that environment to the shell, so the link has to be in place before the
	# server starts rather than after it.
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/moved-config"
	mkdir -p "$XDG_CONFIG_HOME"
	run -0 link_prescribed

	start_private_tmux "$XDG_CONFIG_HOME/tmux/tmux.conf"
	tmux -S "$TMUX_SOCKET" set -g base-index 9

	run -0 run_reload_binding
	[ "$(tmux_option base-index)" = 1 ]
}

#
# The install step that points zsh at the prescribed configuration.
#

@test "the step writes the ZDOTDIR line when the home directory holds neither file" {
	run -0 run_shell_step
	[[ $output == *"wrote $HOME/.zshenv"* ]]
	run -0 grep -Fxq 'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' "$HOME/.zshenv"

	# The line names the directory the linker links the prescribed zsh
	# configuration to.
	run -0 link_prescribed
	local resolved
	resolved=$( (eval "$(grep -m1 '^export ZDOTDIR=' "$HOME/.zshenv")"; printf '%s\n' "$ZDOTDIR") )
	[ "$resolved" = "$XDG_CONFIG_HOME/zsh" ]
	[ -f "$resolved/.zshrc" ]
}

@test "the step is idempotent" {
	run -0 run_shell_step
	local first
	first=$(cat "$HOME/.zshenv")

	run -0 run_shell_step
	[[ $output == *"already in place"* ]]
	[ "$(cat "$HOME/.zshenv")" = "$first" ]
}

@test "the step leaves a .zshenv of the user exactly as it is" {
	printf 'export MY_OWN=1\n' >"$HOME/.zshenv"

	run -0 run_shell_step
	[[ $output == *"is already there"* ]]
	[[ $output == *'export ZDOTDIR='* ]]
	[ "$(cat "$HOME/.zshenv")" = 'export MY_OWN=1' ]
}

@test "the step leaves a ZDOTDIR the user chose" {
	printf 'export ZDOTDIR=$HOME/my-zsh\n' >"$HOME/.zshenv"

	run -0 run_shell_step
	[[ $output == *"sets ZDOTDIR already"* ]]
	[ "$(cat "$HOME/.zshenv")" = 'export ZDOTDIR=$HOME/my-zsh' ]
}

# ZDOTDIR moves the file zsh reads, so a ~/.zshrc that is already there would
# stop being read. That is a shell configuration lost in silence, and this step
# reports it instead.
@test "the step refuses to orphan a .zshrc the user already has" {
	printf 'alias mine=true\n' >"$HOME/.zshrc"

	run -0 run_shell_step
	[[ $output == *"would stop zsh reading it"* ]]
	[ ! -e "$HOME/.zshenv" ]
	[ "$(cat "$HOME/.zshrc")" = 'alias mine=true' ]
}

@test "a dry run of the step changes nothing" {
	INSTALL_DRY_RUN=yes run -0 run_shell_step
	[[ $output == *"would: write $HOME/.zshenv"* ]]
	[ ! -e "$HOME/.zshenv" ]
}

# The temporary file is named by mktemp, so this reads the directory rather
# than one name. The name used to be fixed, and a test that knew it would go on
# passing over a step that had gone back to a fixed name.
@test "the step leaves no temporary file behind" {
	run -0 run_shell_step

	local path
	while IFS= read -r path; do
		printf 'the step left %s behind\n' "$path" >&2
		return 1
	done < <(find "$HOME" -maxdepth 1 -name '.zshenv.*')
}

# The one path in this project that writes a real dotfile. The temporary file
# used to be a fixed name beside ~/.zshenv, and a redirection follows a symbolic
# link: a link planted at that name sent the write and the chmod into the file
# at the far end, put ~/.zshenv there as a symbolic link into it, and let the
# step report success.
@test "the step writes through no symbolic link planted beside ~/.zshenv" {
	printf 'REAL CONTENT THE USER CARES ABOUT\n' >"$HOME/victim"
	ln -s "$HOME/victim" "$HOME/.zshenv.xghost-new"

	run -0 run_shell_step

	# The file at the far end of the link is exactly as it was.
	[ "$(cat "$HOME/victim")" = 'REAL CONTENT THE USER CARES ABOUT' ]

	# The link itself is left alone: the step follows it and removes it neither.
	[ -L "$HOME/.zshenv.xghost-new" ]
	[ "$(readlink "$HOME/.zshenv.xghost-new")" = "$HOME/victim" ]

	# And the step did its own work, at its own path, as a regular file.
	[ ! -L "$HOME/.zshenv" ]
	[ -f "$HOME/.zshenv" ]
	run -0 grep -Fxq 'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' \
		"$HOME/.zshenv"
}

# ZDOTDIR moves every startup file of zsh, not .zshrc alone. A PATH addition, an
# ssh-agent or a umask in .zprofile, .zlogin or .zlogout stops running at the
# next login, and the guard used to read .zshrc and nothing else.
@test "the step refuses to orphan any startup file that ZDOTDIR moves" {
	local base count=0
	for base in .zshrc .zprofile .zlogin .zlogout; do
		clear_zsh_startup_files
		printf 'umask 077\n' >"$HOME/$base"

		run -0 run_shell_step
		count=$((count + 1))

		# The file that was found is named, rather than the class of file.
		[[ $output == *"$HOME/$base is there"* ]]
		[[ $output == *"would stop zsh reading it"* ]]
		[ ! -e "$HOME/.zshenv" ]
		[ "$(cat "$HOME/$base")" = 'umask 077' ]
	done
	[ "$count" -eq 4 ]
}

# Refusing is right. The advice was not: there is nothing at the end of a
# dangling link to move out of it.
@test "the step reports a dangling ~/.zshrc without advice about what to keep" {
	ln -s "$HOME/nothing-is-here" "$HOME/.zshrc"

	run -0 run_shell_step
	[[ $output == *"points at a target that does not exist"* ]]
	[[ $output != *"move what you want to keep"* ]]
	[ ! -e "$HOME/.zshenv" ]
	[ -L "$HOME/.zshrc" ]
}

# The same shape at the other path: no line can be added to a directory, so
# "add this line to ~/.zshenv" was advice that could not be followed.
@test "the step reports a ~/.zshenv that is a directory and prints no line to add" {
	mkdir "$HOME/.zshenv"

	run -0 run_shell_step
	[[ $output == *"is a directory"* ]]
	[[ $output != *"add this line to"* ]]
	[[ $output != *"add these two lines to"* ]]
	[ -d "$HOME/.zshenv" ]
	[ -z "$(find "$HOME/.zshenv" -mindepth 1)" ]
}

# The step reports and carries on. install_fail is exit 1, which fails the run,
# and docs/installing.md says this step never fails the installation.
@test "the step reports a home directory it cannot write and ends well" {
	if [ "$(id -u)" -eq 0 ]; then
		skip "root writes a directory whatever the mode of that directory says"
	fi

	chmod 0555 "$HOME"
	run run_shell_step
	chmod 0755 "$HOME"

	[ "$status" -eq 0 ]
	[[ $output == *"cannot create a temporary file"* ]]
	[[ $output == *"the rest of the desktop is in place"* ]]
	[ ! -e "$HOME/.zshenv" ]
}

# The file of a run that wrote the ZDOTDIR line and no other. The step edits no
# file it did not write, so it reports the missing line rather than adding it.
@test "the step reports a ~/.zshenv that carries no STARSHIP_CONFIG line" {
	printf '%s\n' 'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' \
		>"$HOME/.zshenv"

	run -0 run_shell_step
	[[ $output == *"already in place"* ]]
	[[ $output == *"carries no STARSHIP_CONFIG line"* ]]
	[ "$(cat "$HOME/.zshenv")" = \
		'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' ]
}

@test "the step tells the reader that the first shell has an empty history" {
	run -0 run_shell_step
	[[ $output == *"empty history"* ]]
	[[ $output == *".histfile"* ]]

	# And nothing was migrated, which is what the report says.
	[ ! -e "$HOME/.histfile" ]
}

#
# STARSHIP_CONFIG outside an interactive shell.
#
# starship reads ~/.config/starship.toml and says nothing when the variable is
# unset, so a shell that does not read the prescribed .zshrc draws whatever that
# path holds. On a machine that used the dotfiles this bundle came from, it
# holds the prompt the old theme switcher wrote.
#

@test "the ~/.zshenv the step writes carries the STARSHIP_CONFIG line of the zshrc" {
	run -0 run_shell_step

	# The same text in both files. A path that diverged between the two would
	# be the divergence ADR 0002 exists to prevent, in the one line this bundle
	# writes twice.
	[ "$(starship_config_line "$HOME/.zshenv")" = "$(starship_config_line "$ZSHRC")" ]
}

@test "the ~/.zshenv line resolves to the generated prompt through the bridge" {
	run -0 run_shell_step
	run -0 link_prescribed
	run -0 "$XGHOST" theme set tokyonight

	local resolved
	resolved=$(starship_config_from_zshenv)
	[ "$resolved" = "$XDG_CONFIG_HOME/$BRIDGE_NAME/starship/starship.toml" ]
	[ -f "$resolved" ]
	[ "$(readlink -f "$resolved")" = \
		"$(readlink -f "$GENERATED/starship/starship.toml")" ]
}

@test "STARSHIP_CONFIG is set in a zsh that never reads the prescribed zshrc" {
	require_program zsh
	run -0 run_shell_step
	run -0 link_prescribed
	run -0 "$XGHOST" theme set tokyonight

	local expected="$XDG_CONFIG_HOME/$BRIDGE_NAME/starship/starship.toml"

	# zsh reads .zshrc for an interactive shell alone, so neither of these two
	# reads it. Both read ~/.zshenv, which is why the line is there. Both
	# printed UNSET while the line was in the prescribed .zshrc alone.
	[ "$(zsh -c 'printf "%s\n" "${STARSHIP_CONFIG:-UNSET}"' 2>/dev/null)" = "$expected" ]
	[ "$(zsh -l -c 'printf "%s\n" "${STARSHIP_CONFIG:-UNSET}"' 2>/dev/null)" = "$expected" ]

	# And the interactive shell, which reads both files, still resolves it.
	[ "$(zsh -i -c 'printf "%s\n" "${STARSHIP_CONFIG:-UNSET}"' </dev/null 2>/dev/null)" \
		= "$expected" ]
}

# Why the line is in ~/.zshenv rather than in a prescribed file of the bundle.
# Both candidates were tried, and this is what zsh does with each of them.
@test "zsh reads no .zshenv from ZDOTDIR, and reads .zprofile for a login shell alone" {
	require_program zsh
	local zdotdir="$BATS_TEST_TMPDIR/own-zsh"
	mkdir -p "$zdotdir"
	printf 'export FROM_ZDOTDIR_ZSHENV=1\n' >"$zdotdir/.zshenv"
	printf 'export FROM_ZDOTDIR_ZPROFILE=1\n' >"$zdotdir/.zprofile"
	printf 'export ZDOTDIR="%s"\n' "$zdotdir" >"$HOME/.zshenv"

	# zsh reads ~/.zshenv as $ZDOTDIR/.zshenv before ZDOTDIR is set, and never
	# reads a .zshenv again. A prescribed config/zsh/.zshenv would be read by
	# nothing at all.
	[ "$(zsh -c 'printf "%s\n" "${FROM_ZDOTDIR_ZSHENV:-UNSET}"' 2>/dev/null)" = UNSET ]
	[ "$(zsh -l -c 'printf "%s\n" "${FROM_ZDOTDIR_ZSHENV:-UNSET}"' 2>/dev/null)" = UNSET ]

	# A prescribed config/zsh/.zprofile would be read by a login shell and by
	# no other, so 'zsh -c' and a zsh script would still fall back.
	[ "$(zsh -c 'printf "%s\n" "${FROM_ZDOTDIR_ZPROFILE:-UNSET}"' 2>/dev/null)" = UNSET ]
	[ "$(zsh -l -c 'printf "%s\n" "${FROM_ZDOTDIR_ZPROFILE:-UNSET}"' 2>/dev/null)" = 1 ]
}

#
# What 'config unlink' says about the file it does not remove.
#

# ZDOTDIR outlives the links. A ~/.zshenv left behind names a directory that has
# just been removed, and zsh then reads no startup file at all, the ~/.zshrc of
# the user included.
@test "'config unlink' names the ~/.zshenv it leaves behind" {
	run -0 run_shell_step
	run -0 link_prescribed

	run -0 unlink_prescribed
	[[ $output == *"left in place: $HOME/.zshenv"* ]]
	[[ $output == *"rm $HOME/.zshenv"* ]]
	[[ $output == *"reads no startup file"* ]]

	# It names the file. It does not remove it.
	[ -f "$HOME/.zshenv" ]
}

@test "a dry run of 'config unlink' names the ~/.zshenv it would leave" {
	run -0 run_shell_step
	run -0 link_prescribed

	run -0 unlink_prescribed --dry-run
	[[ $output == *"would be left in place: $HOME/.zshenv"* ]]
	[ -L "$XDG_CONFIG_HOME/zsh" ]
	[ -f "$HOME/.zshenv" ]
}

@test "'config unlink' says nothing about a ~/.zshenv that xghost did not write" {
	printf 'export ZDOTDIR=$HOME/my-zsh\n' >"$HOME/.zshenv"
	run -0 link_prescribed

	run -0 unlink_prescribed
	[[ $output != *".zshenv"* ]]
	[ "$(cat "$HOME/.zshenv")" = 'export ZDOTDIR=$HOME/my-zsh' ]
}

#
# The bundle page.
#

# Every package the page lists is read out of the page, so a package added to
# that table is covered without this test changing. The list was hard-coded
# before, it held five of the six rows, and 'ttf-jetbrains-mono-nerd' was in the
# table and in no assertion.
#
# tests/install.bats runs the same cross-check over every bundle page. This one
# is here as well so that a shell page whose table stopped being readable fails
# in the suite of its own bundle rather than only in the installer suite.
@test "the manifest declares every package the bundle page lists" {
	# shellcheck source=lib/install.sh
	. "$ROOT_DIR/lib/install.sh"
	install_paths
	run -0 install_read_manifest "$ROOT_DIR/install/packages/base.txt"
	local declared=$output

	local page="$ROOT_DIR/docs/bundles/shell.md"
	local name rows=0
	while IFS= read -r name; do
		rows=$((rows + 1))
		[[ $'\n'$declared$'\n' == *$'\n'"$name"$'\n'* ]] || {
			printf 'shell.md lists %s and the base manifest does not declare it\n' \
				"$name" >&2
			return 1
		}
	done < <(sed -n 's/^| `\([a-z0-9@._+-]*\)` *| `extra` *|.*|$/\1/p' "$page")

	# A table that stopped matching would pass the loop above without a package
	# name ever being read.
	[ "$rows" -gt 0 ]
}

# No file of this project may hold a value that belongs to one machine. The
# Hyprland bundle holds the same guard over its own files.
@test "no file of this bundle names a machine fact" {
	local file
	for file in "$ZSHRC" "$TMUX_CONF" "$STARSHIP_TEMPLATE"; do
		run -1 grep -qE 'MACHINE_[A-Z0-9_]+' "$file"
	done
}
