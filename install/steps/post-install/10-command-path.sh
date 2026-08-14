# Post-install: put the 'xghost' command in reach.
#
# Two things need the command on the PATH. The user runs 'xghost theme set' and
# 'xghost machine detect' by name, and the Hyprland autostart runs
# 'xghost machine refresh' at the start of every session. A prescribed Hyprland
# file cannot write the location of this checkout, so that line names a program
# on the PATH and this step is what puts it there.
#
# The link is created the way the linker creates one: a path that already points
# at this command is adopted and reported, and a path that holds something else
# is named and left exactly as it is. Nothing here is ever clobbered.
#
# This link is not in the link record, so 'xghost config unlink' does not remove
# it. It is not prescribed configuration: it is the command itself.

bin_dir=${XGHOST_BIN_DIR:-$HOME/.local/bin}
target=$INSTALL_XGHOST
link=$bin_dir/xghost

if [ ! -x "$target" ]; then
	install_fail \
		"the xghost command is not an executable file: $target" \
		"check the repository out again."
fi

if [ -L "$link" ] && [ "$(readlink -f "$link" || true)" = "$(readlink -f "$target" || true)" ]; then
	install_say "already linked: $link -> $target"
elif [ -e "$link" ] || [ -L "$link" ]; then
	install_fail \
		"$link is already there and it is not this command" \
		"move that path aside, then run './install.sh' again. Nothing was changed at that path."
elif [ "$INSTALL_DRY_RUN" = yes ]; then
	install_would "link $link -> $target"
else
	if ! mkdir -p "$bin_dir"; then
		install_fail \
			"cannot create the directory $bin_dir" \
			"create it by hand, then run './install.sh' again."
	fi
	if ! ln -s "$target" "$link"; then
		install_fail \
			"cannot create the symbolic link $link" \
			"check the permissions of $bin_dir, then run './install.sh' again."
	fi
	install_say "linked: $link -> $target"
fi

# The PATH of this shell is not the PATH of the desktop session, so this is a
# report rather than a test the step can fail on.
case ":${PATH:-}:" in
*":$bin_dir:"*) ;;
*)
	install_warn "$bin_dir is not on the PATH of this shell"
	install_warn "what to do: add it to the PATH of your login shell, so that you can run 'xghost' by name and the Hyprland autostart can run 'xghost machine refresh'."
	;;
esac
