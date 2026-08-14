# Packaging: the packages of the official repositories.
#
# The step is idempotent because it asks first. 'pacman -T' names the packages
# this machine does not have, and a run with nothing missing installs nothing
# at all. A second run of a finished installation therefore reaches no package
# operation, and an installation that stopped part way through installs exactly
# the remainder.
#
# This is the one step that needs root, and it raises its own privileges. Every
# other step runs as the user, because every other step writes into that user's
# directories.

base_file=$INSTALL_PACKAGES_DIR/base.txt

if ! manifest=$(install_read_manifest "$base_file"); then
	install_fail \
		"the base package manifest cannot be read: $base_file" \
		"correct that file, then run './install.sh' again."
fi

packages=()
while IFS= read -r name; do
	if [ -n "$name" ]; then
		packages+=("$name")
	fi
done <<<"$manifest"

if [ "${#packages[@]}" -eq 0 ]; then
	install_fail \
		"the base package manifest declares no package: $base_file" \
		"correct that file, then run './install.sh' again."
fi

if ! report=$(install_missing_packages "${packages[@]}"); then
	install_fail \
		"the packages this machine is missing could not be read from pacman" \
		"read the report above. The installation changed nothing, so running './install.sh' again once pacman answers is safe."
fi

missing=()
while IFS= read -r name; do
	if [ -n "$name" ]; then
		missing+=("$name")
	fi
done <<<"$report"

if [ "${#missing[@]}" -eq 0 ]; then
	install_say "every package of $base_file is installed (${#packages[@]} declared)"
	exit 0
fi

install_say "${#missing[@]} of ${#packages[@]} packages are missing: ${missing[*]}"

if [ "$INSTALL_DRY_RUN" = yes ]; then
	install_would "run: sudo pacman -S --needed -- ${missing[*]}"
	exit 0
fi

# The one moment this installation raises privileges, announced where it
# happens. Preflight says that sudo is installed, and that is a different
# sentence: three steps and an unbounded amount of pacman output separate the
# two, and a password prompt that arrives with neither warning nor context is a
# prompt people type into without reading.
install_say ""
install_say "the next command needs root, and it is the only one that does:"
install_say "  sudo pacman -S --needed -- ${missing[*]}"
install_say "sudo asks for your password now, unless it has one from this terminal already."
install_say ""

if ! sudo pacman -S --needed -- "${missing[@]}"; then
	install_fail \
		"pacman could not install every package of $base_file" \
		"read the pacman report above, fix what it names, then run './install.sh' again. The packages that are already installed are passed over on the second run."
fi

# pacman can end well and still leave a package out, so the step proves its own
# result rather than trusting its exit status.
if ! report=$(install_missing_packages "${packages[@]}"); then
	install_fail \
		"pacman ran, and the packages this machine is missing could not be read afterwards" \
		"read the report above, then run './install.sh' again."
fi

still_missing=()
while IFS= read -r name; do
	if [ -n "$name" ]; then
		still_missing+=("$name")
	fi
done <<<"$report"

if [ "${#still_missing[@]}" -gt 0 ]; then
	install_fail \
		"these packages are still not installed after pacman ran: ${still_missing[*]}" \
		"install them by hand, then run './install.sh' again."
fi

install_say "every package of $base_file is installed"
