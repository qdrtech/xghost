# The zsh configuration of xghost.
#
# This file is prescribed configuration. The project owns it, and 'xghost config
# link' symlinks the directory that holds it to ~/.config/zsh. Do not edit it:
# an edit dirties the checkout and conflicts on the next pull. See
# docs/adr/0001-prescribed-config-architecture.md.
#
# zsh reads this file because ZDOTDIR names the directory above it.
# install/steps/config/40-shell.sh writes that one line into ~/.zshenv, and
# docs/bundles/shell.md records what the step does and what it refuses to do.
#
# The colours are not here. The prompt is starship, starship reads one file and
# has no include of any kind, so the whole of its configuration is generated
# output. See "The prompt" below and docs/bundles/shell.md.
#
# What is not here either: everything personal, work-specific or
# machine-specific that the zshrc of qdrtech/dotfiles carried. Every line that
# was left behind is listed in docs/bundles/shell.md with the reason.

# The history.
#
# The file follows XDG_STATE_HOME, because a shell history is derived state
# that has to survive a reboot, which is the same rule docs/theming.md gives
# for the generated output. zsh creates the file and never the directory above
# it, so this creates it. 'mkdir' reports a failure on standard error, and
# nothing here hides one.
HISTFILE=${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history
HISTSIZE=1000
SAVEHIST=1000
mkdir -p -- "${HISTFILE:h}"

# Emacs key bindings on the command line, whatever EDITOR holds.
bindkey -e

# Completion.
#
# The dump file follows XDG_CACHE_HOME. Without '-d' compinit writes it into
# ZDOTDIR, which is the link into this checkout, so every login would drop an
# untracked file into a git working tree.
autoload -Uz compinit
mkdir -p -- "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

# The 'xghost' command runs by name.
#
# install/steps/post-install/10-command-path.sh links bin/xghost into
# ~/.local/bin, and Arch puts that directory on the PATH of no login shell of
# its own. This line is what lets 'xghost theme set' run by name here, and that
# command is what replaces the 'ts' alias of the dotfiles.
#
# The guard is what keeps a second read of this file from naming the directory
# twice.
case ":${PATH}:" in
*":$HOME/.local/bin:"*) ;;
*) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# The aliases of this desktop.
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -l'
alias la='ls -a'
alias l='ls -al'

# The two zsh plugins this desktop ships, in the order their upstreams ask for:
# the highlighter last of the two that draw on the command line, and both after
# compinit.
#
# Neither source is guarded. 'zsh-syntax-highlighting' and 'zsh-autosuggestions'
# are declared in install/packages/base.txt, so a machine that has this file has
# both files, and a guard would turn a broken installation into a shell that
# quietly lost its highlighting.
#
# The suggestion is drawn in 'fg=8', which is the default of
# zsh-autosuggestions and is terminal colour slot 8. docs/bundles/ghostty.md
# records that slot 8 carries TEXT_MUTED for exactly this plugin, so the
# suggestion is readable and this file sets no colour of its own.
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# The prompt.
#
# starship reads one file and offers no include, so the whole file is generated
# output and 'xghost theme set' writes it from the palette of the active theme.
# templates/starship/starship.toml is the file this project owns.
#
# The path names the bridge that 'xghost config link' creates, which is the
# construction of docs/adr/0002-the-bridge-to-the-generated-output.md. Neither
# end of it is written out in full: the directory it starts from follows
# XDG_CONFIG_HOME, and the bridge follows XDG_STATE_HOME. The shell is one of
# the two places in this project that can write the XDG default inline, and
# that is what the ':-' below is.
#
# The same line is in the ~/.zshenv that install/steps/config/40-shell.sh
# writes, and the two carry the same text on purpose. zsh reads this file for
# an interactive shell alone, so this copy covers a terminal and nothing else;
# the ~/.zshenv copy covers every other zsh, which is what keeps 'zsh -c' and a
# zsh script off the silent fallback of starship. This copy is what an
# interactive shell gets when the ~/.zshenv on the machine was written by hand
# and carries the ZDOTDIR line alone. tests/shell.bats fails when the two texts
# stop matching, and docs/bundles/shell.md records the boundary.
export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/xghost-generated/starship/starship.toml"

# starship falls back to its own default prompt, and says nothing at all, when
# the file STARSHIP_CONFIG names is not there. That is the silent miss ADR 0002
# exists to prevent, and this shell is the one part of the desktop that can
# report it. The prompt is still started: a default prompt is better than none.
if [ ! -r "$STARSHIP_CONFIG" ]; then
	printf 'xghost: the generated starship configuration is missing: %s\n' \
		"$STARSHIP_CONFIG" >&2
	printf 'xghost: this shell draws the default prompt of starship. Run %s to render that file.\n' \
		"'xghost theme set <name>'" >&2
fi

eval "$(starship init zsh)"
