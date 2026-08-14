# Preflight: the package manifests parse.
#
# The manifests are the single source of truth for what an installation needs.
# A name with a typo in it reaches pacman as a package that does not exist, and
# the installation then stops in the packaging group with a message about a
# target rather than about a file this project owns. Reading both manifests here
# turns that into one report, with the file and the line number, before anything
# changes.
#
# This step reads. It changes nothing.

base_file=$INSTALL_PACKAGES_DIR/base.txt
aur_file=$INSTALL_PACKAGES_DIR/aur.txt

if ! base_packages=$(install_read_manifest "$base_file"); then
	install_fail \
		"the base package manifest has a problem, and it is the single source of truth for what an installation needs" \
		"correct $base_file, then run './install.sh' again. Every problem of that file is reported above."
fi

if [ -z "$base_packages" ]; then
	install_fail \
		"the base package manifest declares no package: $base_file" \
		"check the repository out again. An installation with no package installs a configuration for programs that are not there."
fi

if ! aur_packages=$(install_read_manifest "$aur_file"); then
	install_fail \
		"the AUR package manifest has a problem" \
		"correct $aur_file, then run './install.sh' again. Every problem of that file is reported above."
fi

base_count=$(printf '%s\n' "$base_packages" | grep -c .)
aur_count=0
if [ -n "$aur_packages" ]; then
	aur_count=$(printf '%s\n' "$aur_packages" | grep -c .)
fi

install_say "the manifests declare $base_count packages from the official repositories and $aur_count from the AUR"
