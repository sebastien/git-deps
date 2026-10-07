#!/usr/bin/env bash

#  _____ _ _      ____
# |   __|_| |_   |    \ ___ ___ ___
# |  |  | |  _|  |  |  | -_| . |_ -|
# |_____|_|_|    |____/|___|  _|___|
#                          |_|

# FIXME: Should separate the commands `kebab-case` from the functions `snake_case`.

# Enable colors only when:
#   - NO_COLOR is unset, AND
#   - tput is available, AND
#   - stderr is a terminal OR color is explicitly forced.
# This keeps redirected/non-interactive output free of ANSI sequences, while
# still allowing callers and tests to opt in via CLICOLOR_FORCE.
_git_deps_color=false
if [[ -z "${NO_COLOR:-}" ]] && command -v tput >/dev/null 2>&1; then
	if [[ -t 2 ]] || [[ -n "${CLICOLOR_FORCE:-}" ]]; then
		_git_deps_color=true
	fi
fi

if [[ "$_git_deps_color" == "true" ]]; then
	# Set TERM if not already set
	: "${TERM:=xterm-color}"

	# Direct assignment is faster and safer than eval/subshell
	BLUE_DK="$(tput setaf 27)"
	BLUE="$(tput setaf 33)"
	BLUE_LT="$(tput setaf 117)"
	YELLOW="$(tput setaf 226)"
	ORANGE="$(tput setaf 208)"
	GREEN="$(tput setaf 118)"
	GOLD="$(tput setaf 214)"
	GOLD_DK="$(tput setaf 208)"
	CYAN="$(tput setaf 51)"
	RED="$(tput setaf 196)"
	PURPLE_DK="$(tput setaf 55)"
	PURPLE="$(tput setaf 92)"
	PURPLE_LT="$(tput setaf 163)"
	GRAY="$(tput setaf 153)"
	GRAYLT="$(tput setaf 231)"
	REGULAR="$(tput setaf 7)"
	RESET="$(tput sgr0)"
	BOLD="$(tput bold)"
	UNDERLINE="$(tput smul)"
	REV="$(tput rev)"
	DIM="$(tput dim)"
else
	# If NO_COLOR is set or tput is not available, set empty values
	BLUE_DK="" BLUE="" BLUE_LT="" YELLOW="" ORANGE="" GREEN="" GOLD=""
	GOLD_DK="" CYAN="" RED="" PURPLE_DK="" PURPLE="" PURPLE_LT=""
	GRAY="" GRAYLT="" REGULAR="" RESET="" BOLD="" UNDERLINE="" REV="" DIM=""
fi

# TODO: Add/Remove/Update
#
GIT_DEPS_MODE=git
GIT_DEPS_FILE="${GIT_DEPS_FILE:-.gitdeps}"
GIT_DEPS_SOURCE="${GIT_DEPS_SOURCE:-file}"
GIT_DEPS_REFRESH="${GIT_DEPS_REFRESH:-86400}"
GIT_DEPS_TIMEOUT="${GIT_DEPS_TIMEOUT:-30}"
GIT_DEPS_OFFLINE="${GIT_DEPS_OFFLINE:-false}"
GIT_DEPS_PARALLEL="${GIT_DEPS_PARALLEL:-4}"

if [ -d ".jj" ]; then
	GIT_DEPS_MODE="jj"
fi
case "$0" in
*jj-deps)
	GIT_DEPS_MODE=jj
	;;
esac

# Function: git_deps_log_message
# Logs an informational / secondary message
# Parameters:
#   message - Message to display
function git_deps_log_message {
	local message="$*"
	message="$(git_deps_redact "$message")"
	echo " … $message$RESET" >&2
	return 0
}

function git_deps_log_rollup {
	local path="$1"
	local result="$2"
	shift 2

	local message="$*"
	local symbol="✓"
	local color="${GREEN}"

	case "$result" in
	err)
		symbol="✗"
		color="${RED}"
		;;
	warn)
		symbol="⚠"
		color="${ORANGE}"
		;;
	esac
	message="${message//$'\n'/; }"
	message="$(git_deps_redact "$message")"
	path="$(git_deps_redact "$path")"
	# Errors must carry a next-action tip; add a safe fallback when the caller
	# did not supply a specific one. Warnings only get a tip when explicit.
	if [ "$result" = "err" ] && [[ "$message" != *"Tip:"* ]]; then
		message+="; Tip: inspect '$path' and its entry in $GIT_DEPS_FILE before retrying"
	fi

	if [ -n "$message" ]; then
		echo "${color} ${symbol} [${path}] ${message}${RESET}" >&2
	else
		echo "${color} ${symbol} [${path}]${RESET}" >&2
	fi
	return 0
}

# Function: git_deps_log_error
# Logs an error message in red. Errors are already marked by the ✗ symbol, so
# no literal "Error:" label is added; callers should include dependency context
# (e.g. "[deps/lib]") and a Tip when the next action is known.
# Parameters:
#   message - Error message to display
function git_deps_log_error {
	local message="$*"
	message="$(git_deps_redact "$message")"
	echo "${RED} ✗ $message${RESET}" >&2
	return 1
}

# Function: git_deps_redact
# Removes credentials embedded in URL userinfo (user:pass@ / token@) from a
# string, so they are never echoed to the user or logs.
# Parameters:
#   input - Text that may contain one or more URLs
# Returns: The text with any embedded credentials replaced by "***"
function git_deps_redact {
	local input="$*"
	# Only redact credentials in scheme:// URLs; scp-like git@host:path has no
	# password component and is left untouched.
	printf '%s' "$input" | sed -E 's#([a-zA-Z][a-zA-Z0-9+.-]*://)[^/[:space:]]*@#\1***@#g'
}

# Function: git_deps_log_tip
# Logs a "next action" tip below an error or warning.
# Parameters:
#   message - Tip to display
function git_deps_log_tip {
	local message="$*"
	message="$(git_deps_redact "$message")"
	echo "   Tip: $message" >&2
	return 0
}

# Function: git_deps_log_warning
# Logs a warning message in orange color
# Parameters:
#   message - Warning message to display
function git_deps_log_warning {
	local message="$*"
	message="$(git_deps_redact "$message")"
	echo "${ORANGE} ⚠ $message${RESET}" >&2
	return 0
}

# Function: git_deps_confirm
# Asks for user confirmation unless force flag is set
# Parameters:
#   message - Message to display
#   force - If "true", skip confirmation
# Returns: 0 if confirmed/forced, 1 if declined
function git_deps_confirm {
	local message="$1"
	local force="$2"

	if [ "$force" = "true" ]; then
		return 0
	fi

	echo -n "${YELLOW}$message [y/N]: ${RESET}" >&2
	read -r response
	case "$response" in
	[yY] | [yY][eE][sS])
		return 0
		;;
	*)
		git_deps_log_message "Operation cancelled by user"
		return 1
		;;
	esac
}

# Function: git_deps_path
# Searches for .gitdeps file in current or parent directories
# Returns: Path to .gitdeps file if found
function git_deps_path {
	local dir="$PWD"
	while [[ "$dir" != "/" ]]; do
		if [[ -f "$dir/$GIT_DEPS_FILE" ]]; then
			echo "$dir/.gitdeps"
			return 0
		fi
		dir="$(dirname "$dir")"
	done
	return 1
}

# Function: git_deps_relative_path
# Converts a path to one relative to the current directory when possible.
# Pure-bash replacement for `realpath --relative-to`, which is GNU-only.
# Parameters:
#   target - Path to convert (relative or absolute)
# Returns: Prints the relative path (or the target unchanged if it cannot be made relative)
function git_deps_relative_path {
	local target="$1"

	# Already relative: drop a leading "./"
	if [[ "$target" != /* ]]; then
		printf '%s\n' "${target#./}"
		return 0
	fi

	# Fast path: the target is below the current directory
	if [[ "$target" == "$PWD/"* ]]; then
		printf '%s\n' "${target#"$PWD/"}"
		return 0
	fi

	# Walk the common prefix of PWD and target, then climb back with ../
	# Both paths are absolute, so index 0 (the leading empty segment) is skipped.
	local -a pwd_parts target_parts
	IFS='/' read -ra pwd_parts <<<"$PWD"
	IFS='/' read -ra target_parts <<<"$target"
	local i=1
	while [ "$i" -lt "${#pwd_parts[@]}" ] &&
		[ "$i" -lt "${#target_parts[@]}" ] &&
		[ "${pwd_parts[$i]}" = "${target_parts[$i]}" ]; do
		((i++))
	done

	local rel=""
	local j
	for ((j = i; j < ${#pwd_parts[@]}; j++)); do
		rel+="../"
	done
	for ((j = i; j < ${#target_parts[@]}; j++)); do
		rel+="${target_parts[$j]}/"
	done
	rel="${rel%/}"
	if [ -n "$rel" ]; then
		printf '%s\n' "$rel"
	else
		printf '%s\n' "$target"
	fi
}

function git_deps_file_read {
	if [ -e "$GIT_DEPS_FILE" ]; then
		# Validate .gitdeps file format and warn about issues
		local line_num=0
		local has_errors=false
		local seen_paths=()

		while IFS= read -r line; do
			((line_num++))

			# Skip empty lines and comments
			[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

			# Split line into fields (tab-separated)
			IFS=$' \t' read -ra fields <<<"$line"
			local field_count=${#fields[@]}

			# Validate field count
			if [ "$field_count" -lt 3 ]; then
				git_deps_log_warning "Line $line_num: incomplete entry, expected at least 3 fields (path, url, branch)"
				has_errors=true
			elif [ "$field_count" -gt 5 ]; then
				git_deps_log_warning "Line $line_num: extra fields detected, only using first 4 (path, url, branch, commit)"
			fi

			# Check for duplicate paths
			local path="${fields[0]}"
			if [[ " ${seen_paths[*]} " =~ " $path " ]]; then
				git_deps_log_warning "Duplicate dependency path '$path' found on line $line_num"
				has_errors=true
			else
				seen_paths+=("$path")
			fi
		done <"$GIT_DEPS_FILE"

		# Normalize spaces as pipe `|` for compatibility
		# Filter out comments (lines starting with # after optional whitespace)
		cat "$GIT_DEPS_FILE" | grep -v '^[[:space:]]*#' | tr ' \t' '||' | tr -s '|'
		return 0
	else
		git_deps_log_error "[$GIT_DEPS_FILE] could not be found"
		return 1
	fi
}

# Function: git_deps_list REPO?
# Returns the list of repositories that match the given glob
function git_deps_list {
	local repo_filter="${1:-}"
	# A missing configuration lists nothing; stay silent.
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		return 0
	fi
	if [ -z "$repo_filter" ]; then
		git_deps_file_read | cut -d"|" -f1
	else
		git_deps_file_read | cut -d"|" -f1 | grep "$repo_filter"
	fi
}

function git_deps_write_file {
	local content="$@"
	echo "$content" | sed 's/|/ /g' >"$GIT_DEPS_FILE"
}

# Function: git_deps_ensure_entry
# Adds or updates a dependency entry in the deps file
# Parameters:
#   REPO - Repository path
#   URL - Repository URL
#   BRANCH - Branch name
#   COMMIT - Commit hash
function git_deps_ensure_entry {
	local REPO="$1"
	local URL="$2"
	local BRANCH="$3"
	local COMMIT="$4"
	local LINE
	LINE="$REPO $URL $BRANCH $COMMIT"
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		echo "$LINE" >"$GIT_DEPS_FILE"
	else
		# Match on the exact first field to avoid regex metacharacters in paths
		local EXISTING
		EXISTING=$(awk -v repo="$REPO" 'BEGIN { FS="[ \t]+" } $1 == repo { print; exit }' "$GIT_DEPS_FILE")
		if [ -z "$EXISTING" ]; then
			echo "$LINE" >>"$GIT_DEPS_FILE"
		elif [ "$EXISTING" == "$LINE" ]; then
			return 0
		else
			local TMPFILE=$(mktemp "$GIT_DEPS_FILE".XXX)
			awk -v repo="$REPO" 'BEGIN { FS="[ \t]+" } $1 == repo { next } { print }' "$GIT_DEPS_FILE" >"$TMPFILE"
			echo -e "$LINE" >>"$TMPFILE"
			cat "$TMPFILE" >"$GIT_DEPS_FILE"
			unlink "$TMPFILE"
		fi
	fi
}

function git_deps_read {
	case "$GIT_DEPS_SOURCE" in
	file)
		git_deps_file_read
		return 0
		;;
	*)
		git_deps_log_error "Unsupported source: $GIT_DEPS_SOURCE"
		return 1
		;;
	esac
}

function git_deps_write {
	local content="$@"
	content="# REPO URL BRANCH COMMIT?"$'\n'"$content"$'\n'"# EOF"
	case "$GIT_DEPS_SOURCE" in
	file)
		git_deps_write_file "$content" || return 1
		return 0
		;;
	*)
		git_deps_log_error "Unsupported source: $GIT_DEPS_SOURCE"
		return 1
		;;
	esac
}

# Function: git_deps_state REPO?
function git_deps_state {
	local fields
	local repo="${1:-}"
	for line in $(git_deps_read); do
		if [ -z "$repo" ] || [[ "${line%%|*}" == *"$repo"* ]]; then
			set -a fields
			local temp_ifs="$IFS"
			IFS='|' read -ra fields <<<"$line"
			IFS="$temp_ifs"
			echo "${fields[0]} ${fields[1]} ${fields[2]} ${fields[3]} $(git_deps_op_commit_id "${fields[0]}")"
		fi
	done
}

# Function: git_deps_status
# Returns a combined status string for a dependency
# Parameters:
#   path - Path to dependency
#   repo - Repository URL
#   branch - Branch name
#   commit - Commit hash (optional)
# Returns: Combined status string "dep=STATUS local=STATUS remote=STATUS"
function git_deps_status {
	local path="$1"
	local repo="$2"
	local branch="$3"
	local commit="$4"

	# Get individual statuses
	local dep_status=$(git_deps_status_dep "$path" "$repo" "$branch" "$commit")
	local local_status=$(git_deps_status_local "$path" "$repo" "$branch" "$commit")
	local remote_status=$(git_deps_status_remote "$repo" "$branch" "$commit" "$path")

	# Output combined format
	echo "dep=$dep_status local=$local_status remote=$remote_status"
}

# ----------------------------------------------------------------------------
#
# GIT/JJ WRAPPER
#
# ----------------------------------------------------------------------------

# Function: git_deps_op_clone
# Clones a repository using git or jj with validation
# Parameters:
#   repo - Repository URL
#   path - Local path to clone to
# Returns: 0 on success, 1 on failure
function git_deps_op_clone {
	local repo="$1"
	local repo_path="$2"
	local quiet="${3:-false}"
	local parent
	local output
	parent="$(dirname "$repo_path")"
	if [ ! -e "$parent" ]; then
		mkdir -p "$parent"
	fi
	if [ "$GIT_DEPS_MODE" == "jj" ]; then
		if ! output=$(jj git clone --colocate "$repo" "$repo_path" 2>&1); then
			output="${output//$'\n'/; }"
			if [ "$quiet" = "true" ]; then
				echo "clone failed from $repo: $output; Tip: check the URL and repository access"
			else
				git_deps_log_error "[$repo_path] clone failed from $repo: $output; Tip: check the URL and repository access"
			fi
			return 1
		fi
	else
		if ! output=$(git clone --quiet "$repo" "$repo_path" 2>&1); then
			output="${output//$'\n'/; }"
			if [ "$quiet" = "true" ]; then
				echo "clone failed from $repo: $output; Tip: check the URL and repository access"
			else
				git_deps_log_error "[$repo_path] clone failed from $repo: $output; Tip: check the URL and repository access"
			fi
			return 1
		fi
	fi

	if [ "$quiet" != "true" ]; then
		git_deps_log_rollup "$repo_path" ok "Cloned from $repo at $(git_deps_op_commit_info "$repo_path")"
	fi
	return 0
}

function git_deps_op_fetch {
	local path="$1"
	local origin="${2:-}"
	local quiet="${3:-false}"

	# Skip fetch in offline mode
	if [ "$GIT_DEPS_OFFLINE" = "true" ]; then
		return 0
	fi

	if ! git_deps_file_aged "$path"; then
		return 0
	fi

	# Use timeout to prevent hanging on unresponsive remotes
	local fetch_args=(git -C "$path" fetch --quiet)
	[ -z "$origin" ] || fetch_args+=("$origin")
	local output
	local fetch_result=0

	if command -v timeout >/dev/null 2>&1; then
		# GNU coreutils timeout (Linux)
		if output=$(timeout "${GIT_DEPS_TIMEOUT}s" "${fetch_args[@]}" 2>&1); then
			fetch_result=0
		else
			fetch_result=$?
		fi
	elif command -v gtimeout >/dev/null 2>&1; then
		# GNU coreutils timeout on macOS (via brew install coreutils)
		if output=$(gtimeout "${GIT_DEPS_TIMEOUT}s" "${fetch_args[@]}" 2>&1); then
			fetch_result=0
		else
			fetch_result=$?
		fi
	else
		# Fallback: use perl for timeout on macOS without coreutils
		if output=$(perl -e "alarm ${GIT_DEPS_TIMEOUT}; exec @ARGV" -- "${fetch_args[@]}" 2>&1); then
			fetch_result=0
		else
			fetch_result=$?
		fi
	fi

	if [ $fetch_result -eq 0 ]; then
		# We touch the path so that the age is updated
		touch "$path"
		return 0
	elif [ $fetch_result -eq 124 ] || [ $fetch_result -eq 142 ]; then
		# 124 = timeout exit code, 142 = SIGALRM (perl timeout)
		if [ "$quiet" = "true" ]; then
			echo "Fetch timed out after ${GIT_DEPS_TIMEOUT}s: $path"
		else
			git_deps_log_warning "[$path] fetch timed out after ${GIT_DEPS_TIMEOUT}s; Tip: check connectivity or increase GIT_DEPS_TIMEOUT"
		fi
		return 1
	else
		if [ "$quiet" = "true" ]; then
			echo "[$path] fetch failed (${origin:-origin}): $output; Tip: check network access and git -C '$path' remote -v"
		else
			git_deps_log_error "[$path] fetch failed (${origin:-origin}): $output; Tip: check network access and git -C '$path' remote -v"
		fi
		return 1
	fi
}

function git_deps_file_age {
	local path="$1"
	if [ ! -e "$path" ]; then
		return 0
	fi
	local now=$(date +%s)
	local mtime=$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null)
	echo "$((now - mtime))"
}

function git_deps_file_aged {
	local limit="${2:-${GIT_DEPS_REFRESH}}"
	local age=$(git_deps_file_age "$1")
	if ((age > limit)); then
		return 1
	else
		return 0
	fi
}

# Function: git_deps_op_is_ancestor
# Checks if one commit is an ancestor of another
# Parameters:
#   path - Path to the git repository
#   ancestor - The potential ancestor commit
#   descendant - The potential descendant commit
# Returns: 0 if ancestor is an ancestor of descendant, 1 otherwise
function git_deps_op_is_ancestor {
	local path="$1"
	local ancestor="$2"
	local descendant="$3"
	git -C "$path" merge-base --is-ancestor "$ancestor" "$descendant" 2>/dev/null
}

# Global variable to capture checkout error message
GIT_CHECKOUT_ERROR=""

# Function: git_deps_op_checkout
# Checks out a specific revision in a git repository
# Parameters:
#   path - Path to the git repository
#   rev - Revision to checkout (branch, tag, or commit)
# Returns: 0 on success, 1 on failure
# Side effect: Sets GIT_CHECKOUT_ERROR with error message on failure
function git_deps_op_checkout {
	local path="$1"
	local rev="$2"
	local res=0
	local output

	# Capture both stdout and stderr
	output=$(git -C "$path" checkout "$rev" 2>&1)
	res=$?

	if [ $res -ne 0 ]; then
		GIT_CHECKOUT_ERROR="$output"
	else
		GIT_CHECKOUT_ERROR=""
	fi

	return $res
}

function git_deps_op_localchanges {
	local path="$1"
	if [ "$GIT_DEPS_MODE" == "jj" ]; then
		# Working copy changes:
		# A .gitdeps
		# Working copy : klywuowv ee6d952f (no description set)
		# Parent commit: zzzzzzzz 00000000 (empty) (no description set)
		jj -R "$path" status 2>/dev/null | head -n -2 | tail -n +2
	else
		git -C "$path" status --porcelain | grep -v '??'
	fi
}

function git_deps_op_commit_id {
	local path="$1"
	local rev="${2:-HEAD}"
	if ! git -C "$path" rev-parse "$rev" 2>/dev/null; then
		return 1
	fi
}

# --
# Returns the commit date for a given commit
# Parameters:
#   path - Repository path
#   commit - Commit hash (optional, defaults to HEAD)
function git_deps_op_commit_date {
	local path="$1"
	local commit="${2:-HEAD}"

	if ! git -C "$path" rev-parse --verify "$commit" >/dev/null 2>&1; then
		echo ""
		return 1
	fi

	git -C "$path" show -s --date=format-local:'%Y-%m-%d %H:%M:%S' --format="%cd" "$commit" 2>/dev/null || echo ""
}

function git_deps_op_commit_info {
	local path="$1"
	local commit="${2:-HEAD}"
	local commit_id
	local commit_date
	commit_id=$(git -C "$path" rev-parse --verify "$commit^{commit}" 2>/dev/null) || {
		echo "$commit (date unavailable)"
		return 0
	}
	commit_date=$(git_deps_op_commit_date "$path" "$commit_id" 2>/dev/null || true)
	echo "$commit_id${commit_date:+ ($commit_date)}"
}

# --
# Tells if the current revision is a named branch `branch`, or
# an unnamed commit `hash`, or if it is simply unknown.
function git_deps_op_identify_rev {
	local path="$1"
	local rev="$2"
	if git -C "$path" show-ref --quiet --heads "$rev" || git -C "$path" show-ref --quiet --tags "$rev"; then
		echo "branch"
	elif git -C "$path" rev-parse --verify "$rev^{commit}" >/dev/null 2>&1; then
		echo "hash"
	else
		echo "unknown"
	fi
}

# Function: git_deps_op_has_unpushed_commits
# Checks if repository has commits that haven't been pushed to remote
# Parameters:
#   path - Repository path
#   branch - Branch name (optional, defaults to current branch)
# Returns: 0 if has unpushed commits, 1 if not
function git_deps_op_has_unpushed_commits {
	local path="$1"
	local branch="${2:-$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")}"
	local remote="origin"

	# Detached HEAD: try to resolve a sensible branch to compare against.
	# Otherwise we end up checking origin/HEAD (which often doesn't exist) and
	# incorrectly report "unpushed commits".
	if [ "$branch" = "HEAD" ] || [ -z "$branch" ]; then
		local upstream
		upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
		if [ -n "$upstream" ] && [[ "$upstream" == */* ]]; then
			remote="${upstream%%/*}"
			branch="${upstream#*/}"
		else
			local containing
			containing=$(git -C "$path" branch -r --contains HEAD 2>/dev/null | sed -n 's/^[*[:space:]]*//p' | head -n 1)
			if [ -n "$containing" ] && [[ "$containing" == */* ]]; then
				remote="${containing%%/*}"
				branch="${containing#*/}"
			else
				# Pinned/colocated dependency at a commit; "unpushed" doesn't apply.
				return 1
			fi
		fi
	fi

	# Check if remote branch exists
	if ! git -C "$path" rev-parse --verify "$remote/$branch" >/dev/null 2>&1; then
		# No remote branch, so local commits exist
		return 0
	fi

	# Check if local is ahead of remote
	local ahead=$(git -C "$path" rev-list --count "$remote/$branch..HEAD" 2>/dev/null || echo "0")
	if [ "$ahead" -gt 0 ]; then
		return 0
	else
		return 1
	fi
}

# Function: git_deps_op_commit_on_remote
# Checks whether a commit is reachable from a cached remote-tracking ref
function git_deps_op_commit_on_remote {
	local path="$1"
	local commit="$2"

	git -C "$path" for-each-ref --contains "$commit" --format='%(refname)' refs/remotes 2>/dev/null | grep -q .
}

# Function: git_deps_op_has_remote_refs
# Checks whether a repository has any cached remote-tracking ref
function git_deps_op_has_remote_refs {
	local path="$1"

	git -C "$path" for-each-ref --format='%(refname)' refs/remotes 2>/dev/null | grep -q .
}

# Function: git_deps_op_remote_ancestor
# Finds the nearest first-parent ancestor reachable from a cached remote ref
function git_deps_op_remote_ancestor {
	local path="$1"
	local commit="$2"

	while git -C "$path" rev-parse --verify "$commit^{commit}" >/dev/null 2>&1; do
		if git_deps_op_commit_on_remote "$path" "$commit"; then
			echo "$commit"
			return 0
		fi
		commit=$(git -C "$path" rev-parse --verify "$commit^1" 2>/dev/null) || return 1
	done

	return 1
}

# ----------------------------------------------------------------------------
#
# DEPENDENCY MANAGEMENT
#
# ----------------------------------------------------------------------------

# Function: git_deps_has
# Checks if a dependency is registered at the given path
# Parameters:
#   path - Path to check
# Returns: 0 if dependency exists, 1 if it doesn't
function git_deps_has {
	local path="$1"
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		return 1
	fi
	grep -E "^${path}[[:blank:]]" "$GIT_DEPS_FILE" >/dev/null 2>&1
}

# Function: git_deps_add
# Adds a new dependency to the project
# Parameters:
#   repo - Repository URL
#   path - Local path for the dependency
#   branch - Branch/tag/commit to track (optional, defaults to remote default)
#   commit - Specific commit (optional)
#   force - Force flag (optional)
function git_deps_add {
	local repo="$1"
	local path="$2"
	local branch_input="${3:-}"
	local commit="$4"
	local force="$5"
	local operation_logs=""
	local status="ok"
	local final_commit=""
	local final_branch=""

	# DEBUG
	operation_logs="DEBUG: repo=$repo, path=$path, branch_input=$branch_input, commit=$commit"
	if [ -z "$repo" ] || [ -z "$path" ]; then
		echo "err|$path|$repo||$commit|Usage: git-deps add REPO_PATH REPO_URL [BRANCH] [COMMIT]"
		return 1
	fi

	# Check if path already exists (unless force is specified)
	if [ "$force" != "true" ] && [ -e "$path" ]; then
		echo "err|$path|$repo||$commit|Path '$path' already exists"
		return 1
	fi

	# Remove existing path if force is specified
	if [ "$force" = "true" ] && [ -e "$path" ]; then
		rm -rf "$path"
	fi

	# Check if dependency already exists (unless force is specified)
	if [ "$force" != "true" ] && git_deps_has "$path"; then
		echo "err|$path|$repo|$branch_input|$commit|Dependency already registered at '$path'. Run 'git-deps add -f $path $repo $branch_input $commit'"
		return 1
	fi

	operation_logs="Adding $repo to $path"

	# Clone the repository
	local clone_output
	if ! clone_output=$(git_deps_op_clone "$repo" "$path" "true"); then
		echo "err|$path|$repo|$branch_input|$commit|$clone_output"
		return 1
	fi
	operation_logs="$operation_logs|Repository cloned successfully"

	# Get the current commit ID and branch after clone (clone already checks out the remote default)
	local current_commit
	local current_branch
	local default_branch
	current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "unknown")
	current_branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

	# Try to detect the remote default branch from origin/HEAD
	# This handles repos that use 'master' or other non-main defaults
	local symref_raw
	local default_branch=""
	symref_raw=$(git -C "$path" symbolic-ref refs/remotes/origin/HEAD 2>&1)
	if [ $? -eq 0 ]; then
		# symbolic-ref succeeded
		default_branch=$(echo "$symref_raw" | sed 's|^refs/remotes/origin/||')
	else
		# symbolic-ref failed - try alternative methods
		# Method 1: Try to get the default branch from git remote show
		default_branch=$(git -C "$path" remote show origin 2>/dev/null | grep "HEAD branch" | sed 's/.*HEAD branch: //')
		# Method 2: If still empty, look for common default branch names
		if [ -z "$default_branch" ]; then
			for try_branch in main master trunk; do
				if git -C "$path" rev-parse --verify "origin/$try_branch" >/dev/null 2>&1; then
					default_branch="$try_branch"
					break
				fi
			done
		fi
	fi

	# Determine which branch to use
	# Priority: 1) explicitly specified, 2) current branch from clone, 3) remote default, 4) fallback to main
	if [ -n "$branch_input" ]; then
		final_branch="$branch_input"
	elif [ -n "$current_branch" ] && [ "$current_branch" != "HEAD" ]; then
		final_branch="$current_branch"
	elif [ -n "$default_branch" ]; then
		final_branch="$default_branch"
	else
		# Last resort fallback
		final_branch="main"
	fi

	# Only checkout if a specific branch or commit was explicitly requested
	# The clone already checks out the remote's default branch, so we only need to checkout
	# if the user explicitly requested something different
	local checkout_rev=""
	if [ -n "$commit" ]; then
		# User explicitly specified a commit
		checkout_rev="$commit"
	elif [ -n "$branch_input" ]; then
		# User explicitly specified a branch
		checkout_rev="$branch_input"
	fi

	# Perform checkout only if needed (i.e., user explicitly requested a branch/commit)
	if [ -n "$checkout_rev" ]; then
		if ! git_deps_op_checkout "$path" "$checkout_rev" 2>/dev/null; then
			# Clean up on failure
			rm -rf "$path" 2>/dev/null
			echo "err|$path|$repo|$final_branch|$commit|Failed to checkout $checkout_rev: $GIT_CHECKOUT_ERROR; Tip: verify the branch or pin in $GIT_DEPS_FILE"
			return 1
		fi
		operation_logs="$operation_logs|Checked out to $checkout_rev"
		# Update current commit after checkout
		current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "unknown")
	fi

	# Use specified commit if provided, otherwise use current commit
	final_commit="${commit:-$current_commit}"

	# Add to deps file
	git_deps_ensure_entry "$path" "$repo" "$final_branch" "$final_commit" 2>/dev/null
	operation_logs="$operation_logs|Added entry to .gitdeps"

	# Return structured output: status|path|repo|branch|commit|logs
	echo "ok|$path|$repo|$final_branch|$final_commit|$operation_logs"
	return 0
}

# Function: git_deps_remove
# Removes a dependency entry from the deps file
# Parameters:
#   path - Local path for the dependency
# Returns: structured output status|path|logs
function git_deps_remove {
	local path="$1"

	if [ -z "$path" ]; then
		echo "err|$path|Usage: git-deps remove PATHS..."
		return 1
	fi

	if [ ! -e "$GIT_DEPS_FILE" ]; then
		echo "err|$path|[$GIT_DEPS_FILE] could not be found"
		return 1
	fi

	local tmpfile
	tmpfile=$(mktemp "$GIT_DEPS_FILE".XXX)
	local found="false"

	while IFS= read -r line || [ -n "$line" ]; do
		if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
			echo "$line" >>"$tmpfile"
			continue
		fi

		local entry_path=""
		local temp_ifs="$IFS"
		IFS=$' \t'
		read -r entry_path _rest <<<"$line"
		IFS="$temp_ifs"

		if [ "$entry_path" = "$path" ]; then
			found="true"
			continue
		fi

		echo "$line" >>"$tmpfile"
	done <"$GIT_DEPS_FILE"

	if [ "$found" != "true" ]; then
		unlink "$tmpfile"
		echo "err|$path|Dependency not registered at '$path'"
		return 1
	fi

	cat "$tmpfile" >"$GIT_DEPS_FILE"
	unlink "$tmpfile"
	echo "ok|$path|Removed dependency from $GIT_DEPS_FILE"
	return 0
}

# function git_deps_save {
# }
#
# function git_deps_pull {
#
# }
#
# function git_deps_push {
#
# }

# Function: git_deps_status_dep
# Checks the status of a dependency entry
# Parameters:
#   path - Path to dependency
#   repo - Repository URL
#   branch - Branch name
#   commit - Commit hash (optional)
# Returns: Status string with color codes
function git_deps_status_dep {
	local path="$1"
	local repo="$2"
	local branch="$3"
	local commit="$4"
	local remote_commit="${5:-}"
	local status=""
	local color=""

	# Check if local exists
	if [ ! -e "$path" ] || [ ! -e "$path/.git" ]; then
		status="[BEHIND]"
		color="${YELLOW}"
	else
		local current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "")

		# Use pre-fetched remote_commit to determine remote availability
		# This avoids redundant ls-remote network calls
		if [ -z "$remote_commit" ] || [ "$remote_commit" = "unknown" ]; then
			# Remote was not reachable during fetch
			status="[UNAVAILABLE]"
			color="${RED}"
		elif [ -n "$commit" ] && ! git -C "$path" cat-file -e "$commit" 2>/dev/null; then
			# Check if specific commit exists locally
			status="[MISSING]"
			color="${RED}"
		elif [ -n "$commit" ] && [ "$current_commit" = "$commit" ] && [ -z "$(git_deps_op_localchanges "$path")" ]; then
			# Exact match with specified commit and no local changes
			status="✓ [SYNCED]"
			color="${GREEN}"
		elif [ -z "$commit" ] && [ -z "$(git_deps_op_localchanges "$path")" ]; then
			# No specific commit specified, check against current state
			status="✓ [SYNCED]"
			color="${GREEN}"
		else
			# Use the pre-fetched remote commit to avoid redundant fetches
			local dep_commit="${commit}"

			# If local differs from dep, show outdated
			if [ -n "$dep_commit" ] && [ "$current_commit" != "$dep_commit" ]; then
				status="⚠ [OUTDATED]"
				color="${ORANGE}"
			# If dep is behind local or remote, show behind
			elif [ -n "$dep_commit" ] && [ -n "$current_commit" ]; then
				if git -C "$path" rev-parse --verify "$dep_commit" >/dev/null 2>&1; then
					if git -C "$path" merge-base --is-ancestor "$dep_commit" "$current_commit" 2>/dev/null; then
						status="↓ [BEHIND]"
						color="${YELLOW}"
					elif [ -n "$remote_commit" ] && git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
						if git -C "$path" merge-base --is-ancestor "$dep_commit" "$remote_commit" 2>/dev/null; then
							status="[BEHIND]"
							color="${YELLOW}"
						else
							status="[SYNCED]"
							color="${GREEN}"
						fi
					else
						status="[SYNCED]"
						color="${GREEN}"
					fi
				else
					status="[BEHIND]"
					color="${YELLOW}"
				fi
			else
				status="[SYNCED]"
				color="${GREEN}"
			fi
		fi
	fi

	echo "${color}${status}${RESET}"
}

# Function: git_deps_status_local
# Checks the status of local repository against dependency
# Parameters:
#   path - Path to dependency
#   repo - Repository URL
#   branch - Branch name
#   commit - Commit hash (optional)
# Returns: Status string with color codes
function git_deps_status_local {
	local path="$1"
	local repo="$2"
	local branch="$3"
	local commit="$4"
	local remote_commit="${5:-}"
	local status=""
	local color=""

	# Check if local exists
	if [ ! -e "$path" ] || [ ! -e "$path/.git" ]; then
		status="[MISSING]"
		color="${GRAY}"
		echo "${color}${status}${RESET}"
		return
	fi

	local current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "")
	local target_commit="${commit}"
	local local_changes=$(git_deps_op_localchanges "$path")

	# If no specific commit in dependency, use pre-fetched remote branch head
	if [ -z "$target_commit" ]; then
		target_commit="$remote_commit"
	fi

	# Check for uncommited changes first
	if [ -n "$local_changes" ]; then
		# Use pre-fetched remote_commit (passed as $5) instead of redundant ls-remote call
		if [ -n "$remote_commit" ] && [ "$remote_commit" != "unknown" ] && [ "$current_commit" != "$remote_commit" ]; then
			if git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
				if git -C "$path" merge-base --is-ancestor "$remote_commit" "$current_commit" 2>/dev/null; then
					status="[AHEAD+UNCOMMITTED]"
					color="${GOLD}"
				else
					status="[UNCOMMITTED]"
					color="${GOLD}"
				fi
			else
				status="[AHEAD+UNCOMMITTED]"
				color="${GOLD}"
			fi
		else
			status="[UNCOMMITTED]"
			color="${GOLD}"
		fi
	else
		# Determine base status relative to remote only (remove dep_relation logic)
		local remote_relation=""

		# Use pre-fetched remote commit for relationship check

		if [ -n "$remote_commit" ] && [ "$current_commit" != "$remote_commit" ]; then
			# Check relationship with remote
			if git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
				if git -C "$path" merge-base --is-ancestor "$current_commit" "$remote_commit" 2>/dev/null; then
					remote_relation="behind"
				elif git -C "$path" merge-base --is-ancestor "$remote_commit" "$current_commit" 2>/dev/null; then
					remote_relation="ahead"
				else
					remote_relation="conflict"
				fi
			else
				remote_relation="behind"
			fi
		fi

		# Set status based on remote relationship only
		case "$remote_relation" in
		behind)
			status="↓ [BEHIND]"
			color="${YELLOW}"
			;;
		ahead)
			status="↑ [AHEAD]"
			color="${GOLD}"
			;;
		conflict)
			status="[CONFLICT]"
			color="${RED}"
			;;
		*)
			# Everything matches
			status="✓ [SYNCED]"
			color="${GREEN}"
			;;
		esac
	fi

	echo "${color}${status}${RESET}"
}

# Function: git_deps_status_remote
# Checks the status of remote repository
# Parameters:
#   repo - Repository URL
#   branch - Branch name
#   commit - Commit hash (optional)
#   path - Local path (for comparison)
# Returns: Status string with color codes
function git_deps_status_remote {
	local repo="$1"
	local branch="$2"
	local commit="$3"
	local path="$4"
	local remote_commit="${5:-}"
	local status=""
	local color=""

	# Use pre-fetched remote commit data
	if [ -z "$remote_commit" ] || [ "$remote_commit" = "unknown" ]; then
		status="[UNAVAILABLE]"
		color="${GRAY}"
		echo "${color}${status}${RESET}"
		return
	fi

	# Check if branch exists in remote (using pre-fetched data)
	if [ -n "$branch" ] && ! git -C "$path" rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
		status="[MISSING]"
		color="${RED}"
		echo "${color}${status}${RESET}"
		return
	fi

	# Compare with dependency commit if available
	local dep_commit="$commit"

	# Compare with local if path provided (this takes precedence over dep comparison)
	if [ -n "$path" ] && [ -e "$path/.git" ]; then
		local local_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "")
		if [ -n "$local_commit" ] && [ "$local_commit" != "unknown" ]; then
			# If remote matches local exactly, it's synced
			if [ "$remote_commit" = "$local_commit" ]; then
				status="✓ [SYNCED]"
				color="${GREEN}"
			# Check if we can resolve remote commit in local repo
			elif git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
				if git -C "$path" merge-base --is-ancestor "$remote_commit" "$local_commit" 2>/dev/null; then
					# Remote is ancestor of local - remote is behind
					status="↓ [BEHIND]"
					color="${YELLOW}"
				elif git -C "$path" merge-base --is-ancestor "$local_commit" "$remote_commit" 2>/dev/null; then
					# Local is ancestor of remote - remote is ahead
					status="↑ [AHEAD]"
					color="${GOLD}"
				else
					# Diverged - remote has different commits
					status="[DIVERGED]"
					color="${ORANGE}"
				fi
			else
				# Remote commit not in local - remote is ahead
				status="[AHEAD]"
				color="${GOLD}"
			fi
		else
			status="[AHEAD]"
			color="${GOLD}"
		fi
	elif [ -n "$dep_commit" ] && [ "$remote_commit" = "$dep_commit" ]; then
		# If no local path but remote matches dependency commit
		status="✓ [SYNCED]"
		color="${GREEN}"
	else
		status="[AHEAD]"
		color=""
	fi

	echo "${color}${status}${RESET}"
}

# Function: git_deps_update
# Updates a dependency to the latest from remote with validation
# Parameters:
#   pinned_mode - "true" to checkout to pinned commit, "false" to fast-forward to latest
#   force - "true" to bypass safety checks
#   path - Path to dependency
#   repo - Repository URL
#   branch - Target branch (defaults to main)
#   commit - Target commit (optional, only used in pinned mode)
#   at - Select the latest branch commit at or before this date (optional)
# Returns: Outputs status code and returns 0/1
function git_deps_update {
	local pinned_mode="$1"
	local force="$2"
	local path="$3"
	local repo="$4"
	local branch="${5:-main}"
	local commit="${6:-}"
	local at="${7:-}"

	if [ -z "$path" ]; then
		echo "err-missing-path"
		return 1
	elif [ -z "$repo" ]; then
		echo "err-missing-repo"
		return 1
	fi

	# Clone if path doesn't exist
	if [ ! -e "$path" ]; then
		if ! git_deps_op_clone "$repo" "$path"; then
			echo "err-clone-failed"
			return 1
		fi
	fi

	# STRICT SAFETY CHECKS - both uncommitted changes and unpushed commits are errors
	local local_changes=$(git_deps_op_localchanges "$path")
	local has_unpushed="false"
	if git_deps_op_has_unpushed_commits "$path" "$branch"; then
		has_unpushed="true"
	fi

	if [ "$force" != "true" ]; then
		if [ -n "$local_changes" ]; then
			git_deps_log_warning "Cannot update $path: has uncommitted changes"
			git_deps_log_tip "commit or stash changes: git -C '$path' status"
			echo "err-uncommitted"
			return 1
		fi
		if [ "$has_unpushed" = "true" ]; then
			git_deps_log_warning "Cannot update $path: has unpushed commits"
			git_deps_log_tip "push changes first: git -C '$path' push"
			echo "err-unpushed"
			return 1
		fi
	else
		# Log warnings but proceed with --force
		if [ -n "$local_changes" ]; then
			git_deps_log_message "Warning: has uncommitted changes (proceeding with --force)"
		fi
		if [ "$has_unpushed" = "true" ]; then
			git_deps_log_message "Warning: has unpushed commits (proceeding with --force)"
		fi
	fi

	# Fetch latest changes from remote
	if ! git_deps_op_fetch "$path"; then
		echo "err-fetch-failed"
		return 1
	fi

	# Get current state
	local current_branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
	local current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "")

	if [ -n "$at" ]; then
		# Prefer main when it exists; otherwise use the dependency's configured branch.
		local target_branch="$branch"
		if git -C "$path" show-ref --verify --quiet refs/remotes/origin/main; then
			target_branch="main"
		fi
		local target_commit
		target_commit=$(git -C "$path" log --date-order -1 --before="$at" --format=%H "origin/$target_branch" 2>/dev/null || true)
		if [ -z "$target_commit" ]; then
			git_deps_log_warning "No commit on origin/$target_branch at or before $at for $path"
			echo "err-no-commit-at-date"
			return 1
		fi
		local current_date=""
		local target_date
		current_date=$(git_deps_op_commit_date "$path" "$current_commit" 2>/dev/null || true)
		target_date=$(git_deps_op_commit_date "$path" "$target_commit" 2>/dev/null || true)
		local from="${current_commit:-none}"
		[ -z "$current_date" ] || from="$from ($current_date)"
		local to="$target_commit"
		[ -z "$target_date" ] || to="$to ($target_date)"
		if [ "$current_commit" = "$target_commit" ]; then
			echo "ok-at-date"
		elif git_deps_op_checkout "$path" "$target_commit"; then
			git_deps_log_rollup "$path" ok "Updated on $target_branch: $from → $to (target: $at)"
			echo "ok-at-date"
		else
			git_deps_log_error "[$path] checkout failed for $(git_deps_op_commit_info "$path" "$target_commit"): $GIT_CHECKOUT_ERROR; Tip: inspect git -C '$path' status"
			echo "err-checkout-failed"
			return 1
		fi
	elif [ "$pinned_mode" = "true" ]; then
		# PINNED MODE: Checkout to exact pinned commit
		if [ -z "$commit" ]; then
			git_deps_log_error "[$path] no pinned commit specified"
			git_deps_log_tip "the .gitdeps entry for this dependency has no commit hash"
			echo "err-no-pinned-commit"
			return 1
		fi

		# Check if pinned commit exists after fetch
		if ! git -C "$path" cat-file -e "$commit^{commit}" >/dev/null 2>&1; then
			git_deps_log_error "[$path] pinned commit $commit (date unavailable) not found"
			git_deps_log_tip "check the saved pin in $GIT_DEPS_FILE and repository history with git -C '$path' log --all"
			echo "err-pinned-missing"
			return 1
		fi

		# Checkout to pinned commit
		local commit_info
		commit_info=$(git_deps_op_commit_info "$path" "$commit")
		if [ "$current_commit" = "$commit" ]; then
			echo "ok-already-pinned"
		else
			if ! git_deps_op_checkout "$path" "$commit"; then
				git_deps_log_error "[$path] checkout failed for $commit_info: $GIT_CHECKOUT_ERROR"
				git_deps_log_tip "inspect local changes with git -C '$path' status before retrying"
				echo "err-checkout-failed"
				return 1
			fi
			git_deps_log_rollup "$path" ok "Checked out pinned commit $commit_info"
			echo "ok-pinned"
		fi
	else
		# DEFAULT MODE: Fast-forward to latest branch HEAD
		local remote_head=$(git -C "$path" rev-parse origin/$branch 2>/dev/null || echo "")

		if [ -z "$remote_head" ]; then
			git_deps_log_warning "Remote branch origin/$branch not found for $path"
			git_deps_log_tip "check available branches: git -C '$path' branch -r"
			echo "err-no-remote-branch"
			return 1
		fi

		# Check if we can fast-forward
		local current_info remote_info
		current_info=$(git_deps_op_commit_info "$path" "$current_commit")
		remote_info=$(git_deps_op_commit_info "$path" "$remote_head")
		if [ "$current_commit" = "$remote_head" ]; then
			echo "ok-up-to-date"
		elif git -C "$path" merge-base --is-ancestor "$current_commit" "$remote_head" 2>/dev/null; then
			# Can fast-forward
			local merge_output
			if ! merge_output=$(git -C "$path" merge --ff-only "$remote_head" 2>&1); then
				git_deps_log_error "[$path] fast-forward failed: $merge_output"
				git_deps_log_tip "inspect git -C '$path' status, then resolve manually or reset with 'git-deps checkout'"
				echo "err-fast-forward-failed"
				return 1
			fi
			git_deps_log_rollup "$path" ok "Updated on $branch: $current_info → $remote_info"
			echo "ok-fast-forwarded"
		else
			# Cannot fast-forward - diverged
			git_deps_log_warning "Cannot fast-forward $path: local branch has diverged from remote"
			git_deps_log_tip "resolve manually or reset to the saved state with 'git-deps checkout'"
			echo "err-diverged"
			return 1
		fi
	fi
}

# ----------------------------------------------------------------------------
#
# HIGH LEVEL COMMANDS
#
# ----------------------------------------------------------------------------

function git-deps-status {
	local STATUS
	local old_ifs="$IFS"
	IFS=$'\n'
	local TOTAL=0
	local seen_paths=""
	local line_num=1
	local specified_paths=()
	local invalid_paths=()
	local valid_paths=()

	# Parse arguments - collect specified paths and flags
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--offline | -o)
			GIT_DEPS_OFFLINE=true
			shift
			;;
		--timeout=*)
			GIT_DEPS_TIMEOUT="${1#--timeout=}"
			shift
			;;
		--timeout | -t)
			GIT_DEPS_TIMEOUT="$2"
			shift 2
			;;
		--parallel=*)
			GIT_DEPS_PARALLEL="${1#--parallel=}"
			shift
			;;
		--parallel | -p)
			GIT_DEPS_PARALLEL="$2"
			shift 2
			;;
		--no-parallel)
			GIT_DEPS_PARALLEL=1
			shift
			;;
		--help | -h)
			echo "Usage: git-deps status [OPTIONS] [PATH...]"
			echo ""
			echo "Options:"
			echo "  --offline, -o       Skip network operations, use cached data only"
			echo "  --timeout=SECONDS   Set network timeout (default: ${GIT_DEPS_TIMEOUT})"
			echo "  --parallel=N        Max parallel fetches (default: ${GIT_DEPS_PARALLEL})"
			echo "  --no-parallel       Disable parallel fetches (same as --parallel=1)"
			echo "  --help, -h          Show this help message"
			echo ""
			echo "Environment variables:"
			echo "  GIT_DEPS_OFFLINE    Set to 'true' for offline mode"
			echo "  GIT_DEPS_TIMEOUT    Network timeout in seconds (default: 30)"
			echo "  GIT_DEPS_PARALLEL   Max parallel fetches (default: 4)"
			echo "  GIT_DEPS_REFRESH    Cache duration in seconds (default: 86400)"
			return 0
			;;
		-*)
			git_deps_log_error "Unknown option: $1"
			return 1
			;;
		*)
			specified_paths+=("$1")
			shift
			;;
		esac
	done

	# status is a read-only request: a missing configuration simply means there
	# are no dependencies to report. Stay silent and succeed — unless the caller
	# explicitly asked about a path, which cannot be registered.
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		if [ ${#specified_paths[@]} -gt 0 ]; then
			for invalid_path in "${specified_paths[@]}"; do
				git_deps_log_error "[$invalid_path] is not a registered dependency"
			done
			return 1
		fi
		return 0
	fi

	# Count total dependencies and validate specified paths
	for LINE in $(git_deps_read); do
		((TOTAL++))
	done

	if [ $TOTAL -eq 0 ]; then
		return 0
	fi

	# If specific paths were provided, validate them
	if [ ${#specified_paths[@]} -gt 0 ]; then
		# Get list of all registered dependency paths
		local registered_paths=()
		for LINE in $(git_deps_read); do
			set -a FIELDS
			IFS='|' read -ra FIELDS <<<"$LINE"
			if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then
				continue
			fi
			registered_paths+=("${FIELDS[0]}")
		done

		# Check each specified path
		for specified_path in "${specified_paths[@]}"; do
			local found=false
			for registered_path in "${registered_paths[@]}"; do
				if [ "$specified_path" = "$registered_path" ]; then
					valid_paths+=("$specified_path")
					found=true
					break
				fi
			done
			if [ "$found" = false ]; then
				invalid_paths+=("$specified_path")
			fi
		done

		# Error if any invalid paths were specified
		if [ ${#invalid_paths[@]} -gt 0 ]; then
			for invalid_path in "${invalid_paths[@]}"; do
				git_deps_log_error "[$invalid_path] is not a registered dependency"
			done
			return 1
		fi
	fi

	# Phase 1: Parallel fetch for all dependencies (unless offline)
	# This significantly speeds up status checks by parallelizing network I/O
	if [ "$GIT_DEPS_OFFLINE" != "true" ] && [ "$GIT_DEPS_PARALLEL" -gt 1 ] 2>/dev/null; then
		local fetch_pids=()
		local fetch_paths=()
		local running=0

		for LINE in $(git_deps_read); do
			IFS='|' read -ra FIELDS <<<"$LINE"
			if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then
				continue
			fi

			local path="${FIELDS[0]}"

			# Skip if specific paths were requested and this isn't one of them
			if [ ${#valid_paths[@]} -gt 0 ]; then
				local should_fetch=false
				for valid_path in "${valid_paths[@]}"; do
					if [ "$path" = "$valid_path" ]; then
						should_fetch=true
						break
					fi
				done
				if [ "$should_fetch" = false ]; then
					continue
				fi
			fi

			# Skip if not a git repo
			if [ ! -e "$path/.git" ]; then
				continue
			fi

			# Wait if we've hit the parallel limit
			while [ $running -ge "$GIT_DEPS_PARALLEL" ]; do
				# Wait for any job to finish
				for i in "${!fetch_pids[@]}"; do
					if ! kill -0 "${fetch_pids[$i]}" 2>/dev/null; then
						unset "fetch_pids[$i]"
						((running--))
						break
					fi
				done
				# Brief sleep to avoid busy-waiting
				sleep 0.1
			done

			# Start background fetch
			(git_deps_op_fetch "$path" "" "true" >/dev/null 2>&1) &
			fetch_pids+=($!)
			fetch_paths+=("$path")
			((running++))
		done

		# Wait for all remaining fetches to complete
		for pid in "${fetch_pids[@]}"; do
			wait "$pid" 2>/dev/null || true
		done
	fi

	for LINE in $(git_deps_read); do
		set -a FIELDS
		IFS='|' read -ra FIELDS <<<"$LINE"
		line_num=$((line_num + 1))

		if [[ "${FIELDS[0]}" =~ ^- ]]; then
			git_deps_log_warning "Parsing syntax errors in configuration"
			continue
		fi

		if [ ${#FIELDS[@]} -lt 3 ]; then
			git_deps_log_warning "Parsing syntax errors in configuration"
			continue
		fi

		local path="${FIELDS[0]}"
		local repo="${FIELDS[1]}"
		local branch="${FIELDS[2]}"
		local commit="${FIELDS[3]:-}"

		# Skip if specific paths were requested and this isn't one of them
		if [ ${#valid_paths[@]} -gt 0 ]; then
			local should_process=false
			for valid_path in "${valid_paths[@]}"; do
				if [ "$path" = "$valid_path" ]; then
					should_process=true
					break
				fi
			done
			if [ "$should_process" = false ]; then
				continue
			fi
		fi

		if [[ "$seen_paths" == *"$path"* ]]; then
			git_deps_log_warning "Duplicate dependency path: $path"
		else
			seen_paths="$seen_paths $path"
		fi

		if [ -e "$path/.git" ]; then
			if ! git -C "$path" show-ref --verify --quiet "refs/heads/$branch"; then
				git_deps_log_warning "Branch '$branch' does not exist in $path"
			fi
			if [ -n "$commit" ] && ! git -C "$path" cat-file -e "$commit" 2>/dev/null; then
				git_deps_log_warning "Commit '$commit' does not exist in $path"
			fi
		fi

		# Get current local branch for display
		local display_branch="$branch"
		if [ -e "$path/.git" ]; then
			local current_branch="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$branch")"
			local current_commit_for_branch="$(git_deps_op_commit_id "$path" 2>/dev/null || echo "unknown")"

			# Handle detached HEAD state - try to find the branch containing current commit
			if [ "$current_branch" = "HEAD" ] && [ "$current_commit_for_branch" != "unknown" ]; then
				# Use git name-rev first - it's O(1) and much faster than branch --contains
				local name_rev="$(git -C "$path" name-rev --name-only "$current_commit_for_branch" 2>/dev/null | head -1)"
				if [ -n "$name_rev" ] && [ "$name_rev" != "undefined" ]; then
					# Extract branch name from name-rev output (e.g., "main~2" -> "main", "remotes/origin/main" -> "main")
					name_rev="${name_rev%%~*}"             # Remove ~N suffix
					name_rev="${name_rev%%^*}"             # Remove ^N suffix
					name_rev="${name_rev#remotes/origin/}" # Remove remote prefix
					name_rev="${name_rev#remotes/}"
					display_branch="$name_rev"
				else
					# Fallback: just show the short commit hash (skip expensive branch --contains)
					display_branch="${current_commit_for_branch:0:8}"
				fi
			else
				display_branch="$current_branch"
			fi
		fi

		# Get commit IDs and dates
		local dep_commit="${commit}"
		local local_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "unknown")
		local remote_commit=""

		# Single fetch per dependency to avoid redundant operations
		local operation_logs=""
		if [ -e "$path/.git" ]; then
			operation_logs="Checking ${path}…"
			local fetch_output
			if fetch_output=$(git_deps_op_fetch "$path" "" "true"); then
				local temp_commit
				temp_commit=$(git -C "$path" rev-parse "origin/$branch" 2>/dev/null)
				# Validate it's a valid commit hash (40-char hex), not a symbolic ref or error
				if [[ "$temp_commit" =~ ^[0-9a-f]{40}$ ]]; then
					remote_commit="$temp_commit"
				else
					remote_commit="unknown"
				fi
				operation_logs="$operation_logs|$fetch_output|$path updated"
			else
				remote_commit="unknown"
				operation_logs="$operation_logs|$fetch_output"
			fi
		fi

		# Get commit dates
		local dep_date=""
		local local_date=""
		local remote_date=""

		if [ -n "$dep_commit" ] && [ "$dep_commit" != "unknown" ] && [ -e "$path/.git" ]; then
			dep_date=$(git_deps_op_commit_date "$path" "$dep_commit" 2>/dev/null || echo "")
		elif [ "$local_commit" != "unknown" ] && [ -e "$path/.git" ]; then
			dep_date=$(git_deps_op_commit_date "$path" "$local_commit" 2>/dev/null || echo "")
		fi

		if [ "$local_commit" != "unknown" ] && [ -e "$path/.git" ]; then
			local_date=$(git_deps_op_commit_date "$path" "$local_commit" 2>/dev/null || echo "")
		fi

		if [ "$remote_commit" != "unknown" ] && [ -e "$path/.git" ]; then
			# For remote date, we need to fetch the commit first if it doesn't exist locally
			if git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
				remote_date=$(git_deps_op_commit_date "$path" "$remote_commit" 2>/dev/null || echo "")
			else
				# Try to fetch and get the date
				local date_fetch_output
				if date_fetch_output=$(git_deps_op_fetch "$path" "origin" "true"); then
					remote_date=$(git_deps_op_commit_date "$path" "$remote_commit" 2>/dev/null || echo "")
					operation_logs="$operation_logs|Fetching commit info for date calculation...|$date_fetch_output"
				else
					operation_logs="$operation_logs|Fetching commit info for date calculation...|$date_fetch_output"
				fi
			fi
		fi

		# Calculate status for each component (pass fetched remote_commit to avoid redundant fetches)
		local dep_status=$(git_deps_status_dep "$path" "$repo" "$branch" "$commit" "$remote_commit")
		local local_status=$(git_deps_status_local "$path" "$repo" "$branch" "$commit" "$remote_commit")
		local remote_status=$(git_deps_status_remote "$repo" "$branch" "$commit" "$path" "$remote_commit")

		# Calculate ahead count for local (commits not in remote)
		local local_ahead=""
		if [ -e "$path/.git" ] && [ "$local_commit" != "unknown" ] && [ "$remote_commit" != "unknown" ]; then
			local ahead_count=0
			if git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
				ahead_count=$(git -C "$path" rev-list --count "$remote_commit..$local_commit" 2>/dev/null || echo "0")
			else
				# Remote commit not available locally - count all local commits from branch point
				ahead_count=$(git -C "$path" rev-list --count HEAD 2>/dev/null || echo "0")
			fi
			if [ "$ahead_count" -gt 0 ]; then
				local_ahead=" (+$ahead_count)"
			fi
		fi

		# Calculate ahead count for remote (commits not in local)
		local remote_ahead=""
		if [ "$remote_commit" != "unknown" ] && [ -e "$path/.git" ] && [ "$local_commit" != "unknown" ]; then
			local remote_ahead_count=0
			if git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
				remote_ahead_count=$(git -C "$path" rev-list --count "$local_commit..$remote_commit" 2>/dev/null || echo "0")
			else
				# Estimate - remote has commits we don't have
				remote_ahead_count=1
			fi
			if [ "$remote_ahead_count" -gt 0 ]; then
				remote_ahead=" (+$remote_ahead_count)"
			fi
		fi

		local DEP_RESULT="ok"
		if [[ "$dep_status" != *"SYNCED"* || "$local_status" != *"SYNCED"* || "$remote_status" != *"SYNCED"* ]]; then
			DEP_RESULT="warn"
		fi

		git_deps_log_rollup "$path" "$DEP_RESULT" "dep=${dep_status} [${display_branch}] ${dep_commit:-$local_commit} ${dep_date} | local=${local_status} [${display_branch}] ${local_commit:-unknown} ${local_date}${local_ahead} | remote=${remote_status} [${display_branch}] ${remote_commit:-unknown} ${remote_date}${remote_ahead}"
	done
}

function git-deps-state {
	# Parse arguments for help flag
	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help)
			echo "Usage: git-deps state"
			echo ""
			echo "Shows the current state of all dependencies"
			echo "Outputs: PATH URL BRANCH COMMIT for each dependency"
			echo ""
			echo "Options:"
			echo "  -h, --help         Show this help message"
			return 0
			;;
		*)
			shift
			;;
		esac
	done

	IFS=$'\n'
	local TOTAL=0

	# state is a read-only request: a missing configuration outputs nothing.
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		return 0
	fi

	# Count dependencies silently for state command
	for LINE in $(git_deps_read); do
		((TOTAL++))
	done

	if [ $TOTAL -eq 0 ]; then
		return 0
	fi

	for LINE in $(git_deps_read); do
		set -a FIELDS
		IFS='|' read -ra FIELDS <<<"$LINE"
		if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then continue; fi
		local path="${FIELDS[0]}"
		local repo="${FIELDS[1]}"

		# Get current local branch and commit
		local current_branch="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
		local current_commit="$(git_deps_op_commit_id "$path" 2>/dev/null || echo "unknown")"

		# Handle detached HEAD state - try to find the branch containing current commit
		if [ "$current_branch" = "HEAD" ] && [ "$current_commit" != "unknown" ]; then
			# Try to find local branch containing current commit
			local branch_containing_commit="$(git -C "$path" branch --contains "$current_commit" 2>/dev/null | grep -v '^*' | head -1 | sed 's/^[* ]*//')"
			if [ -n "$branch_containing_commit" ]; then
				current_branch="$branch_containing_commit"
			else
				# Try remote branches
				local remote_branch_containing_commit="$(git -C "$path" branch -r --contains "$current_commit" 2>/dev/null | head -1 | sed 's|^origin/||')"
				if [ -n "$remote_branch_containing_commit" ]; then
					current_branch="$remote_branch_containing_commit"
				else
					# If no branch found, show commit hash as branch
					current_branch="${current_commit:0:8}"
				fi
			fi
		fi

		echo "$path $repo $current_branch $current_commit"
	done
}

function git-deps-save {
	local safe="false"

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-s | --safe)
			safe="true"
			shift
			;;
		-h | --help)
			echo "Usage: git-deps save [OPTIONS]"
			echo ""
			echo "Saves the current dependency state to .gitdeps file"
			echo "Records current branch and commit for each dependency."
			echo ""
			echo "Options:"
			echo "  -s, --safe         Save the nearest cached remote ancestor"
			echo "  -h, --help         Show this help message"
			return 0
			;;
		*)
			git_deps_log_error "Unknown save option: $1"
			return 1
			;;
		esac
	done

	# A missing configuration leaves nothing to save; report once and fail.
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		git_deps_log_error "[$GIT_DEPS_FILE] could not be found"
		return 1
	fi

	local state="$(git-deps-state)"
	local deps_file="$(git_deps_path 2>/dev/null || echo "$GIT_DEPS_FILE")"
	local count=0

	# Count dependencies
	if [ -n "$state" ]; then
		count=$(echo "$state" | wc -l)
	fi

	if [ "$count" -eq 0 ]; then
		return 0
	fi

	# Validate or downgrade commits before constructing any file changes.
	local save_state=""
	local unsafe_paths=()
	local safe_errors=0
	while IFS= read -r line; do
		[ -z "$line" ] && continue
		local path url branch commit
		read -r path url branch commit <<<"$line"
		if git_deps_op_commit_on_remote "$path" "$commit"; then
			save_state+="$line"$'\n'
		elif [ "$safe" = "true" ]; then
			local safe_commit
			if safe_commit=$(git_deps_op_remote_ancestor "$path" "$commit"); then
				save_state+="$path $url $branch $safe_commit"$'\n'
			else
				local reason="no cached remote ancestor for $(git_deps_op_commit_info "$path" "$commit")"
				if [ ! -e "$path/.git" ]; then
					reason="not a checked-out git repository"
				fi
				git_deps_log_rollup "$path" "err" "$reason"
				((safe_errors++))
			fi
		else
			local reason="commit $(git_deps_op_commit_info "$path" "$commit") is not on any cached remote ref"
			if [ ! -e "$path/.git" ]; then
				reason="not a checked-out git repository"
			elif ! git_deps_op_has_remote_refs "$path"; then
				reason="repository has no cached remote refs"
			fi
			git_deps_log_rollup "$path" "err" "$reason"
			unsafe_paths+=("$path")
		fi
	done <<<"$state"

	if [ ${#unsafe_paths[@]} -gt 0 ]; then
		git_deps_log_error "Cannot save: ${#unsafe_paths[@]} dependency(ies) not reachable from a cached remote ref"
		git_deps_log_message "Push dependency commits first, or use 'git-deps save --safe'"
		return 1
	fi
	if [ "$safe_errors" -gt 0 ]; then
		git_deps_log_error "Could not determine safe commits for $safe_errors dependencies"
		return 1
	fi
	state="${save_state%$'\n'}"

	# Build maps of existing entries (without comments) for change detection
	declare -A existing_entries
	if [ -e "$deps_file" ]; then
		while IFS=$'\t ' read -r e_path e_url e_branch e_commit _rest; do
			[ -z "$e_path" ] && continue
			[[ "$e_path" =~ ^# ]] && continue
			existing_entries["$e_path"]="${e_url} ${e_branch} ${e_commit}"
		done < <(grep -v '^[[:space:]]*#' "$deps_file" 2>/dev/null || true)
	fi

	local new_content=""
	local added=0
	local updated=0
	local unchanged=0
	local change_paths=() change_messages=()

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		local path url branch commit
		# state output format: path repo branch commit
		read -r path url branch commit <<<"$line"
		local new_line_payload="${url} ${branch} ${commit}"
		local operation_logs=""

		if [ -z "${existing_entries[$path]+x}" ]; then
			operation_logs="Added entry (${branch} $(git_deps_op_commit_info "$path" "$commit"))"
			((added++))
		elif [ "${existing_entries[$path]}" = "$new_line_payload" ]; then
			((unchanged++))
		else
			# Compare old vs new commit/branch
			local old_val="${existing_entries[$path]}"
			local old_url old_branch old_commit
			IFS=' ' read -r old_url old_branch old_commit <<<"$old_val"
			if [ -z "$old_commit" ]; then
				old_commit=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "unknown")
			fi
			operation_logs="Updated entry (${branch} $(git_deps_op_commit_info "$path" "$old_commit") → $(git_deps_op_commit_info "$path" "$commit"))"
			((updated++))
		fi

		# Append to new file content
		new_content+="$path $url $branch $commit"$'\n'

		if [ -n "$operation_logs" ]; then
			change_paths+=("$path")
			change_messages+=("$operation_logs")
		fi
	done <<<"$state"

	if [ "$added" -eq 0 ] && [ "$updated" -eq 0 ]; then
		return 0
	fi

	if git_deps_write "${new_content%$'\n'}"; then
		local index
		for index in "${!change_paths[@]}"; do
			git_deps_log_rollup "${change_paths[$index]}" ok "${change_messages[$index]}"
		done
		return 0
	else
		git_deps_log_error "Failed to save dependency state"
		return 1
	fi
}

function git-deps-push {
	git_deps_log_error "Push command not yet implemented"
	git_deps_log_message "Use 'git-deps pull' to sync dependencies, or manually push changes in dependency directories"
	return 1
}

function git-deps-update {
	local pinned="false"
	local force="false"
	local at=""
	local at_mode="false"
	local specified_paths=()
	local invalid_paths=()
	local valid_paths=()

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help)
			echo "Usage: git-deps update [OPTIONS] [PATH...]"
			echo ""
			echo "Updates dependencies to latest from remote"
			echo ""
			echo "Arguments:"
			echo "  PATH               One or more dependency paths to update (optional, updates all if omitted)"
			echo ""
			echo "Options:"
			echo "  --pinned           Checkout to pinned commit instead of fast-forwarding"
			echo "  -t, --at [DATE]    Checkout latest commit at or before DATE (default: current HEAD date)"
			echo "  -f, --force        Force update even with uncommitted/unpushed changes"
			echo "  -h, --help         Show this help message"
			return 0
			;;
		--pinned)
			pinned="true"
			shift
			;;
		-t | --at)
			at_mode="true"
			if [ $# -ge 2 ] && [[ "$2" != -* ]] && ! git_deps_has "$2"; then
				at="$2"
				shift 2
			else
				shift
			fi
			;;
		-f | --force)
			force="true"
			shift
			;;
		-*)
			git_deps_log_error "Unknown option: $1"
			return 1
			;;
		*)
			specified_paths+=("$1")
			shift
			;;
		esac
	done

	if [ "$pinned" = "true" ] && [ "$at_mode" = "true" ]; then
		git_deps_log_error "--pinned and --at cannot be used together"
		return 1
	fi
	if [ "$at_mode" = "true" ] && [ -z "$at" ]; then
		# Infer from HEAD's committer date, in the same local format used elsewhere.
		at=$(git show -s --date=format-local:'%Y-%m-%d %H:%M:%S' --format=%cd HEAD 2>/dev/null) || at=""
	fi
	if [ "$at_mode" = "true" ] && [ -z "$at" ]; then
		git_deps_log_error "Cannot infer DATETIME from the current HEAD commit"
		return 1
	fi

	local old_ifs="$IFS"
	IFS=$'\n'
	local TOTAL=0
	local ERRORS=0
	local WARNINGS=0

	# A missing configuration cannot be updated; report once and fail.
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		git_deps_log_error "[$GIT_DEPS_FILE] could not be found"
		return 1
	fi

	# If specific paths were provided, validate them against registered dependencies
	if [ ${#specified_paths[@]} -gt 0 ]; then
		local registered_paths=()
		for LINE in $(git_deps_read); do
			IFS='|' read -ra FIELDS <<<"$LINE"
			if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then
				continue
			fi
			registered_paths+=("${FIELDS[0]}")
		done

		for specified_path in "${specified_paths[@]}"; do
			local found="false"
			for registered_path in "${registered_paths[@]}"; do
				if [ "$specified_path" = "$registered_path" ]; then
					valid_paths+=("$specified_path")
					found="true"
					break
				fi
			done
			if [ "$found" = "false" ]; then
				invalid_paths+=("$specified_path")
			fi
		done

		if [ ${#invalid_paths[@]} -gt 0 ]; then
			for invalid_path in "${invalid_paths[@]}"; do
				git_deps_log_error "[$invalid_path] is not a registered dependency"
			done
			return 1
		fi

		TOTAL=${#valid_paths[@]}
	else
		# Count total dependencies
		for LINE in $(git_deps_read); do
			((TOTAL++))
		done
	fi

	if [ $TOTAL -eq 0 ]; then
		return 0
	fi

	for LINE in $(git_deps_read); do
		set -a FIELDS
		local temp_ifs="$IFS"
		IFS='|' read -ra FIELDS <<<"$LINE"
		IFS="$temp_ifs"
		if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then continue; fi
		local path="${FIELDS[0]}"

		# Skip non-selected dependencies when specific paths were requested
		if [ ${#valid_paths[@]} -gt 0 ]; then
			local include="false"
			for valid_path in "${valid_paths[@]}"; do
				if [ "$path" = "$valid_path" ]; then
					include="true"
					break
				fi
			done
			if [ "$include" = "false" ]; then
				continue
			fi
		fi

		local update_output
		if [ "$at_mode" = "true" ]; then
			update_output=$(git_deps_update "$pinned" "$force" "${FIELDS[0]}" "${FIELDS[1]}" "${FIELDS[2]}" "${FIELDS[3]:-}" "$at")
		else
			update_output=$(git_deps_update "$pinned" "$force" "${FIELDS[@]}")
		fi
		local update_kind="${update_output%%-*}"
		local update_reason="${update_output#*-}"
		if [ "$update_kind" = "err" ]; then
			case "$update_reason" in
			uncommitted | unpushed | no-remote-branch | diverged)
				((WARNINGS++))
				;;
			*)
				((ERRORS++))
				;;
			esac
		fi
	done

	if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
		return 0
	elif [ $ERRORS -eq 0 ]; then
		git_deps_log_warning "Update completed with warnings=$WARNINGS (total=$TOTAL)"
		return 0
	else
		git_deps_log_error "Update failed: errors=$ERRORS warnings=$WARNINGS (total=$TOTAL)"
		return 1
	fi
}

function git-deps-add {
	local force="false"
	local repo=""
	local path=""
	local branch=""
	local commit=""

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help)
			echo "Usage: git-deps add [OPTIONS] REPO_PATH REPO_URL [BRANCH] [COMMIT]"
			echo ""
			echo "Adds a new dependency to the project"
			echo ""
			echo "Arguments:"
			echo "  REPO_PATH          Local path for the dependency"
			echo "  REPO_URL           Repository URL to clone"
			echo "  BRANCH             Branch to track (default: main)"
			echo "  COMMIT             Specific commit to pin (optional)"
			echo ""
			echo "Options:"
			echo "  -f, --force        Force overwrite if path exists"
			echo "  -h, --help         Show this help message"
			return 0
			;;
		-f | --force)
			force="true"
			shift
			;;
		*)
			if [ -z "$path" ]; then
				path="$1"
			elif [ -z "$repo" ]; then
				repo="$1"
			elif [ -z "$branch" ]; then
				branch="$1"
			elif [ -z "$commit" ]; then
				commit="$1"
			fi
			shift
			;;
		esac
	done

	# Validate required arguments
	if [ -z "$path" ] || [ -z "$repo" ]; then
		git_deps_log_error "Usage: git-deps add [OPTIONS] REPO_PATH REPO_URL [BRANCH] [COMMIT]"
		git_deps_log_message "Use 'git-deps add --help' for more information"
		return 1
	fi

	# Call internal function and capture structured output
	local add_output
	add_output=$(git_deps_add "$repo" "$path" "$branch" "$commit" "$force")
	local add_exit=$?

	# Parse structured output
	local status=""
	local result_path=""
	local result_repo=""
	local result_branch=""
	local result_commit=""
	local operation_logs=""

	IFS='|' read -r status result_path result_repo result_branch result_commit operation_logs <<<"$add_output"

	# Determine result status
	local DEP_RESULT="ok"
	if [ "$add_exit" -ne 0 ] || [ "$status" = "err" ]; then
		DEP_RESULT="err"
	fi

	local summary="$operation_logs"
	if [ "$DEP_RESULT" = "ok" ] && [ -n "$result_commit" ]; then
		local commit_info
		commit_info=$(git_deps_op_commit_info "$result_path" "$result_commit")
		summary="Added from $result_repo on $result_branch at $commit_info"
	fi

	git_deps_log_rollup "$path" "$DEP_RESULT" "${summary//|/; }"

	if [ "$DEP_RESULT" = "err" ]; then
		return 1
	else
		return 0
	fi
}

function git-deps-remove {
	local force="false"
	local paths=()

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help)
			echo "Usage: git-deps remove [OPTIONS] PATHS..."
			echo ""
			echo "Removes one or more dependencies from .gitdeps"
			echo ""
			echo "Options:"
			echo "  -f, --force        Accepted for compatibility (no effect)"
			echo "  -h, --help         Show this help message"
			echo ""
			echo "Arguments:"
			echo "  PATHS             One or more dependency paths to remove"
			return 0
			;;
		-f | --force)
			force="true"
			shift
			;;
		-*)
			git_deps_log_error "Unknown option: $1"
			git_deps_log_message "Usage: git-deps remove [OPTIONS] PATHS..."
			return 1
			;;
		*)
			paths+=("$1")
			shift
			;;
		esac
	done

	if [ ${#paths[@]} -eq 0 ]; then
		git_deps_log_error "Usage: git-deps remove [OPTIONS] PATHS..."
		git_deps_log_message "Use 'git-deps remove --help' for more information"
		return 1
	fi

	local ERRORS=0
	local TOTAL=${#paths[@]}

	for path in "${paths[@]}"; do
		local remove_output
		remove_output=$(git_deps_remove "$path")
		local remove_exit=$?

		local status=""
		local result_path=""
		local operation_logs=""
		IFS='|' read -r status result_path operation_logs <<<"$remove_output"

		local DEP_RESULT="ok"
		if [ "$remove_exit" -ne 0 ] || [ "$status" = "err" ]; then
			DEP_RESULT="err"
			((ERRORS++))
		fi

		git_deps_log_rollup "$path" "$DEP_RESULT" "${operation_logs//|/; }"
	done

	if [ $ERRORS -eq 0 ]; then
		return 0
	else
		git_deps_log_error "Failed to remove $ERRORS out of $TOTAL dependencies"
		return 1
	fi
}

# Function: git-deps-fix
# Repairs the .gitdeps file by normalising entries: strips extra fields,
# defaults a missing branch, drops unusable lines and removes duplicates.
function git-deps-fix {
	local dry_run="false"
	local default_branch="main"

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-n | --dry-run)
			dry_run="true"
			shift
			;;
		-b | --branch)
			if [ -z "${2:-}" ]; then
				git_deps_log_error "Missing value for $1"
				return 1
			fi
			default_branch="$2"
			shift 2
			;;
		--branch=*)
			default_branch="${1#--branch=}"
			shift
			;;
		-h | --help)
			echo "Usage: git-deps fix [OPTIONS]"
			echo ""
			echo "Repairs the .gitdeps file in place"
			echo ""
			echo "Fixes applied:"
			echo "  - strips fields beyond path, url, branch and commit"
			echo "  - drops lines that have neither a path and a url"
			echo "  - defaults a missing branch to '$default_branch'"
			echo "  - removes duplicate dependency paths (keeps the first)"
			echo "  - normalises field separators to single spaces"
			echo "  - ensures the file ends with a single newline"
			echo ""
			echo "Options:"
			echo "  -n, --dry-run      Print the repaired file without writing it"
			echo "  -b, --branch NAME  Branch used for entries missing one (default: main)"
			echo "  -h, --help         Show this help message"
			return 0
			;;
		-*)
			git_deps_log_error "Unknown option: $1"
			git_deps_log_message "Usage: git-deps fix [OPTIONS]"
			return 1
			;;
		*)
			git_deps_log_error "Unexpected argument: $1"
			git_deps_log_message "Usage: git-deps fix [OPTIONS]"
			return 1
			;;
		esac
	done

	if [ ! -e "$GIT_DEPS_FILE" ]; then
		git_deps_log_error "[$GIT_DEPS_FILE] could not be found"
		return 1
	fi

	local line_num=0
	local kept=0
	local dropped=0
	local repaired=0
	local duplicates=0
	local output=""
	declare -A seen_paths=()

	while IFS= read -r line || [ -n "$line" ]; do
		((line_num++)) || true

		# Preserve comment lines as-is (trailing whitespace trimmed)
		if [[ "$line" =~ ^[[:space:]]*# ]]; then
			output+="${line%"${line##*[![:space:]]}"}"$'\n'
			continue
		fi

		# Drop blank lines
		if [ -z "${line//[[:space:]]/}" ]; then
			continue
		fi

		local -a fields=()
		IFS=$' \t' read -ra fields <<<"$line"
		local count=${#fields[@]}

		# A single field cannot be repaired into a usable dependency
		if [ "$count" -lt 2 ]; then
			git_deps_log_warning "Line $line_num: dropping unusable entry '${fields[0]}' (need at least a path and a url)"
			((dropped++)) || true
			continue
		fi

		local path="${fields[0]}"
		local url="${fields[1]}"
		local branch="${fields[2]:-}"
		local commit="${fields[3]:-}"

		if [ "$count" -eq 2 ]; then
			branch="$default_branch"
			git_deps_log_warning "Line $line_num: missing branch for '$path', defaulting to '$default_branch'"
			((repaired++)) || true
		elif [ "$count" -gt 4 ]; then
			git_deps_log_warning "Line $line_num: stripping $((count - 4)) extra field(s) from '$path'"
			((repaired++)) || true
		fi

		if [ -n "${seen_paths[$path]+x}" ]; then
			git_deps_log_warning "Line $line_num: duplicate path '$path' removed"
			((duplicates++)) || true
			continue
		fi
		seen_paths["$path"]=1

		# Rebuild the entry with canonical single-space separators
		local entry="$path $url $branch"
		if [ -n "$commit" ]; then
			entry="$entry $commit"
		fi
		output+="$entry"$'\n'
		((kept++)) || true
	done <"$GIT_DEPS_FILE"

	# Keep-trailing-newline-safe copy of the current content for comparison
	local original
	original="$(cat "$GIT_DEPS_FILE" && printf x)"
	original="${original%x}"

	local summary="kept=$kept dropped=$dropped repaired=$repaired duplicates=$duplicates"

	if [ "$output" = "$original" ]; then
		if [ "$dry_run" = "true" ]; then
			printf '%s' "$output"
		fi
		return 0
	fi

	if [ "$dry_run" = "true" ]; then
		printf '%s' "$output"
		git_deps_log_message "Dry run: no changes written ($summary)"
		return 0
	fi

	local tmpfile
	tmpfile=$(mktemp "$GIT_DEPS_FILE".XXX)
	printf '%s' "$output" >"$tmpfile"
	cat "$tmpfile" >"$GIT_DEPS_FILE"
	unlink "$tmpfile"

	git_deps_log_rollup "$GIT_DEPS_FILE" ok "Repaired ($summary)"
	return 0
}

function git-deps-checkout {
	local force="false"
	local missing="false"
	local specified_paths=()
	local invalid_paths=()
	local valid_paths=()

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help)
			echo "Usage: git-deps checkout [OPTIONS] [PATH...]"
			echo ""
			echo "Checks out dependency to saved state (no network required)"
			echo ""
			echo "Arguments:"
			echo "  PATH               One or more dependency paths to checkout (optional, checks out all if omitted)"
			echo ""
			echo "Options:"
			echo "  -f, --force        Bypass the unpushed-commit check (never discards uncommitted changes)"
			echo "  -m, --missing      Only clone dependencies that are absent; leave existing checkouts untouched"
			echo "  -h, --help         Show this help message"
			return 0
			;;
		-f | --force)
			force="true"
			shift
			;;
		-m | --missing)
			missing="true"
			shift
			;;
		-*)
			git_deps_log_error "Unknown option: $1"
			return 1
			;;
		*)
			specified_paths+=("$1")
			shift
			;;
		esac
	done

	local old_ifs="$IFS"
	IFS=$'\n'
	local ERRORS=0
	local WARNINGS=0
	local TOTAL=0

	# A missing configuration leaves nothing to check out; report once and fail.
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		git_deps_log_error "[$GIT_DEPS_FILE] could not be found"
		return 1
	fi

	# If specific paths were provided, validate them against registered dependencies
	if [ ${#specified_paths[@]} -gt 0 ]; then
		local registered_paths=()
		for LINE in $(git_deps_read); do
			IFS='|' read -ra FIELDS <<<"$LINE"
			if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then
				continue
			fi
			registered_paths+=("${FIELDS[0]}")
		done

		for specified_path in "${specified_paths[@]}"; do
			local found="false"
			for registered_path in "${registered_paths[@]}"; do
				if [ "$specified_path" = "$registered_path" ]; then
					valid_paths+=("$specified_path")
					found="true"
					break
				fi
			done
			if [ "$found" = "false" ]; then
				invalid_paths+=("$specified_path")
			fi
		done

		if [ ${#invalid_paths[@]} -gt 0 ]; then
			for invalid_path in "${invalid_paths[@]}"; do
				git_deps_log_error "[$invalid_path] is not a registered dependency"
			done
			return 1
		fi

		TOTAL=${#valid_paths[@]}
	else
		# Count total dependencies
		for LINE in $(git_deps_read); do
			((TOTAL++))
		done
	fi

	if [ $TOTAL -eq 0 ]; then
		return 0
	fi

	for LINE in $(git_deps_read); do
		IFS='|' read -ra FIELDS <<<"$LINE"
		if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then continue; fi
		local path="${FIELDS[0]}"
		local repo="${FIELDS[1]}"
		local branch="${FIELDS[2]:-main}"
		local commit="${FIELDS[3]:-}"

		# Skip non-selected dependencies when specific paths were requested
		if [ ${#valid_paths[@]} -gt 0 ]; then
			local include="false"
			for valid_path in "${valid_paths[@]}"; do
				if [ "$path" = "$valid_path" ]; then
					include="true"
					break
				fi
			done
			if [ "$include" = "false" ]; then
				continue
			fi
		fi

		local operation_logs=""
		local DEP_RESULT="ok"

		# With --missing, existing checkouts are never touched: they may hold
		# local work, a detached revision or a symlink to a development tree.
		# A dangling symlink still counts as present so we never clone over it.
		if [ "$missing" = "true" ] && { [ -e "$path" ] || [ -L "$path" ]; }; then
			continue
		fi

		# Clone if path doesn't exist (this is the only network operation allowed)
		if [ ! -e "$path" ]; then
			operation_logs="Cloning $repo..."
			local clone_output
			if ! clone_output=$(git_deps_op_clone "$repo" "$path" true); then
				operation_logs="$clone_output"
				((ERRORS++))
				DEP_RESULT="err"
			else
				operation_logs="Cloned from $repo at $(git_deps_op_commit_info "$path")"
			fi
		fi

		# Checkout to specified revision (local-only, no network)
		if [ -e "$path/.git" ]; then
			local target_rev="${commit:-$branch}"
			local local_changes
			local_changes=$(git_deps_op_localchanges "$path")
			local current_branch
			local current_commit
			current_branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
			current_commit=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "")
			local need_checkout="true"

			# Only checkout when the current state differs from the desired state.
			if [ -n "$commit" ]; then
				if [ -n "$current_commit" ] && [ "$current_commit" = "$commit" ]; then
					need_checkout="false"
				fi
			else
				if [ -n "$current_branch" ] && [ "$current_branch" = "$target_rev" ]; then
					need_checkout="false"
				fi
			fi

			# SAFETY: never check out over uncommitted changes, even with
			# --force, as that could discard local work. Unpushed commits are
			# recoverable and may be bypassed with --force.
			local has_unpushed="false"
			if git_deps_op_has_unpushed_commits "$path" "$branch"; then
				has_unpushed="true"
			fi

			local blocked="false"
			if [ "$need_checkout" = "false" ] && [ -n "$local_changes" ]; then
				operation_logs="$operation_logs|${ORANGE}Warning: has uncommitted changes, but already at the requested state${RESET}"
				DEP_RESULT="warn"
			elif [ -n "$local_changes" ]; then
				operation_logs="$operation_logs|${ORANGE}Cannot checkout: has uncommitted changes${RESET}"
				operation_logs="$operation_logs|Tip: commit or stash changes: git -C '$path' status"
				blocked="true"
				((WARNINGS++))
				DEP_RESULT="warn"
			elif [ "$has_unpushed" = "true" ] && [ "$force" != "true" ]; then
				operation_logs="$operation_logs|${ORANGE}Cannot checkout: has unpushed commits${RESET}"
				operation_logs="$operation_logs|Tip: push changes first: git -C '$path' push"
				blocked="true"
				((WARNINGS++))
				DEP_RESULT="warn"
			elif [ "$has_unpushed" = "true" ]; then
				operation_logs="$operation_logs|${ORANGE}Warning: has unpushed commits (proceeding with --force)${RESET}"
			fi

			if [ "$blocked" != "true" ]; then
				# Check if pinned commit exists locally
				local pinned_missing="false"
				if [ -n "$commit" ]; then
					if ! git -C "$path" cat-file -e "$commit^{commit}" >/dev/null 2>&1; then
						pinned_missing="true"
						operation_logs="$operation_logs|${RED}Pinned commit $commit (date unavailable) not found locally${RESET}"
						operation_logs="$operation_logs|Tip: run 'git-deps update --pinned' to fetch the pinned commit"
						((ERRORS++))
						DEP_RESULT="err"
					fi
				fi

				# Only checkout when the current state differs from the desired state.
				if [ "$pinned_missing" != "true" ]; then
					local target_info
					target_info=$(git_deps_op_commit_info "$path" "$target_rev")
					if [ "$need_checkout" = "true" ]; then
						# Confirm before switching branches
						if [ "$current_branch" != "$branch" ] && [ "$current_branch" != "HEAD" ] && [ "$current_branch" != "" ]; then
							if [ "$force" != "true" ]; then
								if ! git_deps_confirm "Switch from branch '$current_branch' to '$branch'?" "$force"; then
									operation_logs="$operation_logs|Checkout cancelled by user"
									DEP_RESULT="warn"
									continue
								fi
							fi
						fi

						if ! git_deps_op_checkout "$path" "$target_rev"; then
							# Show the actual git error
							local error_msg=""
							error_msg=$(echo "$GIT_CHECKOUT_ERROR" | grep -E "^error:|^fatal:" | head -1 | sed -E 's/^(error|fatal): //')
							if [ -z "$error_msg" ]; then
								error_msg=$(echo "$GIT_CHECKOUT_ERROR" | head -1)
							fi
							operation_logs="$operation_logs|${RED}Failed to checkout $target_rev: $error_msg${RESET}"
							((ERRORS++))
							DEP_RESULT="err"
							operation_logs="$operation_logs|Tip: inspect the repository with git -C '$path' status"
						else
							operation_logs="$operation_logs|Checked out $target_info"
						fi
					fi
				fi
			fi
		elif [ "$DEP_RESULT" != "err" ]; then
			operation_logs="Not a checked-out Git repository; Tip: inspect '$path' before retrying checkout"
			DEP_RESULT="err"
			((ERRORS++))
		fi

		operation_logs="${operation_logs#|}"
		if [ -n "$operation_logs" ]; then
			git_deps_log_rollup "$path" "$DEP_RESULT" "${operation_logs//|/; }"
		fi
	done

	if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
		return 0
	elif [ $ERRORS -eq 0 ]; then
		git_deps_log_warning "Checkout completed with warnings=$WARNINGS (total=$TOTAL)"
		git_deps_log_message "Resolve the reported issues or re-run with --force where applicable"
		return 0
	else
		git_deps_log_error "Checkout failed: errors=$ERRORS warnings=$WARNINGS (total=$TOTAL)"
		git_deps_log_message "Tip: resolve the dependency-specific issues above before retrying"
		return 1
	fi
}

function git-deps-import {
	local recursive="false"
	local paths=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			echo "Usage: git-deps import [OPTIONS] [PATH...]"
			echo ""
			echo "Imports existing git repositories into .gitdeps and checks out their configured state"
			echo ""
			echo "Arguments:"
			echo "  PATH               Directory or repository to scan (default: deps)"
			echo ""
			echo "Options:"
			echo "  -r, --recursive    Recurse into subdirectories"
			echo "  -h, --help         Show this help message"
			return 0
			;;
		-r | --recursive)
			recursive="true"
			shift
			;;
		-*)
			git_deps_log_error "Unknown option: $1"
			return 1
			;;
		*)
			paths+=("$1")
			shift
			;;
		esac
	done

	if [ ${#paths[@]} -eq 0 ]; then
		paths=("deps")
	fi

	local path
	for path in "${paths[@]}"; do
		if [ ! -e "$path" ]; then
			git_deps_log_error "[$path] path not found"
			return 1
		fi
		if [ ! -d "$path" ] && [ ! -e "$path/.git" ]; then
			git_deps_log_error "[$path] not a directory or git repository"
			return 1
		fi
	done

	# An absent file is intentionally created by git_deps_ensure_entry below.
	declare -A existing_urls
	declare -A existing_branches
	declare -A existing_commits
	if [ -e "$GIT_DEPS_FILE" ]; then
		while IFS=$' \t' read -r entry_path entry_url entry_branch entry_commit _rest; do
			[ -z "$entry_path" ] && continue
			[[ "$entry_path" =~ ^# ]] && continue
			existing_urls["$entry_path"]="$entry_url"
			existing_branches["$entry_path"]="$entry_branch"
			existing_commits["$entry_path"]="$entry_commit"
		done <"$GIT_DEPS_FILE"
	fi

	local repositories=()
	local -A seen_repositories=()
	local repo
	local scan_path
	for scan_path in "${paths[@]}"; do
		if [ -e "$scan_path/.git" ]; then
			if [ -z "${seen_repositories[$scan_path]+x}" ]; then
				repositories+=("$scan_path")
				seen_repositories["$scan_path"]=1
			fi
			continue
		fi

		if [ "$recursive" = "true" ]; then
			while IFS= read -r -d '' git_dir; do
				local found="${git_dir%/.git}"
				if [ -z "${seen_repositories[$found]+x}" ]; then
					repositories+=("$found")
					seen_repositories["$found"]=1
				fi
			done < <(find "$scan_path" -name .git -print0)
		else
			while IFS= read -r child; do
				if [ -e "$child/.git" ] && [ -z "${seen_repositories[$child]+x}" ]; then
					repositories+=("$child")
					seen_repositories["$child"]=1
				fi
			done < <(printf '%s\n' "$scan_path"/*)
		fi
	done

	local total=${#repositories[@]}
	local current=0
	local added=0
	local updated=0
	local unchanged=0
	local errors=0
	local warnings=0
	local repo_path config_path url current_branch current_commit
	local target_branch target_commit target_rev local_changes
	local operation_logs

	for repo_path in "${repositories[@]}"; do
		((current++))
		# Keep symlink spelling: dependency paths are workspace paths, not resolved
		# repository locations. This ensures deps/foo remains deps/foo when it
		# points at a repository elsewhere in the workspace.
		config_path="$(git_deps_relative_path "$repo_path")"
		url=$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)
		current_branch=$(git -C "$repo_path" branch --show-current 2>/dev/null || true)
		current_commit=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null || true)
		operation_logs=""

		if [ -z "$url" ] || [ -z "$current_commit" ]; then
			git_deps_log_rollup "$config_path" "warn" "$operation_logs; missing origin or commit"
			((warnings++))
			continue
		fi

		if [ -z "${existing_urls[$config_path]+x}" ]; then
			target_branch="${current_branch:-main}"
			target_commit="$current_commit"
			git_deps_ensure_entry "$config_path" "$url" "$target_branch" "$target_commit"
			operation_logs="$operation_logs; added ${target_branch}@$(git_deps_op_commit_info "$repo_path" "$target_commit")"
			((added++))
		else
			target_branch="${existing_branches[$config_path]}"
			target_commit="${existing_commits[$config_path]}"
			if [ -z "$target_branch" ]; then
				target_branch="${current_branch:-main}"
			fi
			target_rev="${target_commit:-$target_branch}"
			local_changes=$(git_deps_op_localchanges "$repo_path" || true)
			if [ -n "$local_changes" ]; then
				git_deps_log_rollup "$config_path" "warn" "$operation_logs; cannot checkout with local changes"
				((warnings++))
				continue
			fi
			if ! git -C "$repo_path" rev-parse --verify "$target_rev^{commit}" >/dev/null 2>&1; then
				git_deps_log_rollup "$config_path" "warn" "$operation_logs; target '$target_rev' is unavailable locally"
				((warnings++))
				continue
			fi
			local needs_checkout="false"
			if [ -n "$target_commit" ] && [ "$current_commit" != "$target_commit" ]; then
				needs_checkout="true"
			elif [ -z "$target_commit" ] && [ "$current_branch" != "$target_branch" ]; then
				needs_checkout="true"
			fi
			if [ "$needs_checkout" = "true" ]; then
				if ! git_deps_op_checkout "$repo_path" "$target_rev" >/dev/null 2>&1; then
					git_deps_log_rollup "$config_path" "err" "Failed to checkout '$target_rev': $GIT_CHECKOUT_ERROR"
					((errors++))
					continue
				fi
				operation_logs="$operation_logs; checked out ${target_branch}@$(git_deps_op_commit_info "$repo_path" HEAD)"
				((updated++))
			else
				((unchanged++))
			fi
		fi

		if [ -n "$operation_logs" ]; then
			git_deps_log_rollup "$config_path" "ok" "${operation_logs#; }"
		fi
	done

	if [ "$total" -eq 0 ]; then
		return 0
	fi
	if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ]; then
		return 0
	elif [ "$errors" -eq 0 ]; then
		git_deps_log_warning "Import completed with warnings=$warnings: total=$total added=$added updated=$updated unchanged=$unchanged"
		return 0
	else
		git_deps_log_error "Import failed: errors=$errors warnings=$warnings: total=$total added=$added updated=$updated unchanged=$unchanged"
		return 1
	fi
}

# Function: git-deps-pull
# Pulls and updates all dependencies from their remote repositories
# Returns: 0 if no errors occurred, 1 otherwise
function git-deps-pull {
	local force="false"
	local specified_paths=()
	local invalid_paths=()
	local valid_paths=()

	# Parse arguments for force flag and optional dependency paths
	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help)
			echo "Usage: git-deps pull [OPTIONS] [PATH...]"
			echo ""
			echo "Pulls and updates dependencies from their remote repositories"
			echo ""
			echo "Options:"
			echo "  -f, --force        Skip the unpushed-commit confirmation"
			echo "  -h, --help         Show this help message"
			echo ""
			echo "Arguments:"
			echo "  PATH               One or more dependency paths to pull (optional, pulls all if omitted)"
			return 0
			;;
		-f | --force)
			force="true"
			shift
			;;
		-*)
			git_deps_log_error "Unknown option: $1"
			return 1
			;;
		*)
			specified_paths+=("$1")
			shift
			;;
		esac
	done

	IFS=$'\n'
	local FIELDS
	local ERRORS=0
	local WARNINGS=0
	local TOTAL=0

	local operation_start=$(date +%s)

	# A missing configuration leaves nothing to pull; report once and fail.
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		git_deps_log_error "[$GIT_DEPS_FILE] could not be found"
		return 1
	fi

	# If specific paths were provided, validate them against registered dependencies
	if [ ${#specified_paths[@]} -gt 0 ]; then
		local registered_paths=()
		for LINE in $(git_deps_read); do
			IFS='|' read -ra FIELDS <<<"$LINE"
			if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then
				continue
			fi
			registered_paths+=("${FIELDS[0]}")
		done

		for specified_path in "${specified_paths[@]}"; do
			local found="false"
			for registered_path in "${registered_paths[@]}"; do
				if [ "$specified_path" = "$registered_path" ]; then
					valid_paths+=("$specified_path")
					found="true"
					break
				fi
			done
			if [ "$found" = "false" ]; then
				invalid_paths+=("$specified_path")
			fi
		done

		if [ ${#invalid_paths[@]} -gt 0 ]; then
			for invalid_path in "${invalid_paths[@]}"; do
				git_deps_log_error "[$invalid_path] is not a registered dependency"
			done
			return 1
		fi

		TOTAL=${#valid_paths[@]}
	else
		# Count total dependencies when no path filter is provided
		for LINE in $(git_deps_read); do
			((TOTAL++))
		done
	fi

	if [ $TOTAL -eq 0 ]; then
		return 0
	fi

	for LINE in $(git_deps_read); do
		IFS='|' read -ra FIELDS <<<"$LINE"
		if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then continue; fi
		# PATH REPO REV
		local REPO="${FIELDS[0]}"
		local URL="${FIELDS[1]}"
		local REV="${FIELDS[2]:-main}"

		# Skip non-selected dependencies when specific paths were requested
		if [ ${#valid_paths[@]} -gt 0 ]; then
			local include="false"
			for valid_path in "${valid_paths[@]}"; do
				if [ "$REPO" = "$valid_path" ]; then
					include="true"
					break
				fi
			done
			if [ "$include" = "false" ]; then
				continue
			fi
		fi

		local repo_start=$(date +%s)
		local operation_logs=""
		local DEP_RESULT="ok" # ok|warn|err

		# Check for unpushed commits and ask for confirmation
		if [ -e "$REPO/.git" ] && git_deps_op_has_unpushed_commits "$REPO" "$REV"; then
			if ! git_deps_confirm "Dependency '$REPO' has unpushed commits. Continue pulling?" "$force"; then
				operation_logs="Skipping $REPO due to user choice"
				DEP_RESULT="warn"
				((WARNINGS++))
				git_deps_log_rollup "$REPO" "$DEP_RESULT" "${operation_logs//|/; }"
				continue
			fi
		fi

		# Clone if missing
		if [ ! -e "$REPO/.git" ]; then
			operation_logs="Cloning $URL..."
			mkdir -p "$(dirname "$REPO")" 2>/dev/null || true
			local clone_output
			if clone_output=$(git_deps_op_clone "$URL" "$REPO" "true"); then
				if git_deps_op_checkout "$REPO" "$REV" 2>/dev/null; then
					local end_time=$(date +%s)
					local duration=$((end_time - repo_start))
					local commit_after
					commit_after=$(git_deps_op_commit_info "$REPO" HEAD)
					operation_logs="$operation_logs|$clone_output|$REPO cloned at $commit_after (${duration}s)"
				else
					operation_logs="$operation_logs|Failed to checkout branch $REV: $GIT_CHECKOUT_ERROR"
					((ERRORS++))
					DEP_RESULT="err"
				fi
			else
				operation_logs="$operation_logs|$clone_output"
				((ERRORS++))
				DEP_RESULT="err"
			fi
		else
			# Existing repo path
			local local_changes=$(git_deps_op_localchanges "$REPO")
			if [ -n "$local_changes" ]; then
				operation_logs="Cannot pull $REPO: has uncommitted changes|Tip: commit or stash changes first: git -C '$REPO' status"
				((WARNINGS++))
				DEP_RESULT="warn"
			else
				operation_logs=""
				local commit_before
				commit_before=$(git_deps_op_commit_info "$REPO" HEAD)
				local git_output
				git_output=$(git -C "$REPO" pull origin "$REV" 2>&1)
				local pull_exit=$?
				if [ "$pull_exit" -ne 0 ]; then
					operation_logs="Pull failed from $URL: $git_output"
					if echo "$git_output" | grep -q "branch.*not found"; then
						operation_logs="$operation_logs|Branch '$REV' not found. Available branches:"
						local branches=$(git -C "$REPO" branch -r 2>/dev/null | head -5 | sed 's|origin/|  - |')
						operation_logs="$operation_logs|$branches"
					else
						operation_logs="$operation_logs|Tip: check repository status: git -C '$REPO' status"
					fi
					((ERRORS++))
					DEP_RESULT="err"
				else
					local end_time=$(date +%s)
					local duration=$((end_time - repo_start))
					local commit_after
					commit_after=$(git_deps_op_commit_info "$REPO" HEAD)
					if [ "$commit_before" != "$commit_after" ]; then
						operation_logs="Updated on $REV: $commit_before → $commit_after"
					fi
					# DEP_RESULT remains ok
				fi
			fi
		fi

		if [ -n "$operation_logs" ]; then
			git_deps_log_rollup "$REPO" "$DEP_RESULT" "${operation_logs//|/; }"
		fi
	done

	local total_time=$(date +%s)
	local total_duration=$((total_time - operation_start))

	if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
		return 0
	elif [ "$ERRORS" -eq 0 ]; then
		git_deps_log_warning "Pull completed with warnings=$WARNINGS (total=$TOTAL, ${total_duration}s)"
		git_deps_log_message "Check individual repositories for issues"
		return 0
	else
		git_deps_log_error "Pull failed: errors=$ERRORS warnings=$WARNINGS (total=$TOTAL, ${total_duration}s)"
		git_deps_log_message "Check individual repositories for issues"
		return 1
	fi
}

# Function: git-deps
# Main entry point for git-deps commands
# Parameters:
#   subcommand - Command to execute (status, pull, push, etc.)
#   ... - Additional arguments passed to subcommand
function git-deps {
	local command="$1"
	case "$command" in
	"" | -h | --help | help)
		echo "
Usage: $GIT_DEPS_MODE-deps <subcommand> [options]

$GIT_DEPS_MODE-deps is an alternative to submodules that keeps dependencies in
sync.

Available subcommands:
  add REPO_PATH REPO_URL [BRANCH] [COMMIT]    Adds a new dependency
  remove [OPTIONS] PATHS...  Removes dependencies from .gitdeps
  list [GLOB]                Lists all dependencies, optionally filtered by glob
  status [PATH...]           Shows the status of each dependency, or specific ones
  checkout [OPTIONS] [PATH...] Checks out dependencies to saved state (no network)
                             Use --missing to clone only absent dependencies
  update [PATH...]           Updates dependencies to latest from remote
  pull [PATH...]             Pulls and updates dependencies from remote
  push [PATH...]             Push changes in dependencies to remotes
  state                      Shows the current state
  save [OPTIONS]             Saves the current state to $GIT_DEPS_FILE
  fix [OPTIONS]              Repairs $GIT_DEPS_FILE (strips extra fields, etc.)
  import [OPTIONS] [PATH...] Imports dependencies from PATH=deps/

"
		;;
	add)
		shift
		git-deps-add "$@"
		;;
	remove | rm)
		shift
		git-deps-remove "$@"
		;;
	list | ls)
		shift
		git_deps_list "$@"
		;;
	status | st)
		shift
		git-deps-status "$@"
		;;
	checkout | so)
		shift
		git-deps-checkout "$@"
		;;
	push | ph)
		shift
		if ! git-deps-push "$@"; then
			git_deps_log_error "Could not push dependencies"
			git_deps_log_message "Some dependencies may need to be manually synced first."
		fi

		;;
	pull | pl)
		shift
		git-deps-pull "$@"
		;;
	state)
		shift
		git-deps-state "$@"
		;;
	save | s)
		shift
		git-deps-save "$@"
		;;
	fix | fx)
		shift
		git-deps-fix "$@"
		;;
	update | up)
		shift
		git-deps-update "$@"
		;;
	import | im)
		shift
		git-deps-import "$@"
		;;
	*)
		git_deps_log_error "Unknown command: $command"
		git_deps_log_message "Run '$GIT_DEPS_MODE-deps help' to see available commands"
		return 1
		;;
	esac
}
# Only run the main function if the script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	git-deps "$@"
fi
# EOF
