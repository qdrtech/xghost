# Packaging: the packages the AUR carries.
#
# aur.txt names hyprshade, which no official repository carries. The step is a
# second one because the repository a package comes from decides which tool
# installs it.
#
# The base installation does not require an AUR helper. A machine with no helper
# gets every package of base.txt, which is the terminal, the compositor, the
# bar, the launcher, the shell, the font and the GTK theme, so it gets a
# complete working desktop. This step therefore names each AUR package it did
# not install rather than stopping the installation for it.
#
# xghost installs no AUR helper by itself. That would mean building a PKGBUILD
# nobody vetted, on a machine that asked for a desktop.
#
# The helper runs as the user, never under sudo: yay and paru both refuse to be
# run as root, and they raise their own privileges for the pacman half of the
# work.

aur_file=$INSTALL_PACKAGES_DIR/aur.txt

if ! manifest=$(install_read_manifest "$aur_file"); then
	install_fail \
		"the AUR package manifest cannot be read: $aur_file" \
		"correct that file, then run './install.sh' again."
fi

packages=()
while IFS= read -r name; do
	if [ -n "$name" ]; then
		packages+=("$name")
	fi
done <<<"$manifest"

if [ "${#packages[@]}" -eq 0 ]; then
	install_say "the AUR manifest declares no package: $aur_file"
	exit 0
fi

if ! report=$(install_missing_packages "${packages[@]}"); then
	install_fail \
		"the AUR packages this machine is missing could not be read from pacman" \
		"read the report above, then run './install.sh' again."
fi

missing=()
while IFS= read -r name; do
	if [ -n "$name" ]; then
		missing+=("$name")
	fi
done <<<"$report"

if [ "${#missing[@]}" -eq 0 ]; then
	install_say "every package of $aur_file is installed (${#packages[@]} declared)"
	exit 0
fi

helper=
read -r -a candidates <<<"$INSTALL_AUR_HELPERS"
for candidate in ${candidates[@]+"${candidates[@]}"}; do
	if command -v "$candidate" >/dev/null 2>&1; then
		helper=$candidate
		break
	fi
done

if [ -z "$helper" ]; then
	install_warn "no AUR helper is installed, so these packages are not installed: ${missing[*]}"
	install_warn "what to do: nothing, unless you want them. Install one of these helpers and run './install.sh' again, and this step picks them up: $INSTALL_AUR_HELPERS. The desktop works without them; each package is named in $aur_file with what it serves."
	exit 0
fi

install_say "${#missing[@]} of ${#packages[@]} AUR packages are missing: ${missing[*]}"

if [ "$INSTALL_DRY_RUN" = yes ]; then
	install_would "run: $helper -S --needed -- ${missing[*]}"
	exit 0
fi

if ! "$helper" -S --needed -- "${missing[@]}"; then
	install_fail \
		"$helper could not install every package of $aur_file" \
		"read the report of $helper above, fix what it names, then run './install.sh' again."
fi

install_say "every package of $aur_file is installed"
