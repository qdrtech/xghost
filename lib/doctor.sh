#!/usr/bin/env bash
#
# The doctor: what this installation is, and what is wrong with it.
#
# The report is one section per check, in plain text, so a reader pastes the
# whole of it into an issue. It ends with the number of problems, and the exit
# status is built from that number rather than from the status of the last
# thing that ran.
#
# ## Every check is independent
#
# A doctor whose first failure hides the rest is worse than no doctor: the
# output still looks like a report, and the reader has no way to tell a section
# that found nothing from a section that never ran. So doctor_main runs each
# check as 'check || true'. That is not a swallowed error. Three things make it
# a design rather than a shortcut:
#
#   - The status of a check is not its report. Every problem a check found is
#     already in the output and counted in DOCTOR_PROBLEMS by the time it
#     returns, so its status carries nothing the reader needs.
#   - As the left operand of an OR list, errexit is suspended inside the check
#     and inside everything the check calls. A command that fails part way
#     through one check therefore cannot end the run, and cannot reach the next
#     check either.
#   - DOCTOR_PROBLEMS is what the exit status is built from, so a check that
#     found something is counted whatever it returned.
#
# The consequence is that no check may rely on errexit for its own correctness.
# Every one of them tests what it runs.
#
# ## What the doctor never does
#
# It reads. It writes one temporary directory, and it deletes it. It changes no
# file of the user, no file of the checkout, and nothing under the state
# directory. It signals no component of the running session, and it installs
# nothing.
#
# The one program it reaches outside this project is the package manager, and
# it is reached through XGHOST_DOCTOR_PACKAGE_QUERY so that a test can answer
# for it. See doctor_missing_packages.
#
# docs/doctor.md records what each check means, what "stale" is defined as, and
# what that definition cannot detect.
#
# Environment:
#   XGHOST_ROOT                    The checkout this reports on.
#   XGHOST_PACKAGES_DIR            The manifest directory. The tests use this.
#   XGHOST_DOCTOR_PACKAGE_QUERY    The program that answers which packages are
#                                  missing. The tests use this.
#   XGHOST_CONFIG_SOURCE           The prescribed configuration directory.
#   XGHOST_CONFIG_HOME             The config directory of the user.
#   XDG_STATE_HOME                 The state directory, resolved by lib/theme.sh.

# The include sentinel. A second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_DOCTOR_SOURCED:-}" ]; then
	return 0
fi
XGHOST_DOCTOR_SOURCED=1

# The environment may carry BASHOPTS or SHELLOPTS, and both change how the
# globs in this file behave. Normalise every option this file depends on.
shopt -u dotglob nocaseglob failglob
unset GLOBIGNORE
set +f

XGHOST_DOCTOR_LIB_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# theme.sh brings the renderer, the palette, the machine facts and the knobs
# with it, and it is the one module that resolves the state directory.
# shellcheck source=lib/theme.sh
. "$XGHOST_DOCTOR_LIB_DIR/theme.sh"
# shellcheck source=lib/linker.sh
. "$XGHOST_DOCTOR_LIB_DIR/linker.sh"
# install.sh owns the manifest reader and the package query. The doctor reports
# on the manifest the installer reads, so it reads it with the same function
# rather than with a second parser that drifts from the first.
# shellcheck source=lib/install.sh
. "$XGHOST_DOCTOR_LIB_DIR/install.sh"

# The name of the base package manifest, under the manifest directory.
readonly DOCTOR_BASE_MANIFEST=base.txt

# The width of the status column, so a detail line lines up under the text of
# the line above it.
readonly DOCTOR_STATUS_WIDTH=9

# The number of monitors this will list one by one. A machine facts file is a
# hand-edit surface, so a count it declares is a number a person may have
# mistyped, and a report is not the place to act on a mistyped number at
# length. A count above this is reported as a count.
readonly DOCTOR_MONITOR_LIMIT=64

# The escape sequences, and whether they are used. Set by
# doctor_resolve_colour.
readonly DOCTOR_RED=$'\033[31m'
readonly DOCTOR_GREEN=$'\033[32m'
readonly DOCTOR_RESET=$'\033[0m'
DOCTOR_COLOUR=no

# The number of problems the report holds. doctor_problem is the only thing
# that raises it, and the exit status is built from it.
DOCTOR_PROBLEMS=0

# The link record, read by doctor_check_links. It is a global because
# linker_read_record takes the name of an array, and a name that collides with
# the name of its own local would break the call.
DOCTOR_RECORD_LINES=()

doctor_say() {
	printf '%s\n' "$*"
}

doctor_warn() {
	printf '%s: %s\n' "$XGHOST_PROGRAM" "$*" >&2
}

# Decide whether the report carries colour.
#
# The question is whether standard output is a terminal, and '[ -t 1 ]' is the
# whole of it. It is deliberately not a test of /dev/tty: that file is mode
# 0666, so a permission test on it answers yes inside a process that has no
# controlling terminal at all. This report is read from a pipe, from a file and
# from a terminal, and an escape sequence in the first two is text the reader
# has to strip out of an issue by hand.
doctor_resolve_colour() {
	if [ -t 1 ]; then
		DOCTOR_COLOUR=yes
	else
		DOCTOR_COLOUR=no
	fi
}

# Print one word in one colour, or plain when there is no terminal.
#
#   doctor_paint COLOUR TEXT
doctor_paint() {
	local colour=$1 text=$2

	if [ "$DOCTOR_COLOUR" != yes ]; then
		printf '%s' "$text"
		return 0
	fi
	printf '%s%s%s' "$colour" "$text" "$DOCTOR_RESET"
}

# Open one section of the report.
doctor_section() {
	printf '\n%s\n' "$1"
}

# One line that states a fact rather than a verdict.
#
#   doctor_fact LABEL VALUE
doctor_fact() {
	printf '  %-*s %s\n' "$DOCTOR_STATUS_WIDTH" "$1:" "$2"
}

# One line that reports a check that found nothing wrong.
doctor_ok() {
	printf '  %-*s %s\n' "$DOCTOR_STATUS_WIDTH" \
		"$(doctor_paint "$DOCTOR_GREEN" ok)" "$*"
}

# One line that reports a problem, and the one thing that counts one.
doctor_problem() {
	DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
	printf '  %-*s %s\n' "$DOCTOR_STATUS_WIDTH" \
		"$(doctor_paint "$DOCTOR_RED" problem)" "$*"
}

# One line that carries the detail of the line above it. It is not a verdict of
# its own, so it is never counted.
doctor_detail() {
	printf '  %*s %s\n' "$DOCTOR_STATUS_WIDTH" '' "$*"
}

# The value of one machine fact, or a word that says it was never recorded.
#
# The two are told apart, because 'unknown' and 'none' are values the file
# declares on purpose, and a key that is not in the file at all is a different
# thing: a file written by an older detection, or edited by hand.
doctor_fact_value() {
	local key=$1

	if [ -n "${FACTS_SCALARS[$key]+set}" ]; then
		printf '%s' "${FACTS_SCALARS[$key]}"
		return 0
	fi
	printf 'not recorded'
}

# --- the checks ---------------------------------------------------------------

# What this installation is: the checkout, the version, the active theme and a
# summary of the machine facts.
#
# Criterion 6 of the issue. Returns 1 when it reported a problem.
doctor_check_project() {
	local status=0

	theme_repo_paths
	doctor_section "this installation"
	doctor_fact checkout "$XGHOST_ROOT"

	doctor_report_version || status=1
	doctor_report_theme || status=1
	doctor_report_facts || status=1

	return "$status"
}

# The version of the project.
#
# This project ships no version number and no release process, so there is
# nothing to print that a release would define. What is true about this
# checkout is which commit it is on and whether it carries work of its own, and
# that is what 'git describe --tags --always --dirty' prints: the nearest tag
# when a tag exists, and the short commit when none does, with '-dirty' when a
# tracked file has been changed.
#
# A number such as '1.0.0' would be an invention, and it would tell a reader
# that a release exists to compare their machine against. docs/doctor.md
# records this.
doctor_report_version() {
	local version root=$XGHOST_ROOT

	if ! command -v git >/dev/null 2>&1; then
		doctor_problem "the version cannot be read: the 'git' program is not installed"
		return 1
	fi
	if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
		doctor_problem "the version cannot be read: $root is not a git working tree"
		doctor_detail "what to do: install the project again with boot.sh, so that the checkout is one git made."
		return 1
	fi
	if ! version=$(git -C "$root" describe --tags --always --dirty 2>/dev/null) ||
		[ -z "$version" ]; then
		doctor_problem "the version cannot be read: the checkout at $root has no commit"
		return 1
	fi

	doctor_fact version "$version"
}

# The theme that is active.
doctor_report_theme() {
	local name

	if name=$(theme_current); then
		doctor_fact theme "$name"
		return 0
	fi

	# theme_current ran in a command substitution, and a command substitution
	# is a subshell, so the problem it set never reached this shell. It only
	# reads, so it is asked again here for the report alone. lib/update.sh does
	# the same thing at update_render and for the same reason.
	theme_current >/dev/null 2>&1 || true
	doctor_problem "$THEME_PROBLEM"
	return 1
}

# A summary of the machine facts.
doctor_report_facts() {
	local file problem count index name mode scale summary=
	local -a monitors=()

	if ! file=$(facts_path); then
		doctor_problem "the machine facts have no home: $FACTS_NO_HOME_MESSAGE"
		return 1
	fi

	doctor_fact facts "$file"

	if ! facts_load "$file"; then
		doctor_problem "the machine facts cannot be read"
		for problem in "${FACTS_ERRORS[@]}"; do
			doctor_detail "$problem"
		done
		doctor_detail "what to do: run 'xghost machine detect' inside a Hyprland session."
		return 1
	fi

	count=$(doctor_fact_value MACHINE_MONITOR_COUNT)
	if [[ $count =~ ^[0-9]+$ ]] && [ "$count" -le "$DOCTOR_MONITOR_LIMIT" ]; then
		for ((index = 1; index <= count; index++)); do
			name=$(doctor_fact_value "MACHINE_MONITOR_${index}_NAME")
			mode=$(doctor_fact_value "MACHINE_MONITOR_${index}_MODE")
			scale=$(doctor_fact_value "MACHINE_MONITOR_${index}_SCALE")
			monitors+=("$name $mode scale $scale")
		done
	fi

	if [ "${#monitors[@]}" -gt 0 ]; then
		# The list is joined by hand. '${monitors[*]}' would join it with the
		# first character of IFS alone, so a separator of more than one
		# character reaches the report as one character of it.
		for name in "${monitors[@]}"; do
			if [ -z "$summary" ]; then
				summary=$name
			else
				summary="$summary; $name"
			fi
		done
		doctor_fact monitors "$count: $summary"
	else
		doctor_fact monitors "$count"
	fi

	doctor_fact input "keyboard $(doctor_fact_value MACHINE_KEYBOARD_LAYOUT), variant $(doctor_fact_value MACHINE_KEYBOARD_VARIANT), timezone $(doctor_fact_value MACHINE_TIMEZONE)"
	doctor_fact session "compositor $(doctor_fact_value MACHINE_COMPOSITOR), browser $(doctor_fact_value MACHINE_BROWSER), terminal $(doctor_fact_value MACHINE_TERMINAL)"
}

# Every prescribed file that has been changed on this machine, by path.
#
# Criterion 2 of the issue. A prescribed file is symbolically linked out of the
# checkout, so "modified" is a question about the working tree of that
# checkout and not about the config directory: the file the desktop reads is
# the file git is tracking. 'git status' over the prescribed directory answers
# it, and it answers it for a file that was edited through the link exactly as
# it does for one edited in the checkout.
#
# The pathspec is the prescribed directory alone. A change anywhere else in the
# checkout is not a prescribed file, so it is not reported here; the '-dirty'
# of the version line above is what says the checkout carries work of its own.
#
# Returns 1 when it reported a problem.
doctor_check_prescribed() {
	local dir top report entry code path dropped state
	local tracked=0 found=0

	doctor_section "prescribed configuration"

	# The prescribed directory is resolved here rather than by
	# linker_resolve_paths, and the reason is independence. That function
	# resolves the state directory as well, and it refuses the whole run when
	# the state directory has no home. This check never reads the state
	# directory, so a machine with no home for it would lose a report it could
	# have had. The rule below is the one the linker uses for its source, and
	# it is the same line update_link writes for the same reason.
	theme_repo_paths
	dir=${XGHOST_CONFIG_SOURCE:-$XGHOST_ROOT/config}

	if [ ! -d "$dir" ]; then
		doctor_problem "the prescribed configuration directory does not exist: $dir"
		return 1
	fi
	if ! command -v git >/dev/null 2>&1; then
		doctor_problem "not checked: the 'git' program is not installed, so a modified prescribed file cannot be found"
		doctor_detail "a prescribed file is tracked by git, and git is what says whether one has been changed."
		return 1
	fi
	if ! top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || [ -z "$top" ]; then
		doctor_problem "not checked: $dir is not inside a git working tree, so a modified prescribed file cannot be found"
		doctor_detail "what to do: install the project again with boot.sh, so that the checkout is one git made."
		return 1
	fi

	# The status is captured before it is read, so a git that failed is a
	# problem this reports rather than an empty loop that reads as a clean
	# tree. A pipeline would leave the loop with no line, and a git that could
	# not answer would then look exactly like a checkout with nothing changed.
	report=$(mktemp) || {
		doctor_problem "not checked: cannot create a temporary file to read the status of the checkout into"
		return 1
	}
	if ! git -C "$dir" status --porcelain -z -- . >"$report" 2>/dev/null; then
		rm -f -- "$report"
		doctor_problem "not checked: 'git status' failed in $dir"
		return 1
	fi

	tracked=$(git -C "$dir" ls-files -- . 2>/dev/null | grep -c . || true)

	while IFS= read -r -d '' entry; do
		code=${entry:0:2}
		path=${entry:3}

		# A rename and a copy carry a second path, which is where the file
		# came from. It is read here so that it is never read as a record of
		# its own, and it is dropped: the path the file is at now is the one a
		# reader needs.
		case $code in
		R* | C*)
			IFS= read -r -d '' dropped || dropped=
			;;
		esac

		case $code in
		'??') state=untracked ;;
		D* | ?D) state=deleted ;;
		R* | C*) state=renamed ;;
		*) state=modified ;;
		esac

		# The path of a '--porcelain' record is relative to the root of the
		# repository, whatever directory git was run in and whatever
		# 'status.relativePaths' holds. Joining it to the prescribed directory
		# instead would print a path that is not on this machine.
		found=$((found + 1))
		doctor_problem "$state: $top/$path"
	done <"$report"

	rm -f -- "$report"

	if [ "$found" -gt 0 ]; then
		doctor_detail "a prescribed file belongs to the project. What to do: run 'git -C $top checkout --' on the paths above to take the prescribed file back, or open an issue for the change you need."
		return 1
	fi

	doctor_ok "no prescribed file is modified; $tracked files are tracked under $dir"
}

# The packages of the manifest this machine does not have.
#
# Criterion 3 of the issue. install/packages/base.txt is the manifest, and
# install/packages/aur.txt beside it is not read here: a machine with no AUR
# helper finishes its installation without those packages and is told so, so
# reporting them as missing would report a state the installer produces on
# purpose. docs/doctor.md records that limit.
#
# Returns 1 when it reported a problem.
doctor_check_packages() {
	local file manifest report name
	local -a packages=() missing=()

	doctor_section "dependencies"

	theme_repo_paths
	file=${XGHOST_PACKAGES_DIR:-$XGHOST_ROOT/install/packages}/$DOCTOR_BASE_MANIFEST

	if ! manifest=$(install_read_manifest "$file"); then
		doctor_problem "not checked: the base package manifest cannot be read: $file"
		doctor_detail "every problem of that file is named above."
		return 1
	fi

	while IFS= read -r name; do
		if [ -n "$name" ]; then
			packages+=("$name")
		fi
	done <<<"$manifest"

	if [ "${#packages[@]}" -eq 0 ]; then
		doctor_problem "the base package manifest declares no package: $file"
		return 1
	fi

	if ! report=$(doctor_missing_packages "${packages[@]}"); then
		doctor_problem "not checked: the packages this machine is missing could not be read"
		doctor_detail "the reason is named above. ${#packages[@]} packages are declared in $file."
		return 1
	fi

	while IFS= read -r name; do
		if [ -n "$name" ]; then
			missing+=("$name")
		fi
	done <<<"$report"

	if [ "${#missing[@]}" -eq 0 ]; then
		doctor_ok "every one of the ${#packages[@]} packages of $file is installed"
		return 0
	fi

	doctor_problem "${#missing[@]} of the ${#packages[@]} packages of $file are not installed"
	for name in "${missing[@]}"; do
		doctor_detail "$name"
	done
	doctor_detail "what to do: run './install.sh' again, or install them with 'sudo pacman -S --needed -- ${missing[*]}'."
	return 1
}

# Print the packages of the argument list this machine does not have, one per
# line.
#
# The package manager is the one program outside this project that the doctor
# reaches, and calling it directly would make this command untestable: a test
# would have to either query the real database of the machine running it, which
# answers differently on every machine, or shadow pacman on the PATH, which is
# a stub of a program rather than an answer to a question. So the query is
# injected.
#
# XGHOST_DOCTOR_PACKAGE_QUERY names a program. It is called with every declared
# package name as an argument, it prints the names that are not installed one
# per line, and it ends 0 when it answered. Any other status is a query that
# could not answer, and the check above reports that rather than reporting that
# nothing is missing.
#
# With the variable unset, install_missing_packages answers, which is 'pacman
# -T' and is the same function the packaging step of the installer uses. A
# machine with no pacman is a query that could not answer, and that is what it
# reports: reading it as "nothing is missing" would tell a user their
# dependencies are in place on a machine that cannot say.
doctor_missing_packages() {
	if [ -n "${XGHOST_DOCTOR_PACKAGE_QUERY:-}" ]; then
		"$XGHOST_DOCTOR_PACKAGE_QUERY" "$@"
		return
	fi
	install_missing_packages "$@"
}

# Whether the generated output is there, and whether it is what the inputs
# would produce now.
#
# Criterion 4 of the issue, and "stale" is the word that had to be defined.
#
#   The generated output is stale when a fresh render of the active theme,
#   from the templates, the palette, the machine facts and the knobs this
#   machine holds right now, does not match the tree the stable path points
#   at, file for file and byte for byte.
#
# So this renders the whole tree again into a temporary directory and compares
# the two. It is the honest answer and it is not the cheap one: it costs what a
# theme switch costs. It needs no state of its own, it works against a build
# made by any earlier version of this project, and it catches a generated file
# somebody edited by hand as well as one the inputs have moved past.
#
# docs/doctor.md states what this definition cannot detect. The short of it:
# it compares files against files, so a machine facts file that no longer
# describes the machine, and a component still running with the previous
# configuration in memory, are both invisible to it.
#
# Returns 1 when it reported a problem.
doctor_check_generated() {
	local work status=0

	doctor_section "generated output"

	if ! work=$(mktemp -d 2>/dev/null); then
		doctor_problem "not checked: cannot create a temporary directory to render into"
		return 1
	fi

	doctor_generated_body "$work" || status=1
	rm -rf -- "$work"

	return "$status"
}

# The body of doctor_check_generated, with a temporary directory to render
# into. The caller removes that directory whatever this returns.
doctor_generated_body() {
	local work=$1
	local name live theme_dir facts_file= knobs_file= problem

	if ! theme_state_paths; then
		doctor_problem "not checked: $THEME_PROBLEM"
		return 1
	fi

	if ! name=$(theme_current); then
		# The subshell of the command substitution kept the problem it set. It
		# only reads, so it is asked again for the report.
		theme_current >/dev/null 2>&1 || true
		doctor_problem "$THEME_PROBLEM"
		return 1
	fi

	live=$(readlink -f "$XGHOST_GENERATED_DIR" 2>/dev/null || true)
	if [ -z "$live" ] || [ ! -d "$live" ]; then
		doctor_problem "the generated output is missing: $XGHOST_GENERATED_DIR points at no directory"
		doctor_detail "what to do: run 'xghost theme set $name'."
		return 1
	fi

	theme_repo_paths
	theme_dir=$XGHOST_THEMES_DIR/$name
	if [ ! -d "$theme_dir" ] || [ ! -f "$theme_dir/$THEME_PALETTE_FILE" ]; then
		doctor_problem "the active theme '$name' is not installed in $XGHOST_THEMES_DIR, so the output cannot be compared against a fresh render"
		return 1
	fi

	# The two inputs that belong to the user. They are resolved exactly as
	# theme_set resolves them, so the render below reads what a real switch
	# would read. Anything at either path is passed on whatever it is, because
	# the renderer names a broken file better than a test here would.
	if ! facts_file=$(facts_path) ||
		{ [ ! -e "$facts_file" ] && [ ! -L "$facts_file" ]; }; then
		facts_file=
	fi
	if ! knobs_file=$(knobs_path) ||
		{ [ ! -e "$knobs_file" ] && [ ! -L "$knobs_file" ]; }; then
		knobs_file=
	fi

	if ! render_tree "$XGHOST_TEMPLATE_DIR" "$theme_dir" "$facts_file" \
		"$XGHOST_KNOBS_SCHEMA" "$knobs_file" "$work/tree"; then
		doctor_problem "not checked: the theme '$name' cannot be rendered, so there is nothing to compare the output against"
		for problem in "${RENDER_ERRORS[@]}"; do
			doctor_detail "$problem"
		done
		return 1
	fi

	# The wallpaper file is written by lib/theme.sh rather than by the
	# renderer, because the path inside it is the stable path of the generated
	# output and only that module knows it. A comparison that left it out would
	# report every installation as holding a file no render produces, so the
	# same two steps a switch takes are taken here. That couples this check to
	# the two steps of theme_set_locked, and docs/doctor.md records the
	# coupling: a third step added there has to be added here too.
	if ! theme_write_wallpaper "$work/tree"; then
		doctor_problem "not checked: $THEME_PROBLEM"
		return 1
	fi

	doctor_compare_trees "$work/tree" "$live" "$name"
}

# Compare a freshly rendered tree against the tree the desktop is reading.
#
#   doctor_compare_trees FRESH LIVE NAME
#
# Returns 1 when they differ, and names every file that does.
doctor_compare_trees() {
	local fresh=$1 live=$2 name=$3
	local relative
	local -a missing=() different=() extra=()
	local count=0

	while IFS= read -r relative; do
		[ -n "$relative" ] || continue
		count=$((count + 1))
		if [ ! -e "$live/$relative" ] && [ ! -L "$live/$relative" ]; then
			missing+=("$relative")
			continue
		fi
		if ! doctor_same_file "$fresh/$relative" "$live/$relative"; then
			different+=("$relative")
		fi
	done < <(doctor_tree_entries "$fresh")

	while IFS= read -r relative; do
		[ -n "$relative" ] || continue
		if [ ! -e "$fresh/$relative" ] && [ ! -L "$fresh/$relative" ]; then
			extra+=("$relative")
		fi
	done < <(doctor_tree_entries "$live")

	if [ "${#missing[@]}" -eq 0 ] && [ "${#different[@]}" -eq 0 ] &&
		[ "${#extra[@]}" -eq 0 ]; then
		doctor_ok "the output matches a fresh render of the theme '$name'; $count files"
		return 0
	fi

	doctor_problem "the generated output is stale: ${#missing[@]} missing, ${#different[@]} different, ${#extra[@]} that no render produces"
	for relative in ${missing[@]+"${missing[@]}"}; do
		doctor_detail "missing: $relative"
	done
	for relative in ${different[@]+"${different[@]}"}; do
		doctor_detail "differs: $relative"
	done
	for relative in ${extra[@]+"${extra[@]}"}; do
		doctor_detail "no render produces it: $relative"
	done
	doctor_detail "what to do: run 'xghost theme set $name' to render the output again. The paths above are under $XGHOST_GENERATED_DIR."
	return 1
}

# Print the path of every file and every link of one tree, relative to that
# tree, sorted.
doctor_tree_entries() {
	local dir=$1
	local path

	if [ ! -d "$dir" ]; then
		return 0
	fi

	# The prefix is stripped by the shell rather than by sed. The path of the
	# directory reaches sed as a regular expression, and a state directory that
	# holds a '.' or a '+' would then strip something else. It is stripped
	# without a 'cd' as well, so this function has no working directory of its
	# own to fail to reach.
	find "$dir" \( -type f -o -type l \) -print |
		while IFS= read -r path; do
			printf '%s\n' "${path#"$dir/"}"
		done |
		LC_ALL=C sort
}

# Whether two paths of the two trees hold the same thing.
#
# A link is compared by the text of its target and a file by its bytes. The two
# are never compared against one another: a link and a regular file are two
# different things at one path, whatever the link points at.
doctor_same_file() {
	local left=$1 right=$2

	if [ -L "$left" ] || [ -L "$right" ]; then
		[ -L "$left" ] && [ -L "$right" ] || return 1
		[ "$(readlink -- "$left")" = "$(readlink -- "$right")" ]
		return
	fi
	cmp -s -- "$left" "$right"
}

# The links this project made: the ones that are gone, the ones that point
# somewhere else, and the ones whose target is not there.
#
# Criterion 5 of the issue. Those three are three different faults and a reader
# has to know which one they have, so each is named in its own words:
#
#   missing          nothing is at the path at all.
#   not a link       something else is at the path.
#   points elsewhere the link is there and it points at something other than
#                    the prescribed entry the record names.
#   target is gone   the link is right and the file it points at is not there.
#   not linked       a prescribed entry that the record does not mention.
#
# Returns 1 when it reported a problem.
doctor_check_links() {
	local line destination source what path base target
	local ok=0 found=0

	doctor_section "symbolic links"

	if ! linker_resolve_paths; then
		doctor_problem "the links cannot be checked; the report above names the path"
		return 1
	fi

	if [ ! -e "$LINKER_RECORD" ] && [ ! -L "$LINKER_RECORD" ]; then
		doctor_problem "nothing is linked: there is no link record at $LINKER_RECORD"
		doctor_detail "what to do: run 'xghost config link'."
		return 1
	fi
	if [ ! -f "$LINKER_RECORD" ]; then
		what=$(linker_describe "$LINKER_RECORD")
		doctor_problem "the link record $LINKER_RECORD is $what; it has to be a regular file"
		return 1
	fi

	DOCTOR_RECORD_LINES=()
	if ! linker_read_record DOCTOR_RECORD_LINES; then
		doctor_problem "the link record cannot be read: $LINKER_RECORD"
		return 1
	fi

	for line in ${DOCTOR_RECORD_LINES[@]+"${DOCTOR_RECORD_LINES[@]}"}; do
		destination=${line%%$'\t'*}
		source=${line#*$'\t'}
		[ -n "$destination" ] || continue

		if [ "$source" = "$line" ] || [ -z "$source" ]; then
			found=$((found + 1))
			doctor_problem "the link record holds a line with no prescribed path: $destination"
			continue
		fi

		if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
			found=$((found + 1))
			doctor_problem "missing: $destination is not there; it should link to $source"
			continue
		fi
		if [ ! -L "$destination" ]; then
			what=$(linker_describe "$destination")
			found=$((found + 1))
			doctor_problem "not a link: $destination is $what; it should link to $source"
			continue
		fi
		if ! linker_link_matches "$destination" "$source"; then
			target=$(readlink -- "$destination" 2>/dev/null) || target='a target that cannot be read'
			found=$((found + 1))
			doctor_problem "points elsewhere: $destination links to $target; the record says $source"
			continue
		fi
		if [ ! -e "$source" ]; then
			found=$((found + 1))
			doctor_problem "the target is gone: $destination links to $source, and nothing is there"
			continue
		fi
		ok=$((ok + 1))
	done

	# A prescribed entry the record never mentions is a link that was never
	# made. It is a missing link as much as one that was removed, and the
	# record alone cannot report it, because the record holds what the linker
	# created and not what it should have created.
	if [ -d "$LINKER_SOURCE_DIR" ]; then
		for path in "$LINKER_SOURCE_DIR"/*; do
			[ -e "$path" ] || [ -L "$path" ] || continue
			base=${path##*/}
			if doctor_record_holds "$LINKER_CONFIG_HOME/$base"; then
				continue
			fi
			found=$((found + 1))
			doctor_problem "not linked: $LINKER_CONFIG_HOME/$base is in no link record; the prescribed entry is $path"
		done
	fi

	# The bridge to the generated output. Nothing in the prescribed directory
	# stands behind it, and every relative include of this project resolves
	# through it, so a report that left it out would pass over the one link
	# whose absence makes every include miss in silence.
	if ! doctor_record_holds "$LINKER_CONFIG_HOME/$LINKER_BRIDGE_NAME"; then
		found=$((found + 1))
		doctor_problem "not linked: $LINKER_CONFIG_HOME/$LINKER_BRIDGE_NAME is in no link record; it is the bridge every include of the generated output resolves through"
	fi

	if [ "$found" -gt 0 ]; then
		doctor_detail "what to do: run 'xghost config link'. It refuses a path that holds something else, and '--backup' moves such a path aside."
		return 1
	fi

	doctor_ok "$ok links are in place"
}

# Whether the link record holds a line for one destination path.
doctor_record_holds() {
	local wanted=$1 line

	for line in ${DOCTOR_RECORD_LINES[@]+"${DOCTOR_RECORD_LINES[@]}"}; do
		if [ "${line%%$'\t'*}" = "$wanted" ]; then
			return 0
		fi
	done
	return 1
}

# --- the report ---------------------------------------------------------------

# The doctor.
#
# Criterion 1 of the issue: it ends non-zero when something is wrong. The
# status is built from the number of problems the report holds, because a
# doctor that ended with the status of whatever ran last would end well over a
# report full of problems, and a test of "the command succeeded" would never
# notice.
doctor_main() {
	local argument

	for argument in "$@"; do
		case $argument in
		*)
			doctor_warn "unknown option '$argument'. Run 'xghost system doctor --help' for what this command does."
			return 2
			;;
		esac
	done

	doctor_resolve_colour
	DOCTOR_PROBLEMS=0

	doctor_say "xghost doctor"

	# Each check is run for its report and never for its status. The '|| true'
	# is what makes the independence of the checks a fact rather than an
	# intention: as the left operand of an OR list, errexit is suspended inside
	# the check and inside everything it calls, so a command that fails part
	# way through one of them can neither end the run nor reach the next check.
	# Every problem is already counted in DOCTOR_PROBLEMS by then, and that
	# count is what the exit status below is built from.
	doctor_check_project || true
	doctor_check_prescribed || true
	doctor_check_packages || true
	doctor_check_generated || true
	doctor_check_links || true

	doctor_say ""
	if [ "$DOCTOR_PROBLEMS" -eq 0 ]; then
		doctor_say "no problem found"
		return 0
	fi
	if [ "$DOCTOR_PROBLEMS" -eq 1 ]; then
		doctor_say "1 problem"
	else
		doctor_say "$DOCTOR_PROBLEMS problems"
	fi
	return 1
}
