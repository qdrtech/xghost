# Config: point zsh at the prescribed shell configuration.
#
# 'xghost config link' put the prescribed zsh directory at
# $XDG_CONFIG_HOME/zsh, and zsh reads none of it until ZDOTDIR names that
# directory. ZDOTDIR can be set in one place only: ~/.zshenv, which zsh reads
# before it reads anything else. That file is outside the config directory, so
# the linker cannot reach it and this step is what puts the line there.
#
# The step creates ~/.zshenv and never edits one. Four cases end with the home
# directory exactly as it was:
#
#   - ~/.zshenv already holds the line. Nothing to do, and nothing to report.
#   - ~/.zshenv holds a ZDOTDIR of its own. The user chose that path, and this
#     step does not take it over.
#   - ~/.zshenv holds something else. The step prints the line and where to put
#     it.
#   - ~/.zshenv is not there and ~/.zshrc is. ZDOTDIR would stop zsh reading
#     that file, and orphaning a shell configuration in silence is worse than
#     one report. The reader moves what they want to keep and adds the line.
#
# None of the three fails the installation. The rest of the desktop is in place
# either way, and zsh is a login shell rather than a part of the session.
# install/steps/post-install/10-command-path.sh is the shape this step follows:
# it creates one path under the home directory when nothing is there, it names
# what it found when something is, and 'xghost config unlink' removes neither,
# because no prescribed entry stands behind either one.
#
# docs/bundles/shell.md records the whole of it, including how to undo it.

zshenv=$HOME/.zshenv
zshrc=$HOME/.zshrc

# The line the file carries. It is written out exactly as it is here, so zsh
# expands it at every start and the path follows XDG_CONFIG_HOME.
zdotdir_line='export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"'

if [ -e "$zshenv" ] || [ -L "$zshenv" ]; then
	if grep -qxF -- "$zdotdir_line" "$zshenv" 2>/dev/null; then
		install_say "already in place: $zshenv sets ZDOTDIR to the prescribed zsh directory"
		exit 0
	fi

	if grep -qE '^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=' "$zshenv" 2>/dev/null; then
		install_warn "$zshenv sets ZDOTDIR already, and this step changed nothing at that path"
		install_warn "what to do: nothing, if that ZDOTDIR is what you want. To read the shell configuration of xghost instead, put this line in $zshenv: $zdotdir_line"
		exit 0
	fi

	install_warn "$zshenv is already there, so zsh does not read the shell configuration of xghost yet"
	install_warn "what to do: add this line to $zshenv, then open a new terminal: $zdotdir_line"
	exit 0
fi

if [ -e "$zshrc" ] || [ -L "$zshrc" ]; then
	install_warn "$zshrc is there, and ZDOTDIR would stop zsh reading it; this step wrote nothing"
	install_warn "what to do: move what you want to keep out of $zshrc, then create $zshenv holding this one line: $zdotdir_line"
	install_warn "why it matters: the shell configuration of xghost is a whole .zshrc rather than an addition to yours, so the two cannot both be the file zsh reads."
	exit 0
fi

if [ "$INSTALL_DRY_RUN" = yes ]; then
	install_would "write $zshenv, holding: $zdotdir_line"
	exit 0
fi

# The file is written whole and then moved into place, so an interrupted write
# leaves no half file for zsh to read at the next login.
temporary=$zshenv.xghost-new
if ! cat >"$temporary" <<EOF
# Written by xghost, install/steps/config/40-shell.sh.
#
# ZDOTDIR names the directory zsh reads .zshrc from. xghost prescribes that
# file, and 'xghost config link' links the directory this line names. Remove
# this file to put zsh back to ~/.zshrc. See docs/bundles/shell.md.
$zdotdir_line
EOF
then
	rm -f "$temporary"
	install_fail \
		"cannot write $temporary" \
		"check the permissions of $HOME, then run './install.sh' again. Nothing was changed at $zshenv."
fi

if ! chmod 0644 "$temporary" || ! mv -- "$temporary" "$zshenv"; then
	rm -f "$temporary"
	install_fail \
		"cannot put $zshenv in place" \
		"check the permissions of $HOME, then run './install.sh' again. Nothing was changed at $zshenv."
fi

install_say "wrote $zshenv, so zsh reads the prescribed shell configuration from the next login"
