#!/usr/bin/env bash
#
# The xghost renderer.
#
# render_tree is a pure function. It reads a template directory and a theme,
# and it writes one output directory. The same inputs always produce the same
# output. It writes nothing outside the output directory it is given, and it
# never moves that directory into place: lib/theme.sh does that.
#
# The module prints nothing. It collects every problem in RENDER_ERRORS and
# leaves the reporting to the caller.
#
# This module needs lib/palette.sh.

# Set by render_tree.
RENDER_ERRORS=()

# A placeholder in a template. The name is upper case, so ordinary text such as
# a CSS at-rule is never mistaken for one.
readonly RENDER_PLACEHOLDER_PATTERN='@[A-Z][A-Z0-9_]*@'

# Render one template directory into one output directory.
#
#   render_tree TEMPLATE_DIR THEME_DIR FACTS_FILE KNOBS_FILE OUT_DIR
#
# The renderer takes three inputs by design: the theme, the machine facts, and
# the knobs. Machine facts and knobs do not exist yet. Their files are named by
# issue #9 and issue #11, and this slice does not invent their format. Pass an
# empty path for each of the two, which means "absent". A path that is not empty
# is a problem rather than a value the renderer guesses at.
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
	local template_dir=$1 theme_dir=$2 facts_file=$3 knobs_file=$4 out_dir=$5

	RENDER_ERRORS=()

	if [ -n "$facts_file" ]; then
		RENDER_ERRORS+=("machine facts are not an input yet; issue #9 defines that file. Pass an empty path.")
	fi
	if [ -n "$knobs_file" ]; then
		RENDER_ERRORS+=("knobs are not an input yet; issue #11 defines that file. Pass an empty path.")
	fi
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

	if ! mkdir -p "$out_dir"; then
		RENDER_ERRORS+=("cannot create the output directory: $out_dir")
		return 1
	fi

	local overrides_dir=$theme_dir/files
	local path relative destination

	# The templates. A template whose relative path the theme also ships by hand
	# is passed over, so the hand-written file is never overwritten.
	while IFS= read -r path; do
		relative=${path#"$template_dir/"}
		if [ -e "$overrides_dir/$relative" ]; then
			continue
		fi
		destination=$out_dir/$relative
		if ! mkdir -p "${destination%/*}"; then
			RENDER_ERRORS+=("$relative: cannot create the directory that holds it")
			continue
		fi
		render_file "$path" "$destination" "$relative" || true
	done < <(find "$template_dir" -type f | LC_ALL=C sort)

	# The hand-written files of the theme.
	if [ -d "$overrides_dir" ]; then
		while IFS= read -r path; do
			relative=${path#"$overrides_dir/"}
			destination=$out_dir/$relative
			if ! mkdir -p "${destination%/*}"; then
				RENDER_ERRORS+=("$relative: cannot create the directory that holds it")
				continue
			fi
			if ! cp "$path" "$destination"; then
				RENDER_ERRORS+=("$relative: cannot copy the hand-written file the theme ships")
			fi
		done < <(find "$overrides_dir" -type f | LC_ALL=C sort)
	fi

	[ "${#RENDER_ERRORS[@]}" -eq 0 ]
}

# Substitute the palette into one template file and write the result.
#
# Every '@NAME@' is replaced by the value of NAME. A placeholder the palette has
# no value for is a problem: the renderer reports it and writes no file, rather
# than leaving the name in the output for a user to find later.
#
# The result carries exactly one newline at its end. An executable template
# produces an executable file.
render_file() {
	local source=$1 destination=$2 relative=$3
	local content key leftover name

	if ! content=$(cat -- "$source"); then
		RENDER_ERRORS+=("$relative: cannot read the template")
		return 1
	fi

	for key in "${!PALETTE_SCALARS[@]}"; do
		content=${content//@$key@/${PALETTE_SCALARS[$key]}}
	done

	leftover=$(printf '%s\n' "$content" | grep -oE "$RENDER_PLACEHOLDER_PATTERN" | LC_ALL=C sort -u || true)
	if [ -n "$leftover" ]; then
		while IFS= read -r name; do
			RENDER_ERRORS+=("$relative: the palette has no value for '${name//@/}'")
		done <<<"$leftover"
		return 1
	fi

	if ! printf '%s\n' "$content" >"$destination"; then
		RENDER_ERRORS+=("$relative: cannot write the rendered file")
		return 1
	fi
	if [ -x "$source" ] && ! chmod +x "$destination"; then
		RENDER_ERRORS+=("$relative: cannot make the rendered file executable")
		return 1
	fi
}
