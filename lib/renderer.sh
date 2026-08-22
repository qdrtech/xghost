#!/usr/bin/env bash
#
# The xghost renderer.
#
# render_tree is a pure function. It reads a template directory, a theme, the
# machine facts and the knobs, and it writes one output directory. The same
# inputs always produce the same output. It writes nothing outside the output
# directory it is given, and it never moves that directory into place:
# lib/theme.sh does that.
#
# It has two substitution mechanisms, and ADR 0001 names both. A value is
# substituted into a template by name. A structural choice picks one whole
# prescribed fragment out of a directory of them. There is no third one: the
# module holds no loop and no condition that a template can reach.
#
# Both mechanisms read one table of values, so a knob and a machine fact drive
# either of them in exactly the same way. A knob is not a third mechanism, and
# adding one adds no code here.
#
# The renderer sets the mode of everything it writes, so the umask of the
# caller cannot change what lands on disk. See RENDER_DIR_MODE below.
#
# The module prints nothing. It collects every problem in RENDER_ERRORS and
# leaves the reporting to the caller. Every command that can write a diagnostic
# of its own has its standard error dropped, so the collected problem is the
# only report.
#
# One file of the output is not a template and not a fragment: the background
# image of the theme. It is a raster image, so no substitution can produce it,
# and lib/background.sh draws it from the same table of values every template
# reads. It is written here rather than by the caller because this is the
# module that builds the whole output tree, and a wallpaper that arrived after
# the tree was moved into place would be a second switch of its own.
#
# This module needs lib/palette.sh, lib/facts.sh, lib/knobs.sh and
# lib/background.sh.

# The include sentinel. A library may be sourced more than once, because two
# modules may each need it. The second source returns here, so the readonly
# declarations below run exactly once.
if [ -n "${XGHOST_RENDERER_SOURCED:-}" ]; then
	return 0
fi
XGHOST_RENDERER_SOURCED=1

# Set by render_tree.
RENDER_ERRORS=()

# Set by render_collect.
RENDER_FILES=()

# Every value a template may name, built by render_tree from the theme palette,
# from the machine facts and from the knobs. The three sources are kept apart
# until here, so a name that two of them declare is named as a problem rather
# than resolved by an order that nobody chose.
declare -A RENDER_SCALARS=()

# Every machine fact whose value is the word 'unknown', built by render_scalars.
#
# lib/facts.sh defines that word: detection could not read the source of this
# fact. It is therefore the one value in the table that is not a value, and a
# template that writes it produces a configuration file that states something
# about the machine that nobody read. A monitor line is the case this was found
# in: 'MACHINE_MONITOR_1_MODE=unknown' renders a line the compositor refuses,
# and the switch would report success.
#
# So the renderer refuses the substitution and names it, exactly as it names a
# value that is missing. Selection is not substitution and is untouched: a
# structural choice keyed on 'MACHINE_MONITOR_COUNT' still selects its 'default'
# fragment for the value 'unknown', which is the fragment that names no monitor.
declare -A RENDER_UNKNOWN_FACTS=()

# Set by render_substitute.
RENDER_CONTENT=
RENDER_MISSING=()
RENDER_UNKNOWN=()
RENDER_UNSAFE=()

# Set by render_unsafe_reason: the character of a value that a generated file
# cannot carry, named in words.
RENDER_UNSAFE_REASON=

# Set by render_tree: the relative path of the background image of this render,
# or empty when it holds none, and the reason it holds none.
#
# An empty path is not a failure. lib/background.sh records the two cases it
# covers, and the caller reports the note: a machine whose monitors nobody has
# read yet has no resolution to draw at, and this project invents neither a
# resolution nor a colour.
RENDER_BACKGROUND=
RENDER_BACKGROUND_NOTE=

# A placeholder in a template. The name is upper case, so ordinary text such as
# a CSS at-rule is never mistaken for one.
readonly RENDER_PLACEHOLDER_PATTERN='@[A-Z][A-Z0-9_]*@'

# The escape, and the one text a template could not write without it.
#
# '@@NAME@@' writes the literal text '@NAME@'. That spelling is the whole of the
# gap: every other text a file may need is already written as itself, because a
# lone '@' is ordinary text and a placeholder is the only thing the renderer
# reads. So the escape is the doubled placeholder and nothing wider. '@@' on its
# own keeps its old meaning, and so does '@@NAME@' and '@NAME@@'. The only
# string whose meaning this changes is the doubled form itself, and no file of
# this project holds one.
#
# It exists because a prescribed file may have to carry the exact spelling the
# renderer substitutes. 'config/swaync/config.json' carries
# '@DEFAULT_AUDIO_SINK@' and '@DEFAULT_AUDIO_SOURCE@', which is the name
# wireplumber gives the default audio device, and no palette, fact or knob
# declares either. Without an escape that file cannot be a template at all,
# whatever else it needs. docs/bundles/swaync.md records the case.
#
# The escape belongs to the template text and never to a value. A value that
# holds '@@NAME@@' reaches the output as '@@NAME@@', because render_substitute
# reads the template once and never reads back what it wrote.
readonly RENDER_ESCAPED_PATTERN='@@[A-Z][A-Z0-9_]*@@'

# What one pass of render_substitute reads: an escape or a placeholder. A
# regular expression matches leftmost and longest, so at a position where both
# could match the doubled form is the one that is taken, whichever side of the
# alternation it is written on.
readonly RENDER_TOKEN_PATTERN="$RENDER_ESCAPED_PATTERN|$RENDER_PLACEHOLDER_PATTERN"

# A structural choice, which is the second substitution mechanism of ADR 0001.
#
# A directory named '<file>.choice.<NAME>' holds one prescribed fragment per
# value of NAME, and the renderer writes exactly one of them to '<file>' beside
# that directory. The fragment whose file name is the value of NAME wins, and
# 'default' is the fragment for every value no file names.
#
# This is a selection, never a loop and never a condition inside a template. A
# fragment is ordinary configuration text, so the project keeps out of the
# business of building a template language. docs/theming.md records the rule and
# docs/bundles/hyprland.md records the case it was built for: a monitor layout
# holds one line per monitor, and the number of monitors is a fact of the
# machine rather than something a template can know.
readonly RENDER_CHOICE_MARKER='.choice.'
readonly RENDER_CHOICE_PATTERN='^(.+)\.choice\.([A-Z][A-Z0-9_]*)$'
readonly RENDER_CHOICE_DEFAULT=default

# Set by render_choice_plan. RENDER_CHOICE_DIRS holds every directory that is
# named like a choice, including one the plan refused, because it is what tells
# render_tree which files are fragments rather than templates of their own. The
# two arrays hold one entry per choice that writes, at the same index: the
# template file that was chosen, and the path it takes in the output.
declare -A RENDER_CHOICE_DIRS=()
RENDER_CHOICE_SOURCES=()
RENDER_CHOICE_TARGETS=()

# Set by render_choice_member.
RENDER_CHOSEN=

# The modes of the generated output.
#
# The renderer sets each one itself rather than leaving it to the umask of the
# caller, so the same inputs produce the same modes on every machine. The
# output is read by desktop components and holds no secret, so it is readable
# by everybody and writable by its owner alone.
readonly RENDER_DIR_MODE=0755
readonly RENDER_FILE_MODE=0644
readonly RENDER_EXECUTABLE_MODE=0755

# Render one template directory into one output directory.
#
#   render_tree TEMPLATE_DIR THEME_DIR FACTS_FILE KNOBS_SCHEMA KNOBS_FILE OUT_DIR
#
# The renderer takes three inputs by design: the theme, the machine facts, and
# the knobs. The knobs are two paths, because the project owns the schema and
# the user owns the file that answers it.
#
# FACTS_FILE is the machine facts file of lib/facts.sh. Every value it declares
# is a value a template may name, beside the values of the palette. An empty
# path means "absent", which is what a machine that has not run
# 'xghost machine detect' passes. A template that names a machine fact then
# fails the render by name, rather than rendering a monitor layout the renderer
# guessed at.
#
# KNOBS_SCHEMA and KNOBS_FILE are the two files of lib/knobs.sh. Every knob the
# schema declares is a value a template may name, and it is the value the knobs
# file gives it or the default of the schema. An empty KNOBS_FILE means
# "absent", which is what a machine that has never changed a preference passes,
# and every knob then takes its default. An empty KNOBS_SCHEMA means "no knob is
# declared at all".
#
# A knob is absent from the output in no case: the schema gives every knob a
# value, so a template that names one always renders. That is the difference
# between a knob and a machine fact, and it is why an absent knobs file is not a
# failure of any kind.
#
# THEME_DIR holds 'palette.conf' and may hold a 'files/' directory. Every file
# under 'files/' is a hand-written file the theme ships. It is copied into the
# output unchanged, and the template of the same relative path is not rendered.
#
# OUT_DIR must not exist. The renderer creates it.
#
# Returns 1 when the render has at least one problem, and every problem lands in
# RENDER_ERRORS.
render_tree() {
	local template_dir=$1 theme_dir=$2 facts_file=$3
	local knobs_schema=$4 knobs_file=$5 out_dir=$6

	RENDER_ERRORS=()
	RENDER_BACKGROUND=
	RENDER_BACKGROUND_NOTE=

	if [ ! -d "$template_dir" ]; then
		RENDER_ERRORS+=("the template directory does not exist: $template_dir")
	fi
	if [ ! -d "$theme_dir" ]; then
		RENDER_ERRORS+=("the theme directory does not exist: $theme_dir")
	fi
	if [ -e "$out_dir" ] || [ -L "$out_dir" ]; then
		RENDER_ERRORS+=("the output directory already exists: $out_dir")
	fi
	if [ "${#RENDER_ERRORS[@]}" -gt 0 ]; then
		return 1
	fi

	local problem
	if ! palette_load "$theme_dir/palette.conf"; then
		for problem in "${PALETTE_ERRORS[@]}"; do
			RENDER_ERRORS+=("palette.conf: $problem")
		done
		return 1
	fi

	if ! render_scalars "$facts_file" "$knobs_schema" "$knobs_file"; then
		return 1
	fi

	if ! mkdir -p "$out_dir" 2>/dev/null; then
		RENDER_ERRORS+=("cannot create the output directory: $out_dir")
		return 1
	fi

	# The output directory with every symbolic link of its own path resolved.
	# Every file the renderer writes is checked against it, so a link inside an
	# input directory can never carry a write outside the output.
	local out_root
	out_root=$(readlink -f "$out_dir" 2>/dev/null || true)
	if [ -z "$out_root" ]; then
		RENDER_ERRORS+=("cannot resolve the output directory: $out_dir")
		return 1
	fi

	local overrides_dir=$theme_dir/files
	local path relative destination ships
	local -a templates=() overrides=()

	if render_collect "$template_dir" 'the template directory'; then
		templates=("${RENDER_FILES[@]}")
	fi
	if [ -d "$overrides_dir" ] && render_collect "$overrides_dir" 'the files directory of the theme'; then
		overrides=("${RENDER_FILES[@]}")
	fi

	# The structural choices, resolved before anything is written, so a choice
	# that names no fragment is reported beside every other problem of the run.
	render_choice_plan "$template_dir" templates

	# The templates. A template whose relative path the theme also ships by hand
	# is passed over, so the hand-written file is never overwritten. A link that
	# points at nothing is still a file the theme means to ship, so it counts
	# here and render_collect has already named it as a problem.
	#
	# What the theme ships at that path is one question with three answers, and
	# render_theme_ships is where all three sites ask it. A file the theme
	# ships wins. A directory is not a file the theme ships, so the template is
	# what belongs there. Anything else is refused by name.
	#
	# A file inside a choice directory is a fragment rather than a template of
	# its own, so it is written by the loop below this one, and only when it is
	# the fragment the choice selected.
	for path in "${templates[@]}"; do
		relative=${path#"$template_dir/"}
		if render_in_choice "$relative"; then
			continue
		fi
		ships=0
		render_theme_ships "$overrides_dir/$relative" "$relative" || ships=$?
		# 0: the theme ships the file. 2: it ships something that is not one,
		# and render_theme_ships has named that. Neither renders the template.
		if [ "$ships" -ne 1 ]; then
			continue
		fi
		destination=$out_dir/$relative
		if ! render_prepare_parent "$out_root" "$destination" "$relative"; then
			continue
		fi
		render_file "$path" "$destination" "$relative" || true
	done

	# The selected fragment of every structural choice. It is rendered like any
	# other template, and it lands at the path the choice directory names, so a
	# hand-written file of the theme still wins over it. The same one question,
	# asked the same way, for the reason the loop above records.
	local index
	for index in ${RENDER_CHOICE_SOURCES[@]+"${!RENDER_CHOICE_SOURCES[@]}"}; do
		path=${RENDER_CHOICE_SOURCES[index]}
		relative=${RENDER_CHOICE_TARGETS[index]}
		ships=0
		render_theme_ships "$overrides_dir/$relative" "$relative" || ships=$?
		if [ "$ships" -ne 1 ]; then
			continue
		fi
		destination=$out_dir/$relative
		if ! render_prepare_parent "$out_root" "$destination" "$relative"; then
			continue
		fi
		render_file "$path" "$destination" "$relative" || true
	done

	# The hand-written files of the theme.
	for path in "${overrides[@]}"; do
		relative=${path#"$overrides_dir/"}
		destination=$out_dir/$relative
		if ! render_prepare_parent "$out_root" "$destination" "$relative"; then
			continue
		fi
		# 'cp' reads through a symbolic link, so the output holds a real file
		# even when the theme ships a link into a dotfiles repository.
		if ! cp -- "$path" "$destination" 2>/dev/null; then
			RENDER_ERRORS+=("$relative: cannot copy the hand-written file the theme ships")
			continue
		fi
		render_set_mode "$path" "$destination" "$relative" || true
	done

	# The background of the theme. It is drawn last, so a theme that ships the
	# image by hand is left alone: that file has already been copied above, and
	# the one rule of precedence in docs/theming.md is that a hand-written file
	# of the theme wins over anything the project generates at the same path.
	render_background "$out_dir" "$overrides_dir" || true

	# The mode of every directory of the output, in one pass, so a directory
	# 'mkdir -p' created on the way to a file is deliberate too.
	if ! find "$out_dir" -type d -exec chmod "$RENDER_DIR_MODE" {} + 2>/dev/null; then
		RENDER_ERRORS+=("cannot set the mode of the directories of the generated output")
	fi

	[ "${#RENDER_ERRORS[@]}" -eq 0 ]
}

# Build the table of every value a template may name.
#
#   render_scalars FACTS_FILE KNOBS_SCHEMA KNOBS_FILE
#
# The palette is loaded already. This adds the machine facts, when the caller
# gave a path for them, then the knobs, and fills RENDER_SCALARS with all three.
#
# A name two sources declare is a problem rather than a winner, and the report
# names both sources. The palette key of a theme holds upper case letters, the
# key of a machine fact starts with 'MACHINE_' and a knob starts with 'KNOB_',
# so a collision is a mistake in one of the files. Quietly preferring either
# side would make the output depend on a rule nobody wrote down.
#
# The three prefixes make two of the three collisions impossible: a machine fact
# and a knob can never carry the same name, whatever either file holds. The one
# collision that can happen is a theme palette that declares a name in the
# namespace of another file, and it is refused whichever of the two it hits.
#
# A machine fact whose value is 'unknown' is recorded in RENDER_UNKNOWN_FACTS as
# well, so render_substitute can refuse to write it. See that array above. No
# knob is ever recorded there: a knob holds a value the schema names, so there
# is no such thing as a knob nobody could read.
#
# Returns 1 when the machine facts or the knobs have at least one problem, and
# every problem lands in RENDER_ERRORS.
render_scalars() {
	local facts_file=$1 knobs_schema=$2 knobs_file=$3
	local name problem
	local -A source=()

	RENDER_SCALARS=()
	RENDER_UNKNOWN_FACTS=()
	for name in "${!PALETTE_SCALARS[@]}"; do
		RENDER_SCALARS[$name]=${PALETTE_SCALARS[$name]}
		source[$name]='the theme palette'
	done

	if [ -n "$facts_file" ]; then
		if ! facts_load "$facts_file"; then
			for problem in "${FACTS_ERRORS[@]}"; do
				RENDER_ERRORS+=("machine facts: $problem")
			done
			return 1
		fi

		for name in "${!FACTS_SCALARS[@]}"; do
			if [ -n "${RENDER_SCALARS[$name]+set}" ]; then
				RENDER_ERRORS+=("machine facts: '$name' is declared by ${source[$name]} as well")
				continue
			fi
			RENDER_SCALARS[$name]=${FACTS_SCALARS[$name]}
			source[$name]='the machine facts'
			if [ "${FACTS_SCALARS[$name]}" = "$FACTS_UNKNOWN" ]; then
				RENDER_UNKNOWN_FACTS[$name]=1
			fi
		done
	fi

	if [ -n "$knobs_schema" ] || [ -n "$knobs_file" ]; then
		if ! knobs_load "$knobs_schema" "$knobs_file"; then
			for problem in "${KNOBS_ERRORS[@]}"; do
				RENDER_ERRORS+=("knobs: $problem")
			done
			return 1
		fi

		for name in "${!KNOBS_SCALARS[@]}"; do
			if [ -n "${RENDER_SCALARS[$name]+set}" ]; then
				RENDER_ERRORS+=("knobs: '$name' is declared by ${source[$name]} as well")
				continue
			fi
			RENDER_SCALARS[$name]=${KNOBS_SCALARS[$name]}
			source[$name]='the knobs'
		done
	fi

	[ "${#RENDER_ERRORS[@]}" -eq 0 ]
}

# Draw the background image of one render.
#
#   render_background OUT_DIR OVERRIDES_DIR
#
# The image is not a template. It is a raster file, and lib/background.sh draws
# it from RENDER_SCALARS, which is the same table every template reads.
#
# Sets RENDER_BACKGROUND to the relative path of the image the output holds, and
# RENDER_BACKGROUND_NOTE to the reason it holds none. A note is not a problem
# and the render succeeds with it; lib/background.sh records the difference.
#
# Returns 1 when the image should have been drawn and could not be, and that
# problem lands in RENDER_ERRORS like any other.
render_background() {
	local out_dir=$1 overrides_dir=$2
	local relative=$BACKGROUND_IMAGE_RELATIVE
	local status=0

	# A theme that ships the image by hand has already had it copied into the
	# output, so the output holds a background and nothing is drawn over it.
	#
	# The same one question the two loops of render_tree ask, asked the same
	# way. The copy that ran before this reads the files of the theme, so a
	# directory at that path put nothing into the output, and treating it as an
	# image already shipped would leave the wallpaper file naming a path that
	# holds none. A link that points at nothing is a problem render_collect has
	# already reported by name.
	local ships=0
	render_theme_ships "$overrides_dir/$relative" "$relative" || ships=$?
	case $ships in
	0)
		RENDER_BACKGROUND=$relative
		return 0
		;;
	2)
		# Named already. Nothing is drawn over what the theme put there, and
		# the render is failing on it.
		return 1
		;;
	esac

	background_render "$out_dir" RENDER_SCALARS || status=$?

	case $status in
	0)
		RENDER_BACKGROUND=$relative
		;;
	1)
		RENDER_BACKGROUND_NOTE=$BACKGROUND_NOTE
		;;
	*)
		RENDER_ERRORS+=("$relative: $BACKGROUND_PROBLEM")
		return 1
		;;
	esac
}

# Collect every file under one directory, symbolic links followed.
#
#   render_collect DIR LABEL
#
# Sets RENDER_FILES to the paths, sorted. Links are followed, because a theme
# whose upstream is a stow-managed dotfiles repository ships a link where
# another theme ships a file, and the two must mean the same thing.
#
# A link that points at nothing is named as a problem rather than passed over.
# A theme that ships a link means the file to be there, so a silent success
# with the file missing is the wrong answer. The walk carries on after such a
# link, so one render reports every one of them.
#
# Returns 1 when the walk itself fails, such as a loop of symbolic links, and
# names that as a problem too.
render_collect() {
	local dir=$1 label=$2
	local listing broken path

	RENDER_FILES=()

	if ! listing=$(find -L "$dir" -type f 2>/dev/null); then
		RENDER_ERRORS+=("cannot walk $label; it may hold a loop of symbolic links: $dir")
		return 1
	fi
	# With links followed, a link that still reports its own type is a link
	# that points at nothing.
	if ! broken=$(find -L "$dir" -type l 2>/dev/null); then
		RENDER_ERRORS+=("cannot walk $label; it may hold a loop of symbolic links: $dir")
		return 1
	fi

	if [ -n "$broken" ]; then
		while IFS= read -r path; do
			RENDER_ERRORS+=("${path#"$dir/"}: the symbolic link points at nothing")
		done < <(printf '%s\n' "$broken" | LC_ALL=C sort)
	fi

	if [ -n "$listing" ]; then
		while IFS= read -r path; do
			RENDER_FILES+=("$path")
		done < <(printf '%s\n' "$listing" | LC_ALL=C sort)
	fi
}

# Resolve every structural choice of one template directory.
#
#   render_choice_plan TEMPLATE_DIR FILES_ARRAY_NAME
#
# A directory named '<file>.choice.<NAME>' is a choice. It holds one fragment
# per value of NAME, and exactly one of them reaches the output, at '<file>'
# beside the directory. The fragment whose file name is the value of NAME is
# the one that is chosen, and 'default' is the fragment for every other value.
#
# Fills RENDER_CHOICE_DIRS with the selector of each choice directory, and
# RENDER_CHOICE_SOURCES and RENDER_CHOICE_TARGETS with the fragment that was
# chosen and the path it takes in the output.
#
# The value of NAME is never used to build a path. The chosen fragment is
# looked up among the files the walk already found, so a value that holds a
# path separator can name nothing outside the choice directory.
#
# Exactly one file reaches each path of the output, and this is where that is
# proved. 'targets' holds every path already spoken for: first every plain
# template, then each choice as it is resolved. A choice that lands on a path
# either of them already writes is a problem rather than a silent overwrite,
# because the two writers are both templates of the project and no rule says
# which one should win.
#
# Returns 1 when at least one choice has a problem, and every problem lands in
# RENDER_ERRORS.
render_choice_plan() {
	local template_dir=$1
	local -n files_ref=$2
	local before=${#RENDER_ERRORS[@]}
	local listing path relative base selector parent target ancestor
	local member chosen
	local -a dirs=() members=()
	local -A targets=() refused=() reported=()

	RENDER_CHOICE_DIRS=()
	RENDER_CHOICE_SOURCES=()
	RENDER_CHOICE_TARGETS=()

	if ! listing=$(find -L "$template_dir" -mindepth 1 -type d 2>/dev/null); then
		RENDER_ERRORS+=("cannot walk the template directory; it may hold a loop of symbolic links: $template_dir")
		return 1
	fi
	if [ -n "$listing" ]; then
		while IFS= read -r path; do
			dirs+=("$path")
		done < <(printf '%s\n' "$listing" | LC_ALL=C sort)
	fi

	# The choice directories, in the order a reader of the tree meets them.
	for path in ${dirs[@]+"${dirs[@]}"}; do
		relative=${path#"$template_dir/"}
		base=${relative##*/}
		case $base in
		*"$RENDER_CHOICE_MARKER"*) ;;
		*) continue ;;
		esac
		if [[ ! $base =~ $RENDER_CHOICE_PATTERN ]]; then
			RENDER_ERRORS+=("$relative: a structural choice is named '<file>.choice.<NAME>', and NAME holds upper case letters, digits and underscores after a letter")
			continue
		fi
		RENDER_CHOICE_DIRS[$relative]=${BASH_REMATCH[2]}
	done

	if [ "${#RENDER_CHOICE_DIRS[@]}" -eq 0 ]; then
		[ "${#RENDER_ERRORS[@]}" -eq "$before" ]
		return
	fi

	# The choices in one fixed order, so one render reports its problems in the
	# same order every time. The names are read one line at a time, because a
	# directory name may hold a space.
	local -a ordered=()
	while IFS= read -r relative; do
		ordered+=("$relative")
	done < <(printf '%s\n' "${!RENDER_CHOICE_DIRS[@]}" | LC_ALL=C sort)

	# A choice inside a choice, and a directory inside a choice, are both
	# refused. One choice holds fragments and nothing else, so the rule stays
	# one sentence long and a reader of the tree never has to work out which
	# choice a file belongs to.
	#
	# A refused choice is recorded here and stays in RENDER_CHOICE_DIRS, because
	# that array is what tells render_tree which files are fragments. Dropping it
	# would turn the fragments of the refused choice into plain templates, and
	# the render that is already failing would report them at their literal
	# paths as well, which is noise in the report a user is reading.
	#
	# The ancestors are walked in the sorted order, so the choice named is the
	# outermost one that is still a choice, whichever order the array happens to
	# hold its keys in.
	for relative in "${ordered[@]}"; do
		for ancestor in "${ordered[@]}"; do
			[ -z "${refused[$ancestor]+set}" ] || continue
			if [ "$ancestor" != "$relative" ] && [ "${relative#"$ancestor"/}" != "$relative" ]; then
				RENDER_ERRORS+=("$relative: a structural choice cannot hold another one, and this one is inside '$ancestor'")
				refused[$relative]=1
				break
			fi
		done
	done

	# Every plain template holds its own path, before any choice is resolved. A
	# file inside a choice directory is a fragment rather than a template of its
	# own, and that is true of a refused choice too.
	for path in ${files_ref[@]+"${files_ref[@]}"}; do
		relative=${path#"$template_dir/"}
		if render_in_choice "$relative"; then
			continue
		fi
		targets[$relative]=$relative
	done

	for relative in "${ordered[@]}"; do
		# A choice the check above refused writes nothing.
		[ -z "${refused[$relative]+set}" ] || continue
		selector=${RENDER_CHOICE_DIRS[$relative]}
		base=${relative##*/}
		[[ $base =~ $RENDER_CHOICE_PATTERN ]] || continue
		base=${BASH_REMATCH[1]}
		parent=${relative%/*}
		if [ "$parent" = "$relative" ]; then
			target=$base
		else
			target=$parent/$base
		fi

		# Every fragment of this choice, which is every collected file whose
		# directory is this one. A file deeper inside is a directory the choice
		# must not hold. Such a directory is named once, however many files it
		# holds: it is one mistake for the reader of the report.
		members=()
		reported=()
		for path in ${files_ref[@]+"${files_ref[@]}"}; do
			member=${path#"$template_dir/"}
			[ "${member#"$relative"/}" != "$member" ] || continue
			member=${member#"$relative"/}
			if [ "${member%%/*}" != "$member" ]; then
				member=${member%%/*}
				if [ -z "${reported[$member]+set}" ]; then
					reported[$member]=1
					RENDER_ERRORS+=("$relative: a structural choice holds fragments and no directory, and it holds the directory '$member'")
				fi
				continue
			fi
			members+=("$member")
		done

		if [ "${#members[@]}" -eq 0 ]; then
			RENDER_ERRORS+=("$relative: the structural choice holds no fragment")
			continue
		fi
		if [ -z "${RENDER_SCALARS[$selector]+set}" ]; then
			RENDER_ERRORS+=("$relative: no value for '$selector' in the theme palette, the machine facts or the knobs, and the structural choice is made by that value")
			continue
		fi

		render_choice_member members "${RENDER_SCALARS[$selector]}"
		chosen=$RENDER_CHOSEN
		if [ -z "$chosen" ]; then
			RENDER_ERRORS+=("$relative: '$selector' is '${RENDER_SCALARS[$selector]}', and the structural choice has no fragment of that name and no '$RENDER_CHOICE_DEFAULT'. It holds: ${members[*]}")
			continue
		fi
		if [ -n "${targets[$target]+set}" ]; then
			RENDER_ERRORS+=("$relative: it writes '$target', and '${targets[$target]}' writes that path as well")
			continue
		fi

		targets[$target]=$relative
		RENDER_CHOICE_SOURCES+=("$template_dir/$relative/$chosen")
		RENDER_CHOICE_TARGETS+=("$target")
	done

	[ "${#RENDER_ERRORS[@]}" -eq "$before" ]
}

# Set RENDER_CHOSEN to the fragment one choice selects.
#
#   render_choice_member MEMBERS_ARRAY_NAME VALUE
#
# The fragment whose file name is the value wins, and 'default' is the fragment
# for every value no fragment names. RENDER_CHOSEN is empty when the choice has
# neither. The names are compared one by one rather than searched inside one
# string, so a fragment whose name holds a space is still matched exactly.
render_choice_member() {
	local -n members_ref=$1
	local value=$2
	local name found_default=0

	RENDER_CHOSEN=

	for name in ${members_ref[@]+"${members_ref[@]}"}; do
		if [ "$name" = "$value" ]; then
			RENDER_CHOSEN=$name
			return 0
		fi
		if [ "$name" = "$RENDER_CHOICE_DEFAULT" ]; then
			found_default=1
		fi
	done

	if [ "$found_default" -eq 1 ]; then
		RENDER_CHOSEN=$RENDER_CHOICE_DEFAULT
	fi
}

# Return 0 when one relative template path is a fragment of a structural
# choice, which is a file the choice writes rather than a template of its own.
# A choice the plan refused still holds fragments, so its files are still not
# templates of their own.
render_in_choice() {
	local relative=$1
	local parent=${relative%/*}

	[ "$parent" != "$relative" ] || return 1
	[ -n "${RENDER_CHOICE_DIRS[$parent]+set}" ]
}

# Say what the theme ships at one path of the output.
#
#   render_theme_ships PATH RELATIVE
#
# PATH is the path under the 'files' directory of the theme. RELATIVE is the
# path the file takes in the output, and it is what a problem is named by.
#
# Three sites ask this one question, and each of them passes over what it would
# otherwise have written when the answer is yes: the template loop, the loop
# that writes the chosen fragment of each structural choice, and
# render_background. They asked it in three copies of one predicate once, and
# the copies drifted twice. Issue #36 corrected the copy on the image path and
# issue #37 the other two, a slice apart, and each correction had to be made
# again by hand at every site. It is one function now, so the next correction
# reaches all three or none.
#
# Returns:
#   0  the theme ships a file here, so the project writes nothing at this path.
#   1  the theme ships nothing here, so the project writes its own file.
#   2  the theme ships something here that is not a file. It is refused by name
#      and the problem is in RENDER_ERRORS.
#
# A link that points at nothing answers 0. A theme that ships a link means the
# file to be there, render_collect has already named the link as a problem, and
# the render is failing on it already.
#
# A link that points at a directory is what this refuses, and it is what '-f'
# does not catch. '-f' is false for such a link and '-L' is true, so the old
# predicate read it as a file the theme ships and passed the template over.
# 'find -L' then named neither the link nor any file at that path, so the copy
# loop wrote nothing there either: the render reported success with the file
# missing from the output. The contents of the directory ARE walked, so a link
# to a directory that holds files is worse still, and leaves a DIRECTORY at the
# path of a configuration file for the program that reads it to fail on.
#
# Neither answer is silent, which is what issue #42 asked for, and the answer is
# to refuse. Every other malformed input of this module refuses: a link that
# points at nothing, a choice inside a choice, a value a generated file cannot
# carry. Rendering the template instead would be this project deciding that
# something the theme author put there on purpose means nothing, and it would
# need a second rule elsewhere to stop the contents of that directory reaching
# the output. The switch is atomic, so the refusal costs the user the previous
# theme whole rather than a desktop that does not render.
#
# A directory that is not a link answers 1, which is what issue #37 decided and
# this does not reopen: nothing of such a directory reaches the output, so the
# template is what belongs at that path.
render_theme_ships() {
	local path=$1 relative=$2
	local points_at

	if [ -f "$path" ]; then
		return 0
	fi
	if [ ! -L "$path" ]; then
		return 1
	fi
	if [ ! -e "$path" ]; then
		return 0
	fi

	# The link resolves to something, and it is not a file. Name what it is,
	# because a directory is the case a theme author reaches by accident and a
	# reader who is told 'not a file' has to go and look.
	points_at='something that is not a file'
	if [ -d "$path" ]; then
		points_at='a directory'
	fi
	RENDER_ERRORS+=("$relative: the theme ships a symbolic link here and it points at $points_at. A file a theme ships by hand is a file, or a link to one, because the output holds a copy of it. Point it at a file, or take it out of the 'files' directory of the theme.")
	return 2
}

# Create the directory that holds one output file, and prove it is inside the
# output tree.
#
#   render_prepare_parent OUT_ROOT DESTINATION RELATIVE
#
# The renderer follows symbolic links in its inputs, so the check below is what
# keeps a link from carrying a write outside the directory the renderer was
# given. It resolves the directory that would be written into and compares it
# with the resolved output root.
render_prepare_parent() {
	local out_root=$1 destination=$2 relative=$3
	local parent=${destination%/*} resolved

	if ! mkdir -p "$parent" 2>/dev/null; then
		RENDER_ERRORS+=("$relative: cannot create the directory that holds it")
		return 1
	fi

	resolved=$(readlink -f "$parent" 2>/dev/null || true)
	if [ -z "$resolved" ] ||
		{ [ "$resolved" != "$out_root" ] && [ "${resolved#"$out_root"/}" = "$resolved" ]; }; then
		RENDER_ERRORS+=("$relative: it would land outside the generated output, at $parent")
		return 1
	fi
}

# Set the mode of one output file from the mode of the file it came from.
#
#   render_set_mode SOURCE DESTINATION RELATIVE
#
# An executable source produces an executable file. Every other file is a
# plain one. The mode is written out in full, because 'chmod +x' is masked by
# the umask and this module does not read the umask.
render_set_mode() {
	local source=$1 destination=$2 relative=$3
	local mode=$RENDER_FILE_MODE

	if [ -x "$source" ]; then
		mode=$RENDER_EXECUTABLE_MODE
	fi
	if ! chmod "$mode" "$destination" 2>/dev/null; then
		RENDER_ERRORS+=("$relative: cannot set the mode of the rendered file")
		return 1
	fi
}

# Name the character of one value that a generated file cannot carry.
#
#   render_unsafe_reason VALUE
#
# The renderer writes a value into a file another program reads as code, and it
# cannot know where in that file the value lands. 'templates/nvim/colors.lua'
# puts one inside a Lua string literal, 'templates/shell/colors.sh' inside a
# shell literal, 'templates/waybar/knobs.css' inside a CSS one, and
# 'templates/hypr/knobs.conf' inside no literal at all. One substitution pass
# serves all four, so the renderer holds no table of output languages and reads
# no syntax around a placeholder. It would have to parse every language it
# writes to escape correctly, and a template it could not parse would have to
# fail instead.
#
# So the rule is the value rather than the file: a value has to be inert
# wherever it lands. These six characters are the ones that are not, and each
# one is refused for a reason a generated file of this project already carries:
#
#   "  closes a literal in Lua, in JSON, in TOML, in CSS and in a shell.
#   '  closes one in a shell, in Lua and in CSS.
#   `  runs a command in a shell.
#   \  escapes the character after it, the closing quotation mark included.
#   $  expands a variable or runs a command in a shell, and names a variable in
#      a Hyprland file.
#   a control character ends the line, so the rest of the value becomes a
#   directive of its own.
#
# The rule is the renderer's and it reaches every template, so a bundle adds no
# check of its own and a new template inherits it. docs/theming.md states it for
# the theme author.
#
# Sets RENDER_UNSAFE_REASON to the character in words. Returns 0 when the value
# holds one, which is the failing case, and 1 when the value is safe.
render_unsafe_reason() {
	local value=$1

	RENDER_UNSAFE_REASON=

	case $value in
	*'"'*) RENDER_UNSAFE_REASON='a quotation mark' ;;
	*"'"*) RENDER_UNSAFE_REASON='an apostrophe' ;;
	*'`'*) RENDER_UNSAFE_REASON='a backtick' ;;
	*'\'*) RENDER_UNSAFE_REASON='a backslash' ;;
	*'$'*) RENDER_UNSAFE_REASON='a dollar sign' ;;
	esac
	if [ -z "$RENDER_UNSAFE_REASON" ] && [[ $value == *[[:cntrl:]]* ]]; then
		RENDER_UNSAFE_REASON='a control character'
	fi

	[ -n "$RENDER_UNSAFE_REASON" ]
}

# Substitute every known value into one string, in a single pass.
#
#   render_substitute TEXT
#
# The values are RENDER_SCALARS, which render_scalars built from the theme
# palette, the machine facts and the knobs.
#
# Sets RENDER_CONTENT to the result, and RENDER_MISSING to the name of every
# placeholder that has no value. A name is listed once, in the order it first
# appears.
#
# RENDER_UNKNOWN holds the name of every placeholder whose machine fact is
# 'unknown', which is a fact detection could not read rather than a value. It is
# refused for the reason RENDER_UNKNOWN_FACTS records, and it is listed the same
# way: once, in the order it first appears.
#
# RENDER_UNSAFE holds the name of every placeholder whose value holds a
# character a generated file cannot carry. render_unsafe_reason names those
# characters and records why. The value is never written and never altered: the
# placeholder stays in the string, the name is listed once in the order it first
# appears, and the whole render fails. A value the renderer changed to make it
# fit would be a value the theme author did not write, and a file another
# program reads as code is not the place to guess.
#
# The pass reads the text once and never reads back what it wrote, so a value
# is copied through as the text it is. Two consequences follow, and both are
# the documented promise that a value is text:
#
#   - A value that holds '&' reaches the output unchanged. The
#     '${var//pattern/replacement}' operator would read it, because since bash
#     5.2 it treats '&' in the replacement as the matched text.
#   - A value that holds a placeholder reaches the output as that placeholder.
#     It is never substituted again, so the result does not depend on the order
#     an associative array happens to walk its keys.
#
# The pass reads one more token than it once did. '@@NAME@@' is the escape, and
# it writes the literal text '@NAME@'. See RENDER_ESCAPED_PATTERN above for what
# it is for and for how narrow it is. It reads no value, so an escaped name that
# no source declares reaches none of the three arrays and fails nothing.
render_substitute() {
	local rest=$1
	local out= match prefix name
	local -A seen=() seen_unknown=() seen_unsafe=()

	RENDER_CONTENT=
	RENDER_MISSING=()
	RENDER_UNKNOWN=()
	RENDER_UNSAFE=()

	while [[ $rest =~ $RENDER_TOKEN_PATTERN ]]; do
		match=${BASH_REMATCH[0]}
		# The regular expression matches the leftmost token, so the text before
		# the first occurrence of that exact string is the text before the
		# match. That holds for either token: were the matched text present
		# earlier in the string, the expression would have matched it there.
		prefix=${rest%%"$match"*}
		rest=${rest#"$prefix$match"}

		# The escape. The doubled form writes the single one, and this is the
		# one token that reads no value: the name inside it names nothing, so a
		# name no source declares is not a problem here. What is written goes
		# straight to 'out', which the pass never reads back, so the result is
		# never substituted again.
		if [ "${match:0:2}" = '@@' ]; then
			out=$out$prefix${match:1:${#match}-2}
			continue
		fi

		name=${match:1:${#match}-2}

		if [ -n "${RENDER_UNKNOWN_FACTS[$name]+set}" ]; then
			out=$out$prefix$match
			if [ -z "${seen_unknown[$name]+set}" ]; then
				seen_unknown[$name]=1
				RENDER_UNKNOWN+=("$name")
			fi
			continue
		fi
		if [ -n "${RENDER_SCALARS[$name]+set}" ]; then
			if render_unsafe_reason "${RENDER_SCALARS[$name]}"; then
				out=$out$prefix$match
				if [ -z "${seen_unsafe[$name]+set}" ]; then
					seen_unsafe[$name]=1
					RENDER_UNSAFE+=("$name")
				fi
				continue
			fi
			out=$out$prefix${RENDER_SCALARS[$name]}
			continue
		fi

		out=$out$prefix$match
		if [ -z "${seen[$name]+set}" ]; then
			seen[$name]=1
			RENDER_MISSING+=("$name")
		fi
	done

	RENDER_CONTENT=$out$rest

	[ "${#RENDER_MISSING[@]}" -eq 0 ] &&
		[ "${#RENDER_UNKNOWN[@]}" -eq 0 ] &&
		[ "${#RENDER_UNSAFE[@]}" -eq 0 ]
}

# Substitute every known value into one template file and write the result.
#
# Every '@NAME@' is replaced by the value of NAME, and '@@NAME@@' writes the
# literal text '@NAME@'. A placeholder that has no value is a problem: the
# renderer reports it and writes no file, rather than leaving the name in the
# output for a user to find later. A placeholder whose
# machine fact is 'unknown' is the same problem, because that word is what
# lib/facts.sh writes for a fact nobody could read. A placeholder whose value
# holds a character a generated file cannot carry is the third, and
# render_unsafe_reason names those characters.
#
# A template is a text file. One that holds a NUL byte is refused by name,
# because reading it into a string would drop that byte and write a file that
# quietly differs from its template.
#
# The result carries exactly one newline at its end. An executable template
# produces an executable file.
render_file() {
	local source=$1 destination=$2 relative=$3
	local content= fd name

	# The file is opened by descriptor, so a refused open is told apart from an
	# empty file, and the diagnostic of the shell is dropped.
	if ! { exec {fd}<"$source"; } 2>/dev/null; then
		RENDER_ERRORS+=("$relative: cannot read the template")
		return 1
	fi

	# 'read' stops at the delimiter. With NUL as the delimiter it returns zero
	# only when the file holds one, and otherwise reads the file to its end.
	if IFS= read -r -d '' content <&"$fd"; then
		{ exec {fd}<&-; } 2>/dev/null
		RENDER_ERRORS+=("$relative: the template holds a NUL byte, and a template is a text file")
		return 1
	fi
	{ exec {fd}<&-; } 2>/dev/null

	# Drop the newlines at the end, so the write below adds exactly one.
	while [ "${content: -1}" = $'\n' ]; do
		content=${content%$'\n'}
	done

	if ! render_substitute "$content"; then
		for name in ${RENDER_MISSING[@]+"${RENDER_MISSING[@]}"}; do
			RENDER_ERRORS+=("$relative: no value for '$name' in the theme palette, the machine facts or the knobs")
		done
		for name in ${RENDER_UNKNOWN[@]+"${RENDER_UNKNOWN[@]}"}; do
			RENDER_ERRORS+=("$relative: '$name' is '$FACTS_UNKNOWN' in the machine facts, which means detection could not read it. Correct that value by hand, or run 'xghost machine detect' again.")
		done
		# Every name here holds a value that already failed the check, so the
		# call names the character again rather than deciding anything. The
		# '|| true' is for the caller that runs with errexit set: a safe value
		# is unreachable, and an unreachable case is not a reason to end the
		# shell of somebody who asked for a theme.
		for name in ${RENDER_UNSAFE[@]+"${RENDER_UNSAFE[@]}"}; do
			render_unsafe_reason "${RENDER_SCALARS[$name]}" || true
			RENDER_ERRORS+=("$relative: the value of '$name' holds $RENDER_UNSAFE_REASON: '${RENDER_SCALARS[$name]}'. A value reaches a file another program reads as code, so it holds no quotation mark, no apostrophe, no backtick, no backslash, no dollar sign and no control character. Correct it in the theme palette, the machine facts or the knobs.")
		done
		return 1
	fi

	# The standard error of the write is dropped before the output is opened,
	# so neither a refused open nor a full disk reaches the terminal as a raw
	# diagnostic of the shell.
	if ! printf '%s\n' "$RENDER_CONTENT" 2>/dev/null >"$destination"; then
		RENDER_ERRORS+=("$relative: cannot write the rendered file")
		return 1
	fi

	render_set_mode "$source" "$destination" "$relative"
}
