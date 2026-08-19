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
	local path relative destination
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
	# A file inside a choice directory is a fragment rather than a template of
	# its own, so it is written by the loop below this one, and only when it is
	# the fragment the choice selected.
	for path in "${templates[@]}"; do
		relative=${path#"$template_dir/"}
		if render_in_choice "$relative"; then
			continue
		fi
		if [ -e "$overrides_dir/$relative" ] || [ -L "$overrides_dir/$relative" ]; then
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
	# hand-written file of the theme still wins over it.
	local index
	for index in ${RENDER_CHOICE_SOURCES[@]+"${!RENDER_CHOICE_SOURCES[@]}"}; do
		path=${RENDER_CHOICE_SOURCES[index]}
		relative=${RENDER_CHOICE_TARGETS[index]}
		if [ -e "$overrides_dir/$relative" ] || [ -L "$overrides_dir/$relative" ]; then
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
	# A file, or a link, and nothing else. The copy that ran before this reads
	# the files of the theme, so a directory at that path put nothing into the
	# output, and treating it as an image already shipped would leave the
	# wallpaper file naming a path that holds none. A link that points at
	# nothing is a problem render_collect has already reported by name.
	if [ -f "$overrides_dir/$relative" ] || [ -L "$overrides_dir/$relative" ]; then
		RENDER_BACKGROUND=$relative
		return 0
	fi

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
# The pass reads the text once and never reads back what it wrote, so a value
# is copied through as the text it is. Two consequences follow, and both are
# the documented promise that a value is text:
#
#   - A value that holds '&' or a backslash reaches the output unchanged. The
#     '${var//pattern/replacement}' operator would read both of them, because
#     since bash 5.2 it treats '&' in the replacement as the matched text and
#     reads backslash escapes.
#   - A value that holds a placeholder reaches the output as that placeholder.
#     It is never substituted again, so the result does not depend on the order
#     an associative array happens to walk its keys.
render_substitute() {
	local rest=$1
	local out= match prefix name
	local -A seen=() seen_unknown=()

	RENDER_CONTENT=
	RENDER_MISSING=()
	RENDER_UNKNOWN=()

	while [[ $rest =~ $RENDER_PLACEHOLDER_PATTERN ]]; do
		match=${BASH_REMATCH[0]}
		# The regular expression matches the leftmost placeholder, so the text
		# before the first occurrence of that exact string is the text before
		# the match.
		prefix=${rest%%"$match"*}
		rest=${rest#"$prefix$match"}
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

	[ "${#RENDER_MISSING[@]}" -eq 0 ] && [ "${#RENDER_UNKNOWN[@]}" -eq 0 ]
}

# Substitute every known value into one template file and write the result.
#
# Every '@NAME@' is replaced by the value of NAME. A placeholder that has no
# value is a problem: the renderer reports it and writes no file, rather than
# leaving the name in the output for a user to find later. A placeholder whose
# machine fact is 'unknown' is the same problem, because that word is what
# lib/facts.sh writes for a fact nobody could read.
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
