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
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XDG_CACHE_HOME="$HOME/.cache"
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

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
	XGHOST_CONFIG_SOURCE="$ROOT_DIR/config" "$XGHOST" config unlink
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

# Expand the STARSHIP_CONFIG line of the prescribed zshrc the way a shell
# expands it, in the environment of this test.
#
# The line is read out of the file rather than written again here, so a change
# to the prescribed file is what this resolves.
starship_config_from_zshrc() {
	local line
	line=$(grep -m1 '^export STARSHIP_CONFIG=' "$ZSHRC") || return 1
	(
		eval "$line"
		printf '%s\n' "$STARSHIP_CONFIG"
	)
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
prescribed_default_shell() {
	sed -n 's/^set -g default-shell //p' "$TMUX_CONF"
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
	local theme name value
	while IFS= read -r theme; do
		"$XGHOST" theme set "$theme" >/dev/null
		while IFS= read -r name; do
			value=$(palette_value "$theme" "$name")
			run -0 grep -Fq "\"$value\"" "$GENERATED/starship/starship.toml"
		done < <(sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' "$ROOT_DIR/themes/$theme/palette.conf")
		run -1 grep -qE '@[A-Z][A-Z0-9_]*@' "$GENERATED/starship/starship.toml"
	done < <("$XGHOST" theme list)
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
	local config_home="$XDG_CONFIG_HOME"
	unset XDG_CONFIG_HOME

	local resolved
	resolved=$(starship_config_from_zshrc)
	[ "$resolved" = "$HOME/.config/$BRIDGE_NAME/starship/starship.toml" ]
	[ "$resolved" = "$config_home/$BRIDGE_NAME/starship/starship.toml" ]
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
	[ -f "$XDG_STATE_HOME/zsh/history" ] || [ -d "$XDG_STATE_HOME/zsh" ]
	[ -d "$XDG_CACHE_HOME/zsh" ]
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

@test "the step leaves no temporary file behind" {
	run -0 run_shell_step
	[ ! -e "$HOME/.zshenv.xghost-new" ]
}

#
# The bundle page.
#

@test "the bundle page names every package the manifest declares for it" {
	# shellcheck source=lib/install.sh
	. "$ROOT_DIR/lib/install.sh"
	install_paths
	run -0 install_read_manifest "$ROOT_DIR/install/packages/base.txt"
	local declared=$output

	local name
	for name in zsh starship tmux zsh-syntax-highlighting zsh-autosuggestions; do
		run -0 grep -qE "^\| \`$name\` +\| \`extra\` +\|" "$ROOT_DIR/docs/bundles/shell.md"
		[[ $'\n'$declared$'\n' == *$'\n'"$name"$'\n'* ]]
	done
}

# No file of this project may hold a value that belongs to one machine. The
# Hyprland bundle holds the same guard over its own files.
@test "no file of this bundle names a machine fact" {
	local file
	for file in "$ZSHRC" "$TMUX_CONF" "$STARSHIP_TEMPLATE"; do
		run -1 grep -qE 'MACHINE_[A-Z0-9_]+' "$file"
	done
}
