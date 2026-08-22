#!/usr/bin/env bash
#
# The reload: how a file this project has just written reaches a running desktop.
#
# A theme switch and a knob change both end the same way. The renderer builds a
# whole tree, one rename moves it into place, and every configuration file the
# desktop reads is new. Nothing has looked at any of them. This module is the
# step that asks.
#
# ## Ask whether it is running, then tell it
#
# Every component is reloaded in two steps, and the order of the two is the
# whole design:
#
#   1. Ask whether a process of that name belongs to this user. 'pgrep' answers,
#      and it changes nothing.
#   2. Only then run the command that tells that process to read its
#      configuration again.
#
# Asking first is not a tidiness. Three separate faults follow from telling
# first, and this project met all three:
#
#   - **It cannot tell a component that is absent from one that refused.** A
#     command that failed for any reason at all reads as "not running", so a
#     compositor that IS running and whose reload was REFUSED is reported as
#     absent. That was the shape of update_restart_one, which this module
#     replaces.
#   - **It can start a daemon nobody started.** SwayNC ships
#     /usr/share/dbus-1/services/org.erikreider.swaync.cc.service, which names
#     'Exec=/usr/bin/swaync'. That service is activatable, so 'swaync-client -rs'
#     on a session with no notification daemon does not fail: the bus starts one.
#     A reload that installs a daemon is not a reload.
#   - **It can hang.** 'swaync-client' waits for the daemon by default; the
#     option that turns the wait off is '-sw', and swaync-client takes one
#     option per run, so it cannot be combined with '-rs'. The packaged systemd
#     unit runs '--reload-config' and '--reload-css' as two separate commands
#     for the same reason. The probe is what keeps the wait from ever starting.
#
# ## The five answers, and which of them is a problem
#
#   reloaded         The process was there and the command succeeded.
#   not running      No process of that name belongs to this user. Not a
#                    problem: a desktop that is not running cannot be shown
#                    anything.
#   nothing to send  The process is there, and this build holds nothing for it
#                    to read. Not a problem either, and the reason is in
#                    RELOAD_DETAIL. Today this is the wallpaper of a build that
#                    drew no image, which is a state lib/background.sh
#                    supports: a machine whose facts carry no resolution, or a
#                    palette that declares no colour to draw with. Reporting a
#                    supported state as a fault is the thing the probe was
#                    built to stop, so it is not 'failed'.
#   no command       The process IS there and the program that reloads it is
#                    not installed. That is a problem, because the change will
#                    not be seen and nothing else will say so.
#   failed           The process is there, the command ran, and it returned
#                    non-zero. The status and the first line of its output are
#                    carried in RELOAD_DETAIL.
#
# A command that fails and whose process has gone in the meantime is reported as
# 'not running' rather than 'failed'. The probe runs a second time to decide
# that, so the race between the two steps resolves to the truth rather than to
# whichever step ran first. This is why 'pkill' needs no rule of its own: its
# exit 1 means "matched nothing", and the second probe is what turns that back
# into "not running".
#
# ## Every component is independent
#
# reload_all runs each component as the left operand of an OR list. As in
# lib/doctor.sh, that is a design rather than a swallowed error: errexit is
# suspended inside reload_one and inside everything it calls, so a component
# that fails cannot end the run and cannot stop the components after it. The
# count in RELOAD_PROBLEMS is what the caller's exit status is built from, not
# the status of the last thing that ran.
#
# ## Adding a component
#
# One row of RELOAD_COMPONENTS, and one row of the table in docs/reloading.md.
# There is no second list, no case statement and no per-component function. That
# is acceptance criterion 9 of issue #24, and tests/reload.bats proves it by
# adding a fictional component to a copy of this file, changing nothing else,
# and reloading it.
#
# ## A command that has to carry a value this file cannot write down
#
# One component needs one. The wallpaper daemon has no reload request at all:
# 'hyprctl hyprpaper wallpaper' SETS a wallpaper, so it has to be told which
# image, and the image is a file of the generated output. That path cannot be
# written into the table, for two reasons that are both about the table rather
# than about the daemon:
#
#   - RELOAD_COMPONENTS is readonly and it is built when this file is sourced,
#     and the state directory of the user is resolved later.
#   - The path runs through XDG_STATE_HOME, so a user may point it at a
#     directory whose name holds a space, and the command is split on white
#     space.
#
# So a command may carry a value of the form @NAME@. RELOAD_VALUES names each
# one and the function that resolves it, reload_check_row refuses a row that
# carries a name no function answers, and reload_expand puts the value in.
#
# **The value is put in AFTER the command is split**, one word at a time, so a
# value holding a space is one argument and stays one argument. That is the
# whole reason the expansion is not a substitution on the command string: this
# is the first value of this project that a user can put a space in, and a
# request that named half a path would be a request to draw a file that is not
# there. tests/reload.bats sets XDG_STATE_HOME to a directory whose name holds
# a space and counts the arguments the program received.
#
# A value is not a placeholder of the renderer. It reads no palette, no knob
# and no machine fact; it is resolved by the named function of this file, and
# that function is what knows where to look.
#
# ## The switch, and why it exists
#
# XGHOST_RELOAD=no turns the reload off. It is reported on the line where the
# components would have been, so a run with it set never reads like a run that
# found nothing to do.
#
# It is not a convenience. Every suite of this project renders a theme, and this
# module is now what a render ends with, so without a switch the test suite of a
# machine that runs this desktop would reload that desktop, once per test. That
# is the second half of the safety rule below: the stubs stop the module this
# file is tested through, and the switch stops the eighteen suites that reach it
# through 'xghost theme set' by way of something else. tests/setup_suite.bash
# sets it for the whole suite, and the two suites that mean to reload turn it
# back on with a stub of every program first on the PATH.
#
# It answers a second question at the same time, which is whether the reload
# should be automatic. It is: a theme change that needs a second command is a
# theme change nobody sees. The switch is the opt out, for a run that renders
# for a session other than the one it is in.
#
# Only 'yes' and 'no' are values. Any other value is reported and the reload
# does not run, which is the conservative half: a value nobody meant to write
# stops a signal rather than sending one.
#
# ## What this module never does
#
# It signals nothing that is not already running, it starts nothing, and it
# writes no file. It reads one, and only to ask whether it is there: the image
# of the build, which is what says whether there is a wallpaper to set. Every
# effect it has leaves through a program named on the PATH: 'pgrep', 'pkill',
# 'hyprctl' and 'swaync-client'. The tests put a stub of each first on the
# PATH, so no test of this project reloads a live session.
#
# docs/reloading.md records the table, what each component reloads, and the
# three components of this desktop that need no signal at all.
#
# Environment:
#   XGHOST_RELOAD   'yes' to reload, 'no' not to. The default is 'yes'.
#   XDG_STATE_HOME  Where the generated output is, read through lib/paths.sh.
#                   The wallpaper request names a file of it.
#   HOME            The directory the fallback for that one is built from.

# The include sentinel. A second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_RELOAD_SOURCED:-}" ]; then
	return 0
fi
XGHOST_RELOAD_SOURCED=1

# The environment may carry BASHOPTS or SHELLOPTS, and both change how the
# globs in this file behave. Normalise every option this file depends on.
shopt -u dotglob nocaseglob failglob
unset GLOBIGNORE
set +f

XGHOST_RELOAD_LIB_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Two rules this file needs and does not own. Neither module runs anything when
# it is sourced.
#
#   paths.sh       Where the generated output is. lib/theme.sh reads the same
#                  rule from the same file, so the path this module names in a
#                  request is the path that module rendered to.
#   background.sh  Which file of that output is the image, and which one says
#                  why a build holds none.
#
# 'commands/system-reload' sources this file and nothing else, so a rule this
# module needed and could not reach would become a third copy of it. There is
# no third copy: the file that owns each rule is sourced here.
# shellcheck source=lib/paths.sh
. "$XGHOST_RELOAD_LIB_DIR/paths.sh"
# shellcheck source=lib/background.sh
. "$XGHOST_RELOAD_LIB_DIR/background.sh"

# The components this reloads, in the order it reloads them.
#
# Each row is four fields separated by a vertical bar:
#
#   name      What the report calls this component.
#   process   The process name to look for, exactly as the kernel holds it.
#             'Hyprland' carries a capital H, and 'pgrep -x' is exact.
#   program   The program that must be installed for the command to run.
#   command   The command that tells the running process to read its
#             configuration again.
#
# Three rules the fields have to keep, each one measured rather than assumed:
#
#   - **No field may be empty.** 'pgrep' with no pattern at all matches every
#     process of the user, so an empty process field would report every
#     component as running, and the matching 'pkill' would signal the whole
#     session. reload_check_row refuses such a row by name rather than running
#     it.
#   - **A process name is at most 15 characters.** That is the length the kernel
#     keeps, and 'pgrep -x' on a longer one matches nothing and says so on
#     standard error. reload_check_row refuses it here instead.
#   - **The command has to start with the program.** The program field is what
#     is tested for existence and the command is what runs, so a row where the
#     two disagree would test one program and run another: an installed
#     component would be reported as having no command, or a missing one would
#     be run. reload_check_row compares them.
#
# The command is split on white space, so no argument written here may hold a
# space. A value the command carries may: it is put in after the split, and a
# value that holds a space is one argument. See the header.
#
# A fourth rule follows from that: **every @NAME@ the command carries has to be
# one RELOAD_VALUES names.** A name nothing answers would be sent to the
# program as itself, and the request would name a file called '@NAME@'.
# reload_check_row refuses such a row rather than running it.
#
# The compositor is first because its reload is the one that can change the
# geometry every other surface is drawn into. The order of the rest does not
# matter, and it is fixed so that two runs produce the same report.
#
# '-u $EUID' is on the probe and on the signal for one reason: the two have to
# ask about the same set of processes. Without it the probe finds the bar of
# this user and 'pkill' signals the bar of every user on the machine, so the
# answer would describe one thing and the action would reach another.
readonly RELOAD_COMPONENTS=(
	"hyprland|Hyprland|hyprctl|hyprctl reload"
	"waybar|waybar|pkill|pkill -SIGUSR2 -x -u $EUID waybar"
	"swaync|swaync|swaync-client|swaync-client -rs"
	"ghostty|ghostty|pkill|pkill -SIGUSR2 -x -u $EUID ghostty"
	"hyprpaper|hyprpaper|hyprctl|hyprctl hyprpaper wallpaper ,@BACKGROUND@"
)

# The values a command may carry, and the function that resolves each one.
#
#   name      The text in the command, resolved wherever it appears in a word.
#   function  What answers it. It sets RELOAD_VALUE and returns 0, or sets
#             RELOAD_DETAIL and returns 1 for "there is nothing to send" or 2
#             for "the value could not be resolved at all".
#
# A function rather than a value, because a value would be frozen with this
# table and the answer is not known then. It sets a variable rather than
# printing, for the reason reload_one records: a command substitution is a
# subshell, and the reason for an answer would be lost in it.
readonly RELOAD_VALUES=(
	"@BACKGROUND@|reload_value_background"
)

# The name of a value, as reload_check_row looks for one in a command. It is
# the shape the rows above are written in.
readonly RELOAD_VALUE_PATTERN='@[A-Z][A-Z0-9_]*@'

# The greatest length of a process name the kernel keeps. 'pgrep -x' compares
# against that name, so a longer pattern can never match.
readonly RELOAD_COMM_LIMIT=15

# The program that answers whether a component is running. It is named here
# rather than written into every row, because every row asks the same question,
# and the tests replace it with a stub through the PATH.
readonly RELOAD_PROBE=pgrep

# Set by reload_one. RELOAD_RESULT is one of the five answers above, or
# 'unknown' for a name that is in no row, or 'malformed' for a row that breaks
# one of the four rules. RELOAD_DETAIL carries the reason when there is one,
# and is empty when there is not. A reason is not only a fault: 'nothing to
# send' carries one too, and reload_all reads it on the line of that component.
RELOAD_RESULT=
RELOAD_DETAIL=

# Set by the function that resolves a value, and read by reload_expand alone.
RELOAD_VALUE=

# Set by reload_all.
RELOAD_PROBLEMS=0
RELOAD_SUMMARY=

reload_say() {
	printf '%s\n' "$*"
}

# Whether the reload runs at all.
#
# Returns 0 when it does. Returns 1 when it does not, and sets RELOAD_DETAIL to
# the reason, so no caller can turn this into a silence.
reload_enabled() {
	local wanted=${XGHOST_RELOAD:-yes}

	case $wanted in
	yes) return 0 ;;
	no)
		RELOAD_DETAIL="XGHOST_RELOAD is 'no'"
		return 1
		;;
	esac
	RELOAD_DETAIL="XGHOST_RELOAD is '$wanted', and it takes 'yes' or 'no'. Nothing was reloaded."
	return 1
}

reload_warn() {
	printf '%s: %s\n' "${XGHOST_PROGRAM:-xghost}" "$*" >&2
}

# Find the row of one component.
#
#   reload_row NAME
#
# Prints the row and returns 0, or returns 1 when no row carries that name.
reload_row() {
	local name=$1
	local row

	for row in "${RELOAD_COMPONENTS[@]}"; do
		if [ "${row%%|*}" = "$name" ]; then
			printf '%s\n' "$row"
			return 0
		fi
	done
	return 1
}

# Find the row of one value.
#
#   reload_value_row NAME
#
# Prints the row and returns 0, or returns 1 when no row carries that name.
reload_value_row() {
	local name=$1
	local row

	for row in "${RELOAD_VALUES[@]}"; do
		if [ "${row%%|*}" = "$name" ]; then
			printf '%s\n' "$row"
			return 0
		fi
	done
	return 1
}

# The image of the build, which is what the wallpaper daemon is told to draw.
#
# Sets RELOAD_VALUE to the path and returns 0.
#
# Returns 1 and sets RELOAD_DETAIL when the build holds no image. That is a
# state lib/background.sh supports rather than a fault, and the file it names
# is where the reason for this particular build is written down.
#
# Returns 2 and sets RELOAD_DETAIL when the state directory has no home, which
# is the one case where this module cannot tell where the output is at all.
#
# The path is the stable path rather than the path of the build, and it is the
# path lib/theme.sh wrote into the wallpaper file, because both are composed by
# xghost_generated_dir in lib/paths.sh. 'hyprctl' resolves it before it sends
# it, so the daemon receives the build the link points at.
reload_value_background() {
	local generated image

	RELOAD_VALUE=

	if ! generated=$(xghost_generated_dir); then
		RELOAD_DETAIL="neither XDG_STATE_HOME nor HOME is set, so where the generated output is cannot be told"
		return 2
	fi

	image=$generated/$BACKGROUND_IMAGE_RELATIVE
	if [ ! -f "$image" ]; then
		RELOAD_DETAIL="this build drew no wallpaper, and $generated/$BACKGROUND_WALLPAPER_RELATIVE records why"
		return 1
	fi

	RELOAD_VALUE=$image
}

# Put the value of every @NAME@ into the words of one command.
#
#   reload_expand WORDS_ARRAY_NAME
#
# The command is already split, and each value lands inside the one word that
# carries its name. So a value that holds a space is one argument: a path under
# an XDG_STATE_HOME whose name holds a space reaches the program whole rather
# than as two arguments naming two files that are not there.
#
# Returns 0 when every word is ready to run, 1 when there is nothing to send,
# and 2 when a value could not be resolved. It returns nothing else, so the
# caller has no fourth case to read: a status of the resolver that is neither 0
# nor 1 is a fault of this file, and it becomes 2 with a reason of its own.
# RELOAD_DETAIL carries the reason for 1 and for 2.
reload_expand() {
	local -n words_ref=$1
	local row name resolver index
	local status=0 resolved=0

	for row in "${RELOAD_VALUES[@]}"; do
		name=${row%%|*}
		resolver=${row#*|}
		resolved=0

		for index in "${!words_ref[@]}"; do
			case ${words_ref[index]} in
			*"$name"*) ;;
			*) continue ;;
			esac

			# The function runs once for a command however many words carry
			# the name, and it does not run at all for a command that carries
			# none: a value is asked for only where it is needed.
			if [ "$resolved" -eq 0 ]; then
				status=0
				"$resolver" || status=$?
				case $status in
				0) ;;
				1) return 1 ;;
				*)
					# Every other status is a fault of this file rather than
					# a state of the machine. A function that is not there
					# ends 127, and without this the words would be run with
					# the name still in them: the request would name a file
					# called '@NAME@'.
					if [ -z "$RELOAD_DETAIL" ]; then
						RELOAD_DETAIL="'$resolver' could not answer '$name' and ended $status"
					fi
					return 2
					;;
				esac
				if [ -z "$RELOAD_VALUE" ]; then
					RELOAD_DETAIL="'$resolver' answered '$name' with nothing, and an argument of a command may not be empty"
					return 2
				fi
				resolved=1
			fi

			words_ref[index]=${words_ref[index]//"$name"/"$RELOAD_VALUE"}
		done
	done
}

# Check one row against the four rules above.
#
#   reload_check_row NAME PROCESS PROGRAM COMMAND
#
# Returns 1 and sets RELOAD_DETAIL when the row breaks one of them. A row that
# breaks one is a defect of this project rather than a state of the machine, so
# it is named and reported instead of being run: the failures it would cause
# are silent ones, and one of them reaches every process of the user.
reload_check_row() {
	local name=$1 process=$2 program=$3 command=$4
	local rest value

	if [ -z "$name" ] || [ -z "$process" ] || [ -z "$program" ] ||
		[ -z "$command" ]; then
		RELOAD_DETAIL="the row of '$name' has an empty field, and every field is required"
		return 1
	fi
	if [ "${#process}" -gt "$RELOAD_COMM_LIMIT" ]; then
		RELOAD_DETAIL="the process name '$process' is longer than $RELOAD_COMM_LIMIT characters, which is the most the kernel keeps, so it can never be matched"
		return 1
	fi
	if [ "${command%% *}" != "$program" ]; then
		RELOAD_DETAIL="the row of '$name' tests for '$program' and runs '${command%% *}', so it asks about one program and runs another"
		return 1
	fi

	# Every @NAME@ of the command has to be one RELOAD_VALUES answers. One that
	# nothing answers would be sent to the program as itself, and the request
	# would name a file called '@NAME@' rather than fail.
	rest=$command
	while [[ $rest =~ $RELOAD_VALUE_PATTERN ]]; do
		value=$BASH_REMATCH
		if ! reload_value_row "$value" >/dev/null; then
			RELOAD_DETAIL="the row of '$name' carries the value '$value', and this file resolves no value of that name"
			return 1
		fi
		rest=${rest#*"$value"}
	done
}

# Ask whether a process of one name belongs to this user.
#
#   reload_is_running PROCESS
#
# Returns 0 when at least one does, 1 when none does, and 2 when the question
# could not be asked. The three are told apart by the exact exit status of the
# probe, and not by a plain 'if': 'pgrep' ends with 1 when it matched nothing
# and with 2 or more when it failed, and an 'if' reads those two the same. That
# is the difference between "the bar is not running" and "this machine cannot
# tell", and reporting the second as the first is how a broken reload looks
# healthy.
reload_is_running() {
	local process=$1
	local status=0

	"$RELOAD_PROBE" -x -u "$EUID" -- "$process" >/dev/null 2>&1 || status=$?
	case $status in
	0) return 0 ;;
	1) return 1 ;;
	esac
	return 2
}

# Tell one component to read its configuration again.
#
#   reload_one NAME
#
# Sets RELOAD_RESULT and RELOAD_DETAIL. Returns 0 when the answer is one the
# caller does nothing about, and 1 when it is a problem the caller counts.
#
# It sets variables rather than printing, and the reason is a defect this
# project has already paid for once: a command substitution is a subshell, so a
# function called as 'result=$(reload_one ...)' would set RELOAD_DETAIL in a
# shell that ends on the next line, and the reason for a failure would be lost
# exactly when it was wanted.
reload_one() {
	local name=$1
	local row process program command
	local -a words=()
	local status=0 output=

	RELOAD_RESULT=
	RELOAD_DETAIL=

	# The switch is tested here rather than in reload_all alone, because this is
	# the one function that runs anything, and a backstop that sits behind the
	# door it guards is not one.
	if ! reload_enabled; then
		RELOAD_RESULT=off
		return 0
	fi

	if ! row=$(reload_row "$name"); then
		RELOAD_RESULT=unknown
		RELOAD_DETAIL="'$name' is not a component this reloads"
		return 1
	fi

	IFS='|' read -r name process program command <<<"$row"

	if ! reload_check_row "$name" "$process" "$program" "$command"; then
		RELOAD_RESULT=malformed
		return 1
	fi

	# The probe itself has to be there before anything can be asked. A machine
	# without it is reported rather than treated as a machine where nothing is
	# running, because those two look identical and only one of them is safe.
	if ! command -v "$RELOAD_PROBE" >/dev/null 2>&1; then
		RELOAD_RESULT=failed
		RELOAD_DETAIL="the '$RELOAD_PROBE' program is not installed, so whether $name is running cannot be asked. It ships in procps-ng."
		return 1
	fi

	reload_is_running "$process" || status=$?
	case $status in
	1)
		RELOAD_RESULT="not running"
		return 0
		;;
	2)
		RELOAD_RESULT=failed
		RELOAD_DETAIL="'$RELOAD_PROBE' could not say whether $process is running"
		return 1
		;;
	esac

	# The component is running, so a missing program is a change the desktop
	# will not be shown, and nothing else would report it.
	if ! command -v "$program" >/dev/null 2>&1; then
		RELOAD_RESULT="no command"
		RELOAD_DETAIL="$process is running and the '$program' program is not installed, so it keeps the configuration it started with"
		return 1
	fi

	read -r -a words <<<"$command"

	# The values the command carries are put in here, after the split and after
	# the two questions above, and in this order for a reason. "This machine
	# cannot send anything" is a fault of the installation that nothing else
	# reports; "this build holds nothing to send" is a state of one render. The
	# first is the one worth naming, so it is asked first.
	status=0
	reload_expand words || status=$?
	case $status in
	1)
		# RELOAD_DETAIL holds the reason, and reload_all prints it. This is not
		# a problem: see the header.
		RELOAD_RESULT="nothing to send"
		return 0
		;;
	2)
		RELOAD_RESULT=failed
		return 1
		;;
	esac

	# Both streams are kept, because the components do not agree on where a
	# diagnostic goes. 'hyprctl' writes its errors to standard output, so a
	# capture of standard error alone reported the status of a failed reload
	# with no cause attached, which is the one thing a reader needs. A
	# component that succeeds gains no noise from this: the success branch
	# below returns before the output is read, exactly as it did before.
	status=0
	output=$("${words[@]}" 2>&1) || status=$?
	if [ "$status" -eq 0 ]; then
		RELOAD_RESULT=reloaded
		return 0
	fi

	# The command failed. It may have failed because the process went away
	# between the probe and the signal, which is not a failure of anything, so
	# the question is asked again before the answer is written down.
	if ! reload_is_running "$process"; then
		RELOAD_RESULT="not running"
		return 0
	fi

	RELOAD_RESULT=failed
	RELOAD_DETAIL="'$command' ended $status"
	if [ -n "$output" ]; then
		RELOAD_DETAIL="$RELOAD_DETAIL: ${output%%$'\n'*}"
	fi
	return 1
}

# Tell every component to read its configuration again.
#
# Prints one line per component and sets RELOAD_PROBLEMS to the number that
# could not be reloaded. RELOAD_SUMMARY is the same thing on one line, for a
# caller that reports in a table. Returns 1 when RELOAD_PROBLEMS is not zero.
#
# The heading belongs to the caller, because the two callers frame this
# differently: an update reports it as one step of six, and 'xghost system
# reload' reports it as the whole of what it did.
reload_all() {
	local row name
	local -a parts=()

	RELOAD_PROBLEMS=0
	RELOAD_SUMMARY=

	if ! reload_enabled; then
		reload_say "   reload is off: $RELOAD_DETAIL"
		RELOAD_SUMMARY="not reloaded: $RELOAD_DETAIL"
		return 0
	fi

	for row in "${RELOAD_COMPONENTS[@]}"; do
		name=${row%%|*}

		# The OR list is what makes the components independent. See the header.
		if reload_one "$name"; then
			# An answer that is not a problem may still have something to say,
			# and 'nothing to send' is the one that does. It goes on the line
			# of that component rather than on standard error, because standard
			# error is where the problems are.
			if [ -n "$RELOAD_DETAIL" ]; then
				reload_say "   $name: $RELOAD_RESULT: $RELOAD_DETAIL"
			else
				reload_say "   $name: $RELOAD_RESULT"
			fi
		else
			RELOAD_PROBLEMS=$((RELOAD_PROBLEMS + 1))
			reload_say "   $name: $RELOAD_RESULT"
			reload_warn "$name: $RELOAD_DETAIL"
		fi
		parts+=("$name $RELOAD_RESULT")
	done

	RELOAD_SUMMARY=$(
		IFS=', '
		printf '%s\n' "${parts[*]}"
	)

	[ "$RELOAD_PROBLEMS" -eq 0 ]
}
