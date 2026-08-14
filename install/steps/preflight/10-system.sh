# Preflight: the system this installs onto.
#
# xghost prescribes an Arch Linux desktop. Every name in the manifests is an
# Arch package name and pacman is what installs them, so an installation onto
# another distribution would install nothing and then link a desktop with no
# programs behind it. This step refuses that before anything changes.
#
# This step reads. It changes nothing, whether it passes or refuses.

os_release=${XGHOST_OS_RELEASE:-/etc/os-release}

if [ ! -r "$os_release" ]; then
	install_fail \
		"cannot read $os_release, so the distribution of this machine is not known" \
		"install xghost on Arch Linux. An Arch system carries that file, and this installer will not guess at the distribution it is changing."
fi

# The two keys that name the distribution. A value may carry one pair of
# quotation marks, which os-release allows and this reader drops.
system_id=
system_id_like=

while IFS= read -r line || [ -n "$line" ]; do
	case $line in
	ID=*) system_id=${line#ID=} ;;
	ID_LIKE=*) system_id_like=${line#ID_LIKE=} ;;
	esac
done <"$os_release"

unquote() {
	local value=$1
	case $value in
	\"*\") value=${value#\"}; value=${value%\"} ;;
	\'*\') value=${value#\'}; value=${value%\'} ;;
	esac
	printf '%s\n' "$value"
}

system_id=$(unquote "$system_id")
system_id_like=$(unquote "$system_id_like")

is_arch=no
if [ "$system_id" = arch ]; then
	is_arch=yes
fi

# ID_LIKE is a space separated list, and a derivative such as EndeavourOS names
# arch in it. Such a machine runs pacman against the same repositories, so it
# is an Arch system for the purpose of this installation.
read -r -a like_words <<<"$system_id_like"
for word in ${like_words[@]+"${like_words[@]}"}; do
	if [ "$word" = arch ]; then
		is_arch=yes
	fi
done

if [ "$is_arch" != yes ]; then
	install_fail \
		"this is not an Arch Linux system: $os_release reports ID='${system_id:-none}' and ID_LIKE='${system_id_like:-none}'" \
		"install xghost on Arch Linux, or on a distribution whose os-release names arch in ID_LIKE. Nothing was changed."
fi

if ! command -v pacman >/dev/null 2>&1; then
	install_fail \
		"the 'pacman' program is not installed, and it is what installs every package the manifests declare" \
		"install pacman, or run this installation on an Arch Linux system. Nothing was changed."
fi

# 'xghost theme set' locks the state directory with flock, so a machine without
# it reaches the config group and fails there. The failure belongs here, where
# nothing has been changed yet.
if ! command -v flock >/dev/null 2>&1; then
	install_fail \
		"the 'flock' program is not installed, and 'xghost theme set' needs it to lock the state directory" \
		"install the 'util-linux' package, then run './install.sh' again. Nothing was changed."
fi

install_say "the system is Arch Linux: ID=$system_id"
