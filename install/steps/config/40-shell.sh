# Config: point zsh at the prescribed shell configuration.
#
# 'xghost config link' put the prescribed zsh directory at
# $XDG_CONFIG_HOME/zsh, and zsh reads none of it until ZDOTDIR names that
# directory. ZDOTDIR can be set in one place only: ~/.zshenv, which zsh reads
# before it reads anything else. That file is outside the config directory, so
# the linker cannot reach it and this step is what puts the line there.
#
# The file this step writes carries two exports, and both are here for the same
# reason: ~/.zshenv is the one file zsh reads for every shell it starts, login
# or not, interactive or not.
#
#   - ZDOTDIR, which is what makes zsh read the prescribed .zshrc at all.
#   - STARSHIP_CONFIG, which names the generated prompt through the bridge.
#     The prescribed .zshrc exports the same value, and that copy reaches an
#     interactive shell only. starship falls back to ~/.config/starship.toml in
#     silence when the variable is unset, so a shell that is not interactive
#     would draw whatever that path happens to hold. docs/bundles/shell.md
#     records the boundary and what to do with a file left at that path.
#
# The step creates ~/.zshenv and never edits one. Seven cases, and six of them
# end with the home directory exactly as it was:
#
#   - Neither ~/.zshenv nor a zsh startup file is there. The step writes the
#     file. This is the only case that changes anything.
#   - ~/.zshenv already holds the ZDOTDIR line. Nothing to do. A file of an
#     earlier run that carries no STARSHIP_CONFIG line is reported, because the
#     step edits no file it did not write.
#   - ~/.zshenv holds a ZDOTDIR of its own. The user chose that path, and this
#     step does not take it over.
#   - ~/.zshenv holds something else. The step prints the lines and where to
#     put them.
#   - ~/.zshenv is a directory. zsh reads nothing from it, and no line can be
#     added to it, so the step says that rather than printing advice that
#     cannot be followed.
#   - ~/.zshenv is not there and a zsh startup file is. ZDOTDIR moves every one
#     of ~/.zshrc, ~/.zprofile, ~/.zlogin and ~/.zlogout, so a PATH addition,
#     an ssh-agent or a umask in any of them would stop running at the next
#     login. Orphaning a shell configuration in silence is worse than one
#     report, so the step names the file it found and stops.
#   - The home directory does not take the write. The step reports it and
#     changes nothing.
#
# None of the seven fails the installation. The rest of the desktop is in place
# either way, and zsh is a login shell rather than a part of the session.
# install/steps/post-install/10-command-path.sh is the shape this step follows
# for the one case they share: it creates one path under the home directory
# when nothing is there, and 'xghost config unlink' removes neither path,
# because no prescribed entry stands behind either one. The two differ on what
# they do about a path that holds something else, and deliberately: that step
# calls install_fail and stops the installation, because every config step runs
# the command it links, and this one reports and carries on.
#
# docs/bundles/shell.md records the whole of it, including how to undo it.

zshenv=$HOME/.zshenv

# Every startup file ZDOTDIR moves. zsh reads each of these from $ZDOTDIR once
# the variable is set, so each one of them is orphaned by the same line.
readonly ZSH_STARTUP_FILES=(.zshrc .zprofile .zlogin .zlogout)

# The lines the file carries. They are written out exactly as they are here, so
# zsh expands them at every start and both paths follow XDG_CONFIG_HOME.
zdotdir_line='export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"'
starship_line='export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/xghost-generated/starship/starship.toml"'

# A directory takes no line, and zsh reads nothing out of one. This is tested
# before the greps below, because grep on a directory reports nothing this step
# could tell apart from a file that does not hold the line.
if [ -d "$zshenv" ] && [ ! -L "$zshenv" ]; then
	install_warn "$zshenv is a directory, so zsh reads no ZDOTDIR from it and this step wrote nothing"
	install_warn "what to do: move that directory aside or remove it, then run './install.sh' again. The step writes $zshenv itself once the path is free."
	exit 0
fi

if [ -e "$zshenv" ] || [ -L "$zshenv" ]; then
	if grep -qxF -- "$zdotdir_line" "$zshenv" 2>/dev/null; then
		install_say "already in place: $zshenv sets ZDOTDIR to the prescribed zsh directory"
		if ! grep -qxF -- "$starship_line" "$zshenv" 2>/dev/null; then
			install_warn "$zshenv carries no STARSHIP_CONFIG line, so a zsh that is not interactive draws whatever prompt ~/.config/starship.toml holds"
			install_warn "what to do: add this line to $zshenv: $starship_line"
		fi
		exit 0
	fi

	if grep -qE '^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=' "$zshenv" 2>/dev/null; then
		install_warn "$zshenv sets ZDOTDIR already, and this step changed nothing at that path"
		install_warn "what to do: nothing, if that ZDOTDIR is what you want. To read the shell configuration of xghost instead, put these two lines in $zshenv: $zdotdir_line and $starship_line"
		exit 0
	fi

	install_warn "$zshenv is already there, so zsh does not read the shell configuration of xghost yet"
	install_warn "what to do: add these two lines to $zshenv, then open a new terminal: $zdotdir_line and $starship_line"
	exit 0
fi

# ZDOTDIR moves every startup file, so every one of them is tested. The file
# that was found is named, because "a zsh startup file" sends the reader
# looking and the path does not.
for base in "${ZSH_STARTUP_FILES[@]}"; do
	found=$HOME/$base
	if [ -L "$found" ] && [ ! -e "$found" ]; then
		install_warn "$found is a symbolic link that points at a target that does not exist, and ZDOTDIR would stop zsh looking at it at all; this step wrote nothing"
		install_warn "what to do: point that link at a file or remove it, then run './install.sh' again. There is nothing at the end of it to keep."
		exit 0
	fi
	if [ -e "$found" ]; then
		install_warn "$found is there, and ZDOTDIR would stop zsh reading it; this step wrote nothing"
		install_warn "what to do: move what you want to keep out of $found, then create $zshenv holding these two lines: $zdotdir_line and $starship_line"
		install_warn "why it matters: ZDOTDIR moves every startup file of zsh, which is .zshrc, .zprofile, .zlogin and .zlogout. The shell configuration of xghost is a whole .zshrc rather than an addition to yours, so the two cannot both be the file zsh reads."
		exit 0
	fi
done

if [ "$INSTALL_DRY_RUN" = yes ]; then
	install_would "write $zshenv, holding: $zdotdir_line and $starship_line"
	exit 0
fi

# The file is written whole and then moved into place, so an interrupted write
# leaves no half file for zsh to read at the next login.
#
# The temporary path comes from mktemp rather than from a name this step writes
# out. A fixed name is a path anything can plant a symbolic link at before the
# step runs, and a redirection follows such a link: the write would land on the
# file at the far end, 'chmod' would land on it too, and ~/.zshenv would become
# a link into it. mktemp creates the file itself with O_CREAT and O_EXCL, so it
# opens no path that already exists and follows no link, and the name it picks
# is not one that can be guessed in advance. It is also the first thing this
# step does that needs the home directory to be writable, so the report for a
# home directory that is not writable is here.
if ! temporary=$(mktemp "$zshenv.XXXXXX" 2>/dev/null); then
	install_warn "cannot create a temporary file beside $zshenv, so zsh was not pointed at the shell configuration of xghost"
	install_warn "what to do: check the permissions of $HOME, then run './install.sh' again. Nothing was changed at $zshenv, and the rest of the desktop is in place."
	exit 0
fi

if ! cat >"$temporary" <<EOF
# Written by xghost, install/steps/config/40-shell.sh.
#
# ZDOTDIR names the directory zsh reads .zshrc from. xghost prescribes that
# file, and 'xghost config link' links the directory this line names.
#
# STARSHIP_CONFIG names the generated prompt through the same directory. It is
# here rather than only in the prescribed .zshrc because zsh reads this file for
# every shell and .zshrc for interactive ones alone.
#
# Remove this file to put zsh back to ~/.zshrc. See docs/bundles/shell.md.
$zdotdir_line
$starship_line
EOF
then
	rm -f -- "$temporary"
	install_warn "cannot write $temporary, so zsh was not pointed at the shell configuration of xghost"
	install_warn "what to do: check the permissions of $HOME, then run './install.sh' again. Nothing was changed at $zshenv, and the rest of the desktop is in place."
	exit 0
fi

if ! chmod 0644 "$temporary" || ! mv -- "$temporary" "$zshenv"; then
	rm -f -- "$temporary"
	install_warn "cannot put $zshenv in place, so zsh was not pointed at the shell configuration of xghost"
	install_warn "what to do: check the permissions of $HOME, then run './install.sh' again. Nothing was changed at $zshenv, and the rest of the desktop is in place."
	exit 0
fi

install_say "wrote $zshenv, so zsh reads the prescribed shell configuration from the next login"
install_say "the first shell opens with an empty history: the prescribed configuration keeps the history under XDG_STATE_HOME, and a ~/.histfile of an earlier shell is left exactly where it is and is read by nothing"
