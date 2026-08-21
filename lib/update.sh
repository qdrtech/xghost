#!/usr/bin/env bash
#
# The update path: what one update does, in what order, and what it reports.
#
# An update runs six steps and then reports what changed:
#
#   1. pull      bring the checkout up to date. Prescribed configuration
#                arrives here and nowhere else: the linker points the config
#                directory of the user at the files of this checkout, so a
#                pull that changes a prescribed file changes what the desktop
#                reads, and no migration is involved.
#   2. link      link the prescribed files the pull added. A file that was
#                already linked needs nothing; a file the pull created needs a
#                link, and this is idempotent so the rest is untouched.
#   3. packages  update the system packages.
#   4. migrate   run the pending migrations. lib/migrate.sh owns that.
#   5. render    render the active theme again from the new templates.
#   6. reload    tell the running components to read their configuration again.
#
# The order is the contract. Packages come after the pull because a migration
# may depend on a package the pull declared, and the render comes after the
# migrations because a migration may remove a stale generated file. The reload
# is last because it is what shows the render, and there is nothing to show
# until the render has moved into place.
#
# The reload itself belongs to lib/reload.sh, which owns the set of components
# and how each one is told. This file held that table until issue #24, and the
# table said so; one reload now serves the update, 'xghost theme set' and
# 'xghost settings set' rather than one mechanism per caller.
#
# Every effect that reaches outside this project is reached by name on the PATH:
# 'git', the AUR helper, 'pacman', and the programs lib/reload.sh names. The
# tests put a stub of each first on the PATH, so no test of this project pulls a
# repository, installs a package, or signals a component of the live session.
# XGHOST_ROOT points the pull at the checkout, and the tests point it at a
# throwaway clone.
#
# Machine facts and knobs are inputs and never outputs. Nothing in this file
# writes either one: the pull writes the checkout, the renderer writes the state
# directory, and both of those files stay where the user left them.
#
# Environment:
#   XGHOST_ROOT             The checkout this updates. The tests use this.
#   XGHOST_UPDATE_HELPERS   The AUR helpers to look for, in the order to look.
#                           The default is 'yay paru'.
#   XGHOST_MIGRATIONS_DIR   The migration directory. The tests use this.

# The include sentinel.
if [ -n "${XGHOST_UPDATE_SOURCED:-}" ]; then
	return 0
fi
XGHOST_UPDATE_SOURCED=1

shopt -u dotglob nocaseglob failglob
unset GLOBIGNORE
set +f

XGHOST_UPDATE_LIB_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/migrate.sh
. "$XGHOST_UPDATE_LIB_DIR/migrate.sh"
# shellcheck source=lib/linker.sh
. "$XGHOST_UPDATE_LIB_DIR/linker.sh"
# reload.sh owns the components and how each one is told to read its
# configuration again. The update is one of its three callers.
# shellcheck source=lib/reload.sh
. "$XGHOST_UPDATE_LIB_DIR/reload.sh"

# The AUR helpers this looks for, in the order it looks. It is the same list the
# installer uses, and for the same reason: a machine that carries another helper
# names it here.
UPDATE_HELPERS=${XGHOST_UPDATE_HELPERS:-"yay paru"}

# What each step of this run did, for the report at the end. Each one holds one
# line of prose.
UPDATE_REPORT_PROJECT=
UPDATE_REPORT_LINKS=
UPDATE_REPORT_PACKAGES=
UPDATE_REPORT_MIGRATIONS=
UPDATE_REPORT_GENERATED=
UPDATE_REPORT_COMPONENTS=

update_say() {
	printf '%s\n' "$*"
}

update_warn() {
	printf '%s: %s\n' "$XGHOST_PROGRAM" "$*" >&2
}

# A fingerprint of the generated output.
#
#   update_fingerprint DIRECTORY
#
# The report says whether the render changed anything, and a report that always
# says "rendered" says nothing. Every build lands in a directory of its own, so
# the path of the build always differs; the content is what is compared. The
# fingerprint covers the name of every file, the content of every file, and the
# target of every link.
#
# It prints 'none' for a directory that is not there, which is the state before
# the first render.
update_fingerprint() {
	local dir=$1
	local path

	if [ ! -d "$dir" ]; then
		printf 'none\n'
		return 0
	fi

	{
		cd "$dir" || exit 1
		find . \( -type f -o -type l \) -print | LC_ALL=C sort |
			while IFS= read -r path; do
				if [ -L "$path" ]; then
					printf 'l %s %s\n' "$path" "$(readlink "$path")"
				else
					printf 'f %s %s\n' "$path" "$(cksum <"$path")"
				fi
			done
	} | cksum
}

# Print the packages this machine has, one 'name version' per line.
#
# 'pacman -Q' reads the local database, needs no root, and changes nothing. A
# machine without pacman prints nothing and the comparison then reports that it
# was not made, rather than reporting that no package changed.
update_package_list() {
	if ! command -v pacman >/dev/null 2>&1; then
		return 1
	fi
	pacman -Q 2>/dev/null | LC_ALL=C sort
}

# Compare two package lists and describe the difference in one line.
#
# The comparison is made by name and then by line. A name in the second list and
# not in the first is a package that arrived; a name in the first and not in the
# second is one that went; a line that is new whose name is not new is a version
# that moved.
#
# 'comm' is what compares them, rather than a search for each package. A package
# name may hold '+' and '.', and both are regular expression characters, so a
# search would read 'gtk+' as a pattern.
update_package_difference() {
	local before=$1 after=$2
	local added removed lines changed
	local before_names after_names

	before_names=$(cut -d' ' -f1 <<<"$before" | LC_ALL=C sort)
	after_names=$(cut -d' ' -f1 <<<"$after" | LC_ALL=C sort)

	added=$(comm -13 <(printf '%s\n' "$before_names") <(printf '%s\n' "$after_names") | wc -l)
	removed=$(comm -23 <(printf '%s\n' "$before_names") <(printf '%s\n' "$after_names") | wc -l)
	lines=$(comm -13 \
		<(printf '%s\n' "$before" | LC_ALL=C sort) \
		<(printf '%s\n' "$after" | LC_ALL=C sort) | wc -l)
	changed=$((lines - added))

	printf '%d installed, %d upgraded or downgraded, %d removed\n' \
		"$added" "$changed" "$removed"
}

# Bring the checkout up to date.
#
# The pull is fast forward only. A checkout with work of its own on it is not
# fast forwarded, and the update stops there rather than merging a change the
# reader did not ask for.
#
# Returns 1 when the checkout was not updated. Everything after this step acts
# on the new checkout, so a failure here stops the update.
update_pull() {
	local before after count status=0

	theme_repo_paths

	if ! command -v git >/dev/null 2>&1; then
		update_warn "the 'git' program is not installed, so the checkout cannot be updated"
		update_warn "what to do: install git, then run 'xghost system update' again."
		return 1
	fi

	if ! git -C "$XGHOST_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
		update_warn "$XGHOST_ROOT is not a git working tree, so the checkout cannot be updated"
		update_warn "what to do: clone the project again with boot.sh, or run the update from the checkout git made."
		return 1
	fi

	before=$(git -C "$XGHOST_ROOT" rev-parse HEAD 2>/dev/null) || status=$?
	if [ "$status" -ne 0 ] || [ -z "$before" ]; then
		update_warn "the checkout at $XGHOST_ROOT has no commit, so there is nothing to update from"
		return 1
	fi

	update_say "-- pull $XGHOST_ROOT"
	if ! git -C "$XGHOST_ROOT" pull --ff-only; then
		update_warn "the pull failed, so the checkout is unchanged and the update stopped"
		update_warn "what to do: read the report above. A checkout that carries work of its own is not fast forwarded, and a machine with no network cannot pull at all. Nothing else was changed."
		return 1
	fi

	after=$(git -C "$XGHOST_ROOT" rev-parse HEAD)
	if [ "$before" = "$after" ]; then
		UPDATE_REPORT_PROJECT="already up to date at ${after:0:7}"
		return 0
	fi

	count=$(git -C "$XGHOST_ROOT" rev-list --count "$before..$after" 2>/dev/null || printf '0\n')
	UPDATE_REPORT_PROJECT="${before:0:7}..${after:0:7}, $count commits"
}

# Link the prescribed files the pull added.
#
# The linker adopts a link that is already right and refuses a path that holds
# something else, so this changes nothing for a file that was already linked. A
# refusal is reported and does not stop the update: it is a path the user has to
# decide about, and the packages and the render are still worth doing.
update_link() {
	local output status=0

	theme_repo_paths

	# The linker takes its source from the directory above its own file, and an
	# update has to link the configuration of the checkout it has just pulled.
	# The two are the same directory on an installed machine, and they are not
	# the same when a caller points XGHOST_ROOT somewhere else, so the source is
	# named here rather than left to whichever of the two the module found.
	export XGHOST_CONFIG_SOURCE=${XGHOST_CONFIG_SOURCE:-$XGHOST_ROOT/config}

	update_say "-- link the prescribed configuration"
	output=$(linker_link 2>&1) || status=$?
	printf '%s\n' "$output"

	if [ "$status" -ne 0 ]; then
		update_warn "the prescribed configuration is not fully linked; the report above names every path"
		UPDATE_REPORT_LINKS="a path is in the way; see the report above"
		return 1
	fi

	UPDATE_REPORT_LINKS=${output##*$'\n'}
}

# Update the system packages.
#
# An AUR helper updates the official packages and the AUR packages in one pass,
# so it is preferred when one is installed. A machine without one uses pacman,
# and pacman needs root.
#
# The command is not given '--noconfirm'. An update that removes a package or
# replaces one asks, and the person running it is the one who answers.
#
# Returns 1 when the packages were not updated.
update_packages() {
	local helper found= command_line before after status=0

	before=$(update_package_list) || before=

	for helper in $UPDATE_HELPERS; do
		if command -v "$helper" >/dev/null 2>&1; then
			found=$helper
			break
		fi
	done

	if [ -n "$found" ]; then
		command_line=("$found" -Syu)
	elif command -v pacman >/dev/null 2>&1; then
		command_line=(sudo pacman -Syu)
	else
		update_warn "neither an AUR helper nor pacman is installed, so the system packages were not updated"
		UPDATE_REPORT_PACKAGES="not updated: no package manager was found"
		return 1
	fi

	update_say "-- ${command_line[*]}"
	"${command_line[@]}" || status=$?

	if [ "$status" -ne 0 ]; then
		update_warn "'${command_line[*]}' ended with status $status, so the system packages are not fully updated"
		UPDATE_REPORT_PACKAGES="not updated: '${command_line[*]}' ended with status $status"
		return 1
	fi

	if [ -z "$before" ]; then
		UPDATE_REPORT_PACKAGES="updated with '${command_line[*]}'; pacman is not installed, so what changed was not read"
		return 0
	fi

	after=$(update_package_list) || after=
	UPDATE_REPORT_PACKAGES=$(update_package_difference "$before" "$after")
}

# Run the pending migrations.
update_migrations() {
	local mode=$1
	local status=0

	update_say "-- migrations"
	migrate_run_pending "$mode" || status=$?

	local applied=${#MIGRATE_APPLIED_NOW[@]}
	local skipped=${#MIGRATE_SKIPPED_NOW[@]}
	UPDATE_REPORT_MIGRATIONS="$applied applied, $skipped skipped"
	if [ "$applied" -gt 0 ]; then
		UPDATE_REPORT_MIGRATIONS="$UPDATE_REPORT_MIGRATIONS (applied: ${MIGRATE_APPLIED_NOW[*]})"
	fi
	if [ "$skipped" -gt 0 ]; then
		UPDATE_REPORT_MIGRATIONS="$UPDATE_REPORT_MIGRATIONS (skipped: ${MIGRATE_SKIPPED_NOW[*]})"
	fi
	if [ -n "$MIGRATE_STOPPED_AT" ]; then
		UPDATE_REPORT_MIGRATIONS="$UPDATE_REPORT_MIGRATIONS; stopped at $MIGRATE_STOPPED_AT"
	fi

	return "$status"
}

# Render the active theme again.
#
# The templates and the themes came out of the pull, so a render is what carries
# a changed template into the generated output. A machine with no theme yet has
# nothing to render, and that is not a failure: it is a machine that has never
# run 'xghost theme set'.
update_render() {
	local name before after

	if ! theme_state_paths; then
		update_warn "$THEME_PROBLEM"
		UPDATE_REPORT_GENERATED="not rendered: $THEME_PROBLEM"
		return 1
	fi

	before=$(update_fingerprint "$XGHOST_GENERATED_DIR")

	# A machine that has never set a theme is not a failure, and a machine whose
	# generated output is broken is one. The exit status of theme_current is 1
	# for both, so the two are told apart by the report it sets, exactly as
	# install/steps/config/30-theme.sh tells them apart. Reading the second as
	# the first would pass over a broken output in silence.
	if ! name=$(theme_current); then
		# The call above ran in a command substitution, and a command
		# substitution is a subshell, so the report it set never reached this
		# shell. theme_current only reads, so it is asked again here for the
		# report alone.
		theme_current >/dev/null 2>&1 || true

		update_say "-- $THEME_PROBLEM"
		UPDATE_REPORT_GENERATED="not rendered: $THEME_PROBLEM"
		case $THEME_PROBLEM in
		"no theme is active"*) return 0 ;;
		esac
		update_warn "$THEME_PROBLEM"
		return 1
	fi

	update_say "-- render the theme '$name'"
	if ! theme_set "$name"; then
		update_warn "$THEME_PROBLEM"
		UPDATE_REPORT_GENERATED="not rendered: $THEME_PROBLEM"
		return 1
	fi

	after=$(update_fingerprint "$XGHOST_GENERATED_DIR")

	if [ "$before" = "$after" ]; then
		UPDATE_REPORT_GENERATED="rendered '$name'; the output is unchanged"
	else
		UPDATE_REPORT_GENERATED="rendered '$name'; the output changed"
	fi
}

# Tell every component to read its configuration again.
#
# lib/reload.sh holds the components, the order and the mechanism of each one.
# This function is the update's frame around it: the heading, the report line,
# and the status.
#
# It returns 1 when a component that is running could not be reloaded. That is a
# change from the table this replaced, which returned 0 whatever happened: it
# reported a compositor whose reload had been REFUSED as one that was not
# running, so the one outcome worth acting on was the one it could not say. A
# component that is genuinely not running is still not a failed update, and it
# still returns 0.
update_reload() {
	local status=0

	update_say "-- reload the running components"
	reload_all || status=1
	UPDATE_REPORT_COMPONENTS=$RELOAD_SUMMARY

	return "$status"
}

# Print what this update changed.
#
# Every line is a comparison of a state before against a state after: the commit
# the checkout was on, the packages the machine had, the migrations that were
# pending, and the content of the generated output. A line that reports no
# change is a measurement, not a default.
update_report() {
	update_say ""
	update_say "what changed:"
	update_say "  project:     ${UPDATE_REPORT_PROJECT:-not read}"
	update_say "  links:       ${UPDATE_REPORT_LINKS:-not read}"
	update_say "  packages:    ${UPDATE_REPORT_PACKAGES:-not read}"
	update_say "  migrations:  ${UPDATE_REPORT_MIGRATIONS:-not read}"
	update_say "  generated:   ${UPDATE_REPORT_GENERATED:-not read}"
	update_say "  components:  ${UPDATE_REPORT_COMPONENTS:-not read}"
}

# Resolve what happens when a migration fails.
#
# 'ask' needs somebody to ask. An update runs from install.sh, from a timer and
# over a pipe as well as from a terminal, and a question nobody can answer is
# not a choice. So a run with no terminal resolves 'ask' to 'stop', which is the
# safe half of the two: stopping changes nothing more and the update is run
# again, while skipping would carry a failed system change past the render and
# the restart and end well.
update_resolve_failure_mode() {
	local mode=$1

	if [ "$mode" != ask ]; then
		printf '%s\n' "$mode"
		return 0
	fi

	# Whether there is somebody to ask is decided by opening the terminal, not
	# by testing its permissions. /dev/tty is readable to everyone, so a test of
	# the permission bits answers yes in a timer that has no controlling
	# terminal at all; the open is what fails there.
	if { : <"$XGHOST_MIGRATE_TTY"; } 2>/dev/null; then
		printf 'ask\n'
		return 0
	fi
	printf 'stop\n'
}

# The update.
#
# Returns 0 when every step did what it was asked. It returns 1 when a step
# reported a problem, and that includes a migration that was skipped: a skipped
# migration is a system change that did not happen, and an update that ended
# well over one would be an update that reported success it did not have.
update_main() {
	local mode=ask
	local status=0 step_status=0

	while [ $# -gt 0 ]; do
		case $1 in
		--on-failure)
			if [ $# -lt 2 ]; then
				update_warn "'--on-failure' needs one of 'ask', 'skip' or 'stop'"
				return 2
			fi
			mode=$2
			shift
			;;
		--on-failure=*)
			mode=${1#--on-failure=}
			;;
		*)
			update_warn "unknown option '$1'. Run 'xghost system update --help' for the options."
			return 2
			;;
		esac
		shift
	done

	case $mode in
	ask | skip | stop) ;;
	*)
		update_warn "'--on-failure' takes 'ask', 'skip' or 'stop', and it was given '$mode'"
		return 2
		;;
	esac

	mode=$(update_resolve_failure_mode "$mode")

	theme_repo_paths
	update_say "xghost updates from $XGHOST_ROOT"

	# The pull is the one step that stops the update, because every step after
	# it acts on the checkout it brings in.
	if ! update_pull; then
		UPDATE_REPORT_PROJECT=${UPDATE_REPORT_PROJECT:-"not updated: the pull failed"}
		update_report
		return 1
	fi

	update_link || status=1

	update_packages || status=1

	step_status=0
	update_migrations "$mode" || step_status=$?
	if [ "$step_status" -ne 0 ]; then
		status=1
		# A migration that was skipped is a reported failure and the update
		# carries on: the render and the restart are what put the new prescribed
		# files in front of the user. A run that stopped at a migration does not
		# carry on, because the machine is part way through a change.
		if [ -n "$MIGRATE_STOPPED_AT" ]; then
			update_warn "the update stopped at the migration $MIGRATE_STOPPED_AT, so nothing was rendered and no component was told to read its configuration again"
			update_warn "what to do: fix the problem the migration reported, then run 'xghost system update' again. Every migration is safe to run twice, so the ones that already ran do nothing the second time."
			update_report
			return 1
		fi
	fi

	update_render || status=1

	update_reload || status=1

	update_report

	if [ "$status" -ne 0 ]; then
		update_say ""
		update_warn "the update finished and at least one step reported a problem; the report above names it"
		return 1
	fi
}
