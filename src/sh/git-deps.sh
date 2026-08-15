#!/usr/bin/env bash

#  _____ _ _      ____
# |   __|_| |_   |    \ ___ ___ ___
# |  |  | |  _|  |  |  | -_| . |_ -|
# |_____|_|_|    |____/|___|  _|___|
#                          |_|

# FIXME: Should separate the commands `kebab-case` from the functions `snake_case`.

# Only set colors if NO_COLOR is not set and tput is available
if [[ -z "${NO_COLOR:-}" ]] && command -v tput >/dev/null 2>&1; then
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

# Function: git_deps_log_action
# Logs an action message in green color
# Parameters:
#   message - Action message to display
function git_deps_log_action {
	local message="$*"
	echo "${BLUE} ▶ $message$RESET" >&2
	return 0
}

function git_deps_log_step {
	echo "${DIM} ⋯ $*$RESET" >&2
	return 0
}

function git_deps_log_message {
	local message="$*"
	echo " … $message$RESET" >&2
	return 0
}

function git_deps_log_output_section {
	echo -n "${BLUE} ▸ $*$RESET"
}

function git_deps_log_output {
	echo "${BLUE}├─${RESET} $*$RESET"
	return 0
}

function git_deps_log_rollup {
	local current="$1"
	local total="$2"
	local path="$3"
	local result="$4"
	shift 4

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

	if [ -n "$message" ]; then
		echo "${color}${symbol} ${current}/${total} [${path}] ${message}${RESET}" >&2
	else
		echo "${color}${symbol} ${current}/${total} [${path}]${RESET}" >&2
	fi
	return 0
}

function git_deps_log_output_start {
	echo -n "${BLUE_LT}" >&2
}

function git_deps_log_output_end {
	echo -n "${RESET}" >&2
}

function git_deps_log_success {
	local message="$*"
	echo "${GREEN} ✓ $message${RESET}" >&2
}

# Function: git_deps_log_error
# Logs an error message in red color
# Parameters:
#   message - Error message to display
function git_deps_log_error {
	local message="$*"
	echo "${RED}✗ Error: $message${RESET}" >&2
	return 1
}

# Function: git_deps_log_warning
# Logs a warning message in orange color
# Parameters:
#   message - Warning message to display
function git_deps_log_warning {
	local message="$*"
	echo "${ORANGE}⚠ $message${RESET}" >&2
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
		git_deps_log_step "Force flag set, proceeding without confirmation"
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
		git_deps_log_error "Could not find deps file: $GIT_DEPS_FILE"
		return 1
	fi
}

# Function: git_deps_list REPO?
# Returns the list of repositories that match the given glob
function git_deps_list {
	local repo_filter="${1:-}"
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
		git_deps_log_message "Creating .gitdeps file"
		echo "$LINE" >"$GIT_DEPS_FILE"
		git_deps_log_message "Added dependency $REPO [$BRANCH] to .gitdeps"
	else
		# Match on the exact first field to avoid regex metacharacters in paths
		local EXISTING
		EXISTING=$(awk -v repo="$REPO" 'BEGIN { FS="[ \t]+" } $1 == repo { print; exit }' "$GIT_DEPS_FILE")
		if [ -z "$EXISTING" ]; then
			echo "$LINE" >>"$GIT_DEPS_FILE"
			git_deps_log_message "Added dependency $REPO [$BRANCH] to .gitdeps"
		elif [ "$EXISTING" == "$LINE" ]; then
			git_deps_log_message "$REPO already registered with same configuration"
		else
			local TMPFILE=$(mktemp "$GIT_DEPS_FILE".XXX)
			awk -v repo="$REPO" 'BEGIN { FS="[ \t]+" } $1 == repo { next } { print }' "$GIT_DEPS_FILE" >"$TMPFILE"
			echo -e "$LINE" >>"$TMPFILE"
			cat "$TMPFILE" >"$GIT_DEPS_FILE"
			unlink "$TMPFILE"
			git_deps_log_message "Updated dependency $REPO [$BRANCH] in .gitdeps"
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
		git_deps_write_file "$content"
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
	parent="$(dirname "$repo_path")"
	if [ ! -e "$parent" ]; then
		mkdir -p "$parent"
	fi
	if [ "$GIT_DEPS_MODE" == "jj" ]; then
		# Show progress for jj clone
		if [ "$quiet" = "true" ]; then
			echo "Running: jj git clone --colocate"
		else
			git_deps_log_message "Running: jj git clone --colocate"
		fi
		if ! jj git clone --colocate "$repo" "$repo_path" 2>/dev/null; then
			if [ "$quiet" = "true" ]; then
				echo "Unable to clone repository: $repo"
			else
				git_deps_log_error "Unable to clone repository: $repo"
			fi
			return 1
		fi
	else
		# Show progress for git clone
		if [ "$quiet" = "true" ]; then
			echo "Running: git clone --progress"
		else
			git_deps_log_message "Running: git clone --progress"
		fi
		if ! git clone --progress "$repo" "$repo_path" 2>/dev/null; then
			if [ "$quiet" = "true" ]; then
				echo "Unable to clone repository: $repo"
			else
				git_deps_log_error "Unable to clone repository: $repo"
			fi
			return 1
		fi
	fi

	if [ "$quiet" = "true" ]; then
		echo "Dependency clone at: $repo_path"
		echo "Clone completed successfully"
	else
		git_deps_log_success "Dependency clone at: $repo_path"
		git_deps_log_message "Clone completed successfully"
	fi
	return 0
}

function git_deps_op_fetch {
	local path="$1"
	local origin="${2:-}"
	local quiet="${3:-false}"

	# Skip fetch in offline mode
	if [ "$GIT_DEPS_OFFLINE" = "true" ]; then
		if [ "$quiet" = "true" ]; then
			echo "Skipping fetch (offline mode): $path"
		else
			git_deps_log_step "Skipping fetch (offline mode): $path"
		fi
		return 0
	fi

	if ! git_deps_file_aged "$path"; then
		if [ "$quiet" = "true" ]; then
			echo "Skipping recently fetched repo: $path"
		else
			git_deps_log_step "Skipping recently fetched repo: $path"
		fi
		return 0
	fi
	if [ "$quiet" = "true" ]; then
		echo "Fetching updates (this may take a moment…)"
	else
		git_deps_log_step "Fetching updates (this may take a moment…)"
	fi

	# Use timeout to prevent hanging on unresponsive remotes
	local fetch_cmd="git -C \"$path\" fetch --progress \"$origin\" 2>/dev/null"
	local fetch_result=0

	if command -v timeout >/dev/null 2>&1; then
		# GNU coreutils timeout (Linux)
		if timeout "${GIT_DEPS_TIMEOUT}s" bash -c "$fetch_cmd"; then
			fetch_result=0
		else
			fetch_result=$?
		fi
	elif command -v gtimeout >/dev/null 2>&1; then
		# GNU coreutils timeout on macOS (via brew install coreutils)
		if gtimeout "${GIT_DEPS_TIMEOUT}s" bash -c "$fetch_cmd"; then
			fetch_result=0
		else
			fetch_result=$?
		fi
	else
		# Fallback: use perl for timeout on macOS without coreutils
		if perl -e "alarm ${GIT_DEPS_TIMEOUT}; exec @ARGV" -- bash -c "$fetch_cmd" 2>/dev/null; then
			fetch_result=0
		else
			fetch_result=$?
		fi
	fi

	if [ $fetch_result -eq 0 ]; then
		# We touch the path so that the age is updated
		touch "$path"
		if [ "$quiet" = "true" ]; then
			echo "Fetch completed successfully"
		else
			git_deps_log_step "Fetch completed successfully"
		fi
		return 0
	elif [ $fetch_result -eq 124 ] || [ $fetch_result -eq 142 ]; then
		# 124 = timeout exit code, 142 = SIGALRM (perl timeout)
		if [ "$quiet" = "true" ]; then
			echo "Fetch timed out after ${GIT_DEPS_TIMEOUT}s: $path"
		else
			git_deps_log_warning "Fetch timed out after ${GIT_DEPS_TIMEOUT}s: $path"
		fi
		return 1
	else
		if [ "$quiet" = "true" ]; then
			echo "Fetch failed: $path $origin"
		else
			git_deps_log_error "Fetch failed: $path $origin"
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

	git -C "$path" show -s --format="%cd" --date=short "$commit" 2>/dev/null || echo ""
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
	if ! git_deps_op_clone "$repo" "$path" "true" >/dev/null 2>&1; then
		echo "err|$path|$repo|$branch_input|$commit|Failed to clone repository: $repo"
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
			echo "err|$path|$repo|$final_branch|$commit|Failed to checkout $checkout_rev"
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
		echo "err|$path|Could not find deps file: $GIT_DEPS_FILE"
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
# Returns: Outputs status code and returns 0/1
function git_deps_update {
	local pinned_mode="$1"
	local force="$2"
	local path="$3"
	local repo="$4"
	local branch="${5:-main}"
	local commit="${6:-}"

	if [ -z "$path" ]; then
		echo "err-missing-path"
		return 1
	elif [ -z "$repo" ]; then
		echo "err-missing-repo"
		return 1
	fi

	# Clone if path doesn't exist
	if [ ! -e "$path" ]; then
		git_deps_log_action "Retrieving dependency: $path ← $repo [$branch]"
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
			git_deps_log_message "→ Commit or stash changes: cd $path && git status"
			echo "err-uncommitted"
			return 1
		fi
		if [ "$has_unpushed" = "true" ]; then
			git_deps_log_warning "Cannot update $path: has unpushed commits"
			git_deps_log_message "→ Push changes first: cd $path && git push"
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
	git_deps_log_message "Fetching latest commits for $path"
	if ! git_deps_op_fetch "$path"; then
		git_deps_log_error "Failed to fetch from remote for $path"
		git_deps_log_message "→ Check network connection and remote URL: cd $path && git remote -v"
		echo "err-fetch-failed"
		return 1
	fi

	# Get current state
	local current_branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
	local current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "")

	if [ "$pinned_mode" = "true" ]; then
		# PINNED MODE: Checkout to exact pinned commit
		if [ -z "$commit" ]; then
			git_deps_log_error "No pinned commit specified for $path"
			git_deps_log_message "→ The .gitdeps entry for this dependency has no commit hash"
			echo "err-no-pinned-commit"
			return 1
		fi

		# Check if pinned commit exists after fetch
		if ! git -C "$path" cat-file -e "$commit^{commit}" >/dev/null 2>&1; then
			git_deps_log_error "Pinned commit ${commit:0:8} not found in $path"
			git_deps_log_message "→ The commit may have been force-pushed away. Run 'git-deps checkout' to use branch HEAD instead"
			echo "err-pinned-missing"
			return 1
		fi

		# Checkout to pinned commit
		if [ "$current_commit" = "$commit" ]; then
			git_deps_log_step "$path already at pinned commit ${commit:0:8}"
			echo "ok-already-pinned"
		else
			git_deps_log_message "Checking out to pinned commit ${commit:0:8}..."
			if ! git_deps_op_checkout "$path" "$commit"; then
				git_deps_log_error "Failed to checkout pinned commit ${commit:0:8} in $path"
				git_deps_log_message "→ The commit may be corrupted. Try recloning: rm -rf $path && git-deps checkout"
				echo "err-checkout-failed"
				return 1
			fi
			git_deps_log_step "Updated $path to pinned commit ${commit:0:8}"
			echo "ok-pinned"
		fi
	else
		# DEFAULT MODE: Fast-forward to latest branch HEAD
		local remote_head=$(git -C "$path" rev-parse origin/$branch 2>/dev/null || echo "")

		if [ -z "$remote_head" ]; then
			git_deps_log_warning "Remote branch origin/$branch not found for $path"
			git_deps_log_message "→ Check available branches: cd $path && git branch -r"
			echo "err-no-remote-branch"
			return 1
		fi

		# Check if we can fast-forward
		if [ "$current_commit" = "$remote_head" ]; then
			git_deps_log_step "$path already at latest commit ${remote_head:0:8} on $branch"
			echo "ok-up-to-date"
		elif git -C "$path" merge-base --is-ancestor "$current_commit" "$remote_head" 2>/dev/null; then
			# Can fast-forward
			git_deps_log_message "Fast-forwarding $path to ${remote_head:0:8}..."
			if ! git -C "$path" merge --ff-only "$remote_head" 2>/dev/null; then
				git_deps_log_error "Failed to fast-forward $path"
				git_deps_log_message "→ Use 'git-deps checkout' to reset to saved state, or resolve manually in $path"
				echo "err-fast-forward-failed"
				return 1
			fi
			git_deps_log_step "Updated $path: ${current_commit:0:8} → ${remote_head:0:8} on $branch"
			echo "ok-fast-forwarded"
		else
			# Cannot fast-forward - diverged
			git_deps_log_warning "Cannot fast-forward $path: local branch has diverged from remote"
			git_deps_log_message "→ Use 'git-deps checkout' to reset to saved state, or resolve manually in $path"
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
	local CURRENT=0
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

	git_deps_log_action "Checking dependency status…"

	# Count total dependencies and validate specified paths
	for LINE in $(git_deps_read); do
		((TOTAL++))
	done

	if [ $TOTAL -eq 0 ]; then
		git_deps_log_message "No dependencies found in .gitdeps"
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
				git_deps_log_error "Path '$invalid_path' is not a registered dependency"
			done
			return 1
		fi
	fi

	# Phase 1: Parallel fetch for all dependencies (unless offline)
	# This significantly speeds up status checks by parallelizing network I/O
	if [ "$GIT_DEPS_OFFLINE" != "true" ] && [ "$GIT_DEPS_PARALLEL" -gt 1 ] 2>/dev/null; then
		git_deps_log_step "Fetching updates in parallel (max ${GIT_DEPS_PARALLEL} concurrent)…"

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

		git_deps_log_step "Parallel fetch complete"
	fi

	for LINE in $(git_deps_read); do
		((CURRENT++))
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

		git_deps_log_rollup "$CURRENT" "$TOTAL" "$path" "$DEP_RESULT" "dep=${dep_status} [${display_branch}] ${dep_commit:-$local_commit} ${dep_date} | local=${local_status} [${display_branch}] ${local_commit:-unknown} ${local_date}${local_ahead} | remote=${remote_status} [${display_branch}] ${remote_commit:-unknown} ${remote_date}${remote_ahead}"
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

	# Count dependencies silently for state command
	for LINE in $(git_deps_read); do
		((TOTAL++))
	done

	if [ $TOTAL -eq 0 ]; then
		git_deps_log_message "No dependencies found in .gitdeps"
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

	git_deps_log_action "Saving current dependency state"

	local state="$(git-deps-state)"
	local deps_file="$(git_deps_path 2>/dev/null || echo "$GIT_DEPS_FILE")"
	local count=0

	# Count dependencies
	if [ -n "$state" ]; then
		count=$(echo "$state" | wc -l)
	fi

	if [ "$count" -eq 0 ]; then
		git_deps_log_message "No dependencies to save"
		git_deps_log_message "Use 'git-deps add' to add dependencies first"
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
				local reason="no cached remote ancestor for ${commit:0:12}"
				if [ ! -e "$path/.git" ]; then
					reason="not a checked-out git repository"
				fi
				git_deps_log_rollup "$count" "$count" "$path" "err" "$reason"
				((safe_errors++))
			fi
		else
			local reason="commit ${commit:0:12} is not on any cached remote ref"
			if [ ! -e "$path/.git" ]; then
				reason="not a checked-out git repository"
			elif ! git_deps_op_has_remote_refs "$path"; then
				reason="repository has no cached remote refs"
			fi
			git_deps_log_rollup "$count" "$count" "$path" "err" "$reason"
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

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		local path url branch commit
		# state output format: path repo branch commit
		read -r path url branch commit <<<"$line"
		local new_line_payload="${url} ${branch} ${commit}"
		local operation_logs="Processing $path..."

		if [ -z "${existing_entries[$path]+x}" ]; then
			operation_logs="$operation_logs|Adding new entry (${branch} ${commit:0:8})"
			((added++))
		elif [ "${existing_entries[$path]}" = "$new_line_payload" ]; then
			operation_logs="$operation_logs|No change (${branch} ${commit:0:8})"
			((unchanged++))
		else
			# Compare old vs new commit/branch
			local old_val="${existing_entries[$path]}"
			local old_url old_branch old_commit
			IFS=' ' read -r old_url old_branch old_commit <<<"$old_val"
			if [ -z "$old_commit" ]; then
				old_commit=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "unknown")
			fi
			operation_logs="$operation_logs|Updating entry (${branch} ${old_commit:0:8} → ${commit:0:8})"
			((updated++))
		fi

		# Append to new file content
		new_content+="$path $url $branch $commit"$'\n'

		git_deps_log_rollup "$count" "$count" "$path" "ok" "${operation_logs//|/; }"
	done <<<"$state"

	git_deps_log_message "Recording $count dependency states to $GIT_DEPS_FILE"

	if git_deps_write "${new_content%$'\n'}"; then
		git_deps_log_success "Saved: added=$added updated=$updated unchanged=$unchanged"
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
			echo "  -f, --force        Force update even with uncommitted/unpushed changes"
			echo "  -h, --help         Show this help message"
			return 0
			;;
		--pinned)
			pinned="true"
			shift
			;;
		-f | --force)
			force="true"
			shift
			;;
		*)
			specified_paths+=("$1")
			shift
			;;
		esac
	done

	local old_ifs="$IFS"
	IFS=$'\n'
	local TOTAL=0
	local CURRENT=0
	local ERRORS=0
	local WARNINGS=0

	git_deps_log_action "Updating dependencies"

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
				git_deps_log_error "Path '$invalid_path' is not a registered dependency"
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
		git_deps_log_message "No dependencies found in .gitdeps"
		return 0
	fi

	for LINE in $(git_deps_read); do
		((CURRENT++))
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
		update_output=$(git_deps_update "$pinned" "$force" "${FIELDS[@]}")
		local update_kind="${update_output%%-*}"
		local update_reason="${update_output#*-}"
		local DEP_RESULT="ok"
		if [ "$update_kind" = "err" ]; then
			case "$update_reason" in
			uncommitted | unpushed | no-remote-branch | diverged)
				((WARNINGS++))
				DEP_RESULT="warn"
				;;
			*)
				((ERRORS++))
				DEP_RESULT="err"
				;;
			esac
		fi

		local update_summary="${update_output#ok-}"
		update_summary="${update_summary#err-}"
		git_deps_log_rollup "$CURRENT" "$TOTAL" "$path" "$DEP_RESULT" "Update result: ${update_summary}"
	done

	if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
		git_deps_log_success "All dependencies updated successfully"
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

	git_deps_log_action "Adding dependency: $path ← $repo"

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
		local short_commit="${result_commit:0:8}"
		summary="$summary|Dependency added: ${result_branch}@${short_commit}"
	fi

	git_deps_log_rollup "1" "1" "$path" "$DEP_RESULT" "${summary//|/; }"

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

	if [ "$force" = "true" ]; then
		git_deps_log_step "Force flag set (no-op for remove)"
	fi

	git_deps_log_action "Removing dependencies"

	local ERRORS=0
	local TOTAL=${#paths[@]}
	local CURRENT=0

	for path in "${paths[@]}"; do
		((CURRENT++))
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

		git_deps_log_rollup "$CURRENT" "$TOTAL" "$path" "$DEP_RESULT" "${operation_logs//|/; }"
	done

	if [ $ERRORS -eq 0 ]; then
		if [ $TOTAL -eq 1 ]; then
			git_deps_log_success "Dependency removed successfully"
		else
			git_deps_log_success "Removed $TOTAL dependencies successfully"
		fi
		return 0
	else
		git_deps_log_error "Failed to remove $ERRORS out of $TOTAL dependencies"
		return 1
	fi
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
	local CURRENT=0

	git_deps_log_action "Checking out dependencies"

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
				git_deps_log_error "Path '$invalid_path' is not a registered dependency"
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
		git_deps_log_message "No dependencies found in .gitdeps"
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

		((CURRENT++))
		local operation_logs=""
		local DEP_RESULT="ok"

		# With --missing, existing checkouts are never touched: they may hold
		# local work, a detached revision or a symlink to a development tree.
		# A dangling symlink still counts as present so we never clone over it.
		if [ "$missing" = "true" ] && { [ -e "$path" ] || [ -L "$path" ]; }; then
			git_deps_log_rollup "$CURRENT" "$TOTAL" "$path" "ok" "Already present, skipped"
			continue
		fi

		# Clone if path doesn't exist (this is the only network operation allowed)
		if [ ! -e "$path" ]; then
			operation_logs="Cloning $repo..."
			if ! git_deps_op_clone "$repo" "$path"; then
				operation_logs="$operation_logs|${RED}Failed to clone $repo${RESET}"
				((ERRORS++))
				DEP_RESULT="err"
			else
				operation_logs="$operation_logs|Repository cloned successfully"
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
				operation_logs="$operation_logs|→ Commit or stash changes: cd $path && git status"
				blocked="true"
				((WARNINGS++))
				DEP_RESULT="warn"
			elif [ "$has_unpushed" = "true" ] && [ "$force" != "true" ]; then
				operation_logs="$operation_logs|${ORANGE}Cannot checkout: has unpushed commits${RESET}"
				operation_logs="$operation_logs|→ Push changes first: cd $path && git push"
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
						operation_logs="$operation_logs|${RED}Pinned commit ${commit:0:8} not found locally${RESET}"
						operation_logs="$operation_logs|→ Run 'git-deps update --pinned' to fetch the pinned commit"
						((ERRORS++))
						DEP_RESULT="err"
					fi
				fi

				# Only checkout when the current state differs from the desired state.
				if [ "$pinned_missing" != "true" ]; then
					if [ "$need_checkout" = "false" ]; then
						local display_target="$target_rev"
						if [[ "$display_target" =~ ^[0-9a-f]{40}$ ]]; then
							display_target="${display_target:0:8}"
						fi
						if [[ "$target_rev" =~ ^[0-9a-f]{40}$ ]]; then
							operation_logs="$operation_logs|Already at $display_target"
						else
							operation_logs="$operation_logs|Already on $display_target (${current_commit:0:8})"
						fi
					else
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

						operation_logs="$operation_logs|Checking out $target_rev..."
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
						fi
					fi
				fi
			fi
		fi

		git_deps_log_rollup "$CURRENT" "$TOTAL" "$path" "$DEP_RESULT" "${operation_logs//|/; }"
	done

	if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
		if [ $TOTAL -eq 1 ]; then
			git_deps_log_success "Dependency checkout completed successfully"
		else
			git_deps_log_success "All $TOTAL dependencies checked out successfully"
		fi
		return 0
	elif [ $ERRORS -eq 0 ]; then
		git_deps_log_warning "Checkout completed with warnings=$WARNINGS (total=$TOTAL)"
		git_deps_log_message "Resolve the reported issues or re-run with --force where applicable"
		return 0
	else
		git_deps_log_error "Checkout failed: errors=$ERRORS warnings=$WARNINGS (total=$TOTAL)"
		git_deps_log_message "Resolve the issues manually, or re-run with --force where applicable"
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

	git_deps_log_action "Importing dependencies"

	local path
	for path in "${paths[@]}"; do
		if [ ! -e "$path" ]; then
			git_deps_log_error "Path not found: $path"
			return 1
		fi
		if [ ! -d "$path" ] && [ ! -e "$path/.git" ]; then
			git_deps_log_error "Path is not a directory or git repository: $path"
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
		operation_logs="Scanning $config_path"

		if [ -z "$url" ] || [ -z "$current_commit" ]; then
			git_deps_log_rollup "$current" "$total" "$config_path" "warn" "$operation_logs; missing origin or commit"
			((warnings++))
			continue
		fi

		if [ -z "${existing_urls[$config_path]+x}" ]; then
			target_branch="${current_branch:-main}"
			target_commit="$current_commit"
			git_deps_ensure_entry "$config_path" "$url" "$target_branch" "$target_commit"
			operation_logs="$operation_logs; added ${target_branch}@${target_commit:0:8}"
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
				git_deps_log_rollup "$current" "$total" "$config_path" "warn" "$operation_logs; cannot checkout with local changes"
				((warnings++))
				continue
			fi
			if ! git -C "$repo_path" rev-parse --verify "$target_rev^{commit}" >/dev/null 2>&1; then
				git_deps_log_rollup "$current" "$total" "$config_path" "warn" "$operation_logs; target '$target_rev' is unavailable locally"
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
					git_deps_log_rollup "$current" "$total" "$config_path" "err" "$operation_logs; failed to checkout '$target_rev'"
					((errors++))
					continue
				fi
				operation_logs="$operation_logs; checked out ${target_branch}@${target_commit:-current}"
				((updated++))
			else
				operation_logs="$operation_logs; unchanged"
				((unchanged++))
			fi
		fi

		git_deps_log_rollup "$current" "$total" "$config_path" "ok" "$operation_logs"
	done

	if [ "$total" -eq 0 ]; then
		git_deps_log_message "No git repositories found"
		return 0
	fi
	if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ]; then
		git_deps_log_success "Import summary: total=$total added=$added updated=$updated unchanged=$unchanged"
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
	local CURRENT=0

	git_deps_log_action "Pulling dependencies…"
	echo "" >&2

	local operation_start=$(date +%s)

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
				git_deps_log_error "Path '$invalid_path' is not a registered dependency"
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
		git_deps_log_message "No dependencies found in .gitdeps"
		return 0
	fi

	# (Optional pre-check phase kept for potential future logic)

	# Reset counters for actual processing
	CURRENT=0

	for LINE in $(git_deps_read); do
		((CURRENT++))
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
				git_deps_log_rollup "$CURRENT" "$TOTAL" "$REPO" "$DEP_RESULT" "${operation_logs//|/; }"
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
					local commit_after=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)
					local commit_date=$(git -C "$REPO" show -s --format="%cd" --date=short HEAD 2>/dev/null)
					operation_logs="$operation_logs|$clone_output|$REPO cloned at $commit_after ($commit_date) (${duration}s)"
				else
					operation_logs="$operation_logs|$clone_output|Failed to checkout branch $REV"
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
				operation_logs="Cannot pull $REPO: has uncommitted changes|Commit or stash changes first: cd $REPO && git status"
				((WARNINGS++))
				DEP_RESULT="warn"
			else
				operation_logs="Pulling $REPO [$REV]..."
				local commit_before=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)
				local git_output
				git_output=$(git -C "$REPO" pull origin "$REV" 2>&1)
				local pull_exit=$?
				if [ "$pull_exit" -ne 0 ]; then
					operation_logs="$operation_logs|Pull failed for $REPO"
					if echo "$git_output" | grep -q "branch.*not found"; then
						operation_logs="$operation_logs|Branch '$REV' not found. Available branches:"
						local branches=$(git -C "$REPO" branch -r 2>/dev/null | head -5 | sed 's|origin/|  - |')
						operation_logs="$operation_logs|$branches"
					else
						operation_logs="$operation_logs|Check repository status: cd $REPO && git status"
					fi
					((ERRORS++))
					DEP_RESULT="err"
				else
					local end_time=$(date +%s)
					local duration=$((end_time - repo_start))
					local commit_after=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)
					local commit_date=$(git -C "$REPO" show -s --format="%cd" --date=short HEAD 2>/dev/null)
					if echo "$git_output" | grep -q "Already up to date"; then
						operation_logs="$operation_logs|$REPO is up to date at $commit_after ($commit_date) (${duration}s)"
					else
						operation_logs="$operation_logs|$REPO updated $commit_before → $commit_after ($commit_date) (${duration}s)"
					fi
					# DEP_RESULT remains ok
				fi
			fi
		fi

		git_deps_log_rollup "$CURRENT" "$TOTAL" "$REPO" "$DEP_RESULT" "${operation_logs//|/; }"
	done

	local total_time=$(date +%s)
	local total_duration=$((total_time - operation_start))

	if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
		if [ "$TOTAL" -eq 1 ]; then
			git_deps_log_success "Dependency pull completed (${total_duration}s)"
		else
			git_deps_log_success "All $TOTAL dependencies pulled successfully (${total_duration}s)"
		fi
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
