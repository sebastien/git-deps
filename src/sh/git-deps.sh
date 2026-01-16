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
	echo "${DIM} ⋯ $@$RESET" >&2
	return 0
}

function git_deps_log_message {
	local message="$*"
	echo " … $message$RESET" >&2
	return 0
}

function git_deps_log_tip {
	local message="$*"
	echo "${BLUE_LT} 💡 $message$RESET" >&2
	return 0
}

function git_deps_log_output_section {
	echo -n "${BLUE} ▸ $@$RESET"
}

function git_deps_log_output {
	echo "${BLUE}├─${RESET} $@$RESET"
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

function git_deps_log_warning {
	local message="$*"
	echo "${ORANGE} ⚠ $message${RESET}" >&2
	return 1
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
	echo "${ORANGE}⚠ $*${RESET}" >&2
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
		git_deps_read_file | cut -d"|" -f1
	else
		git_deps_read_file | cut -d"|" -f1 | grep "$repo_filter"
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
	LINE="$(echo -e "$REPO\t$URL\t$BRANCH\t$COMMIT")"
	if [ ! -e "$GIT_DEPS_FILE" ]; then
		git_deps_log_message "Creating .gitdeps file"
		echo -e "$LINE" >"$GIT_DEPS_FILE"
		git_deps_log_tip "Added dependency $REPO [$BRANCH] to .gitdeps"
	else
		local EXISTING=$(grep -E "$REPO[[:blank:]]" "$GIT_DEPS_FILE")
		if [ -z "$EXISTING" ]; then
			echo -e "$LINE" >>"$GIT_DEPS_FILE"
			git_deps_log_tip "Added dependency $REPO [$BRANCH] to .gitdeps"
		elif [ "$EXISTING" == "$LINE" ]; then
			git_deps_log_message "$REPO already registered with same configuration"
		else
			local TMPFILE=$(mktemp "$GIT_DEPS_FILE".XXX)
			grep -v -E "^$REPO[[:blank:]]" "$GIT_DEPS_FILE" >"$TMPFILE"
			echo -e "$LINE" >>"$TMPFILE"
			cat "$TMPFILE" >"$GIT_DEPS_FILE"
			unlink "$TMPFILE"
			git_deps_log_tip "Updated dependency $REPO [$BRANCH] in .gitdeps"
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
		git_deps_log_step "Fetching updates $(DIM)(this may take a moment…)"
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

	# Check if remote branch exists
	if ! git -C "$path" rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
		# No remote branch, so local commits exist
		return 0
	fi

	# Check if local is ahead of remote
	local ahead=$(git -C "$path" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "0")
	if [ "$ahead" -gt 0 ]; then
		return 0
	else
		return 1
	fi
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
#   branch - Branch/tag/commit to track (optional, defaults to main)
#   commit - Specific commit (optional)
#   force - Force flag (optional)
function git_deps_add {
	local repo="$1"
	local path="$2"
	local branch="${3:-main}"
	local commit="$4"
	local force="$5"

	# Validate required parameters
	if [ -z "$repo" ] || [ -z "$path" ]; then
		git_deps_log_error "Usage: git-deps add REPO_PATH REPO_URL [BRANCH] [COMMIT]"
		return 1
	fi

	# Check if path already exists
	if [ -e "$path" ]; then
		git_deps_log_error "Path '$path' already exists"
		return 1
	fi

	# Check if dependency already exists (unless force is specified)
	if [ "$force" != "true" ] && git_deps_has "$path"; then
		git_deps_log_error "Dependency already registered at '$path'"
		git_deps_log_tip "Run git-deps add -f $path $repo $branch $commit"
		return 1
	fi

	git_deps_log_action "Adding $repo to $path"

	# Clone the repository
	if ! git_deps_op_clone "$repo" "$path"; then
		return 1
	fi

	# Checkout the specified branch or commit
	local checkout_rev="${commit:-$branch}"
	if ! git_deps_op_checkout "$path" "$checkout_rev"; then
		# Clean up on failure
		rm -rf "$path" 2>/dev/null
		return 1
	fi

	# Get the current commit ID
	local current_commit
	current_commit=$(git_deps_op_commit_id "$path")

	# Use specified commit if provided, otherwise use current commit
	local final_commit="${commit:-$current_commit}"

	# Add to deps file
	git_deps_ensure_entry "$path" "$repo" "$branch" "$final_commit"

	git_deps_log_tip "${repo}[$branch] is now available in $path"
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
# Updates a dependency to the specified revision with validation
# Parameters:
#   path - Path to dependency
#   repo - Repository URL
#   rev - Target revision (defaults to main)
#   commit - Target commit (optional)
function git_deps_update {
	local path="$1"
	local repo="$2"
	local branch="${3:-main}"
	if [ -z "$path" ]; then
		git_deps_log_error "Dependency missing directory"
		git_deps_log_tip "Usage: git-deps update PATH REPO [REVISION] [COMMIT]"
		return 1
	elif [ -z "$repo" ]; then
		git_deps_log_error "Dependency missing repository"
		git_deps_log_tip "Usage: git-deps update PATH REPO [REVISION] [COMMIT]"
		return 1
	fi

	# Clone if path doesn't exist
	if [ ! -e "$path" ]; then
		git_deps_log_action "Retrieving dependency: $path ← $repo [$rev]"
		if ! git_deps_op_clone "$repo" "$path"; then
			return 1
		fi
	fi

	# Check for uncommitted changes (blocker for update)
	local local_changes=$(git_deps_op_localchanges "$path")
	if [ -n "$local_changes" ]; then
		git_deps_log_error "Cannot update $path: has uncommitted changes"
		git_deps_log_tip "Commit or stash local changes before updating"
		echo "err-uncommitted"
		return 1
	fi

	# Get current local branch and commit
	local current_branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
	local current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "")

	# Warn if we're changing branch or commit
	local target_commit="${commit:-$(git -C "$path" ls-remote "$repo" "$rev" 2>/dev/null | cut -f1)}"
	if [ "$current_branch" != "$rev" ] && [ "$current_branch" != "HEAD" ]; then
		if [ "$force" != "true" ]; then
			git_deps_confirm "Update will change branch from '$current_branch' to '$rev'. Continue?" "$force" || return 1
		else
			git_deps_log_message "Changing branch from '$current_branch' to '$rev'"
		fi
	fi

	# Check if target branch/commit exists in remote
	if ! git -C "$path" ls-remote --exit-code "$repo" "refs/heads/$rev" >/dev/null 2>&1; then
		if [ -n "$commit" ] && git -C "$path" cat-file -e "$commit" 2>/dev/null; then
			git_deps_log_message "Branch '$rev' not found in remote, using commit '$commit'"
		else
			git_deps_log_error "Branch '$rev' does not exist in remote repository"
			git_deps_log_tip "Check available branches with: git -C $path ls-remote $repo"
			echo "err-missing-branch"
			return 1
		fi
	fi

	# Fetch latest changes
	git_deps_log_message "Fetching latest commits for $path"
	if ! git_deps_op_fetch "$path"; then
		git_deps_log_error "Failed to fetch from remote"
		return 1
	fi

	# Checkout target revision
	local target_rev="${commit:-$rev}"
	if ! git_deps_op_checkout "$path" "$target_rev"; then
		git_deps_log_error "Failed to checkout '$target_rev'"
		return 1
	fi

	git_deps_log_tip "Updated $path to [$rev] $(git_deps_op_commit_id "$path" | head -c 8)"
	echo "ok-updated"
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
			--offline|-o)
				GIT_DEPS_OFFLINE=true
				shift
				;;
			--timeout=*)
				GIT_DEPS_TIMEOUT="${1#--timeout=}"
				shift
				;;
			--timeout|-t)
				GIT_DEPS_TIMEOUT="$2"
				shift 2
				;;
			--parallel=*)
				GIT_DEPS_PARALLEL="${1#--parallel=}"
				shift
				;;
			--parallel|-p)
				GIT_DEPS_PARALLEL="$2"
				shift 2
				;;
			--no-parallel)
				GIT_DEPS_PARALLEL=1
				shift
				;;
			--help|-h)
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
		git_deps_log_tip "No dependencies found in .gitdeps"
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
					name_rev="${name_rev%%~*}"  # Remove ~N suffix
					name_rev="${name_rev%%^*}"  # Remove ^N suffix
					name_rev="${name_rev#remotes/origin/}"  # Remove remote prefix
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
				remote_commit=$(git -C "$path" rev-parse "origin/$branch" 2>/dev/null || echo "unknown")
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

		# Improved output format with better visual hierarchy
		echo "${BLUE}┌─ ${path}${RESET}" >&2

		# Include operation logs within the tree structure
		if [ -n "$operation_logs" ]; then
			IFS='|' read -ra log_lines <<<"$operation_logs"
			for log_line in "${log_lines[@]}"; do
				if [ -n "$log_line" ]; then
					git_deps_log_output "$log_line"
				fi
			done
		fi

		# Format: component [STATUS] [branch] commit date (+ahead)
		git_deps_log_output "dep      ${dep_status} [${display_branch}] ${dep_commit:-$local_commit} ${dep_date}"
		git_deps_log_output "local    ${local_status} [${display_branch}] ${local_commit:-unknown} ${local_date}${local_ahead}"
		git_deps_log_output "remote   ${remote_status} [${display_branch}] ${remote_commit:-unknown} ${remote_date}${remote_ahead}"

		echo "${BLUE}└─ ${path} ${local_status}${RESET}" >&2
	done
}

function git-deps-state {
	IFS=$'\n'
	local TOTAL=0

	# Count dependencies silently for state command
	for LINE in $(git_deps_read); do
		((TOTAL++))
	done

	if [ $TOTAL -eq 0 ]; then
		git_deps_log_tip "No dependencies found in .gitdeps"
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
	git_deps_log_action "Saving current dependency state"

	local state="$(git-deps-state "$@")"
	local deps_file="$(git_deps_path 2>/dev/null || echo "$GIT_DEPS_FILE")"
	local count=0

	# Count dependencies
	if [ -n "$state" ]; then
		count=$(echo "$state" | wc -l)
	fi

	if [ "$count" -eq 0 ]; then
		git_deps_log_message "No dependencies to save"
		git_deps_log_tip "Use 'git-deps add' to add dependencies first"
		return 0
	fi

	# Build maps of existing entries (without comments) for change detection
	declare -A existing_entries
	if [ -e "$deps_file" ]; then
		while IFS=$'\t ' read -r e_path e_url e_branch e_commit _rest; do
			[ -z "$e_path" ] && continue
			[[ "$e_path" =~ ^# ]] && continue
			existing_entries["$e_path"]="${e_url}\t${e_branch}\t${e_commit}"
		done < <(grep -v '^[[:space:]]*#' "$deps_file" 2>/dev/null || true)
	fi

	local new_content=""
	local added=0
	local updated=0
	local unchanged=0
	local errors=0

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		local path url branch commit
		# state output format: path repo branch commit
		read -r path url branch commit <<<"$line"
		local new_line_payload="${url}\t${branch}\t${commit}"
		local status_type="ok"
		local operation_logs="Processing $path..."

		if [ -z "${existing_entries[$path]+x}" ]; then
			operation_logs="$operation_logs|Adding new entry (${branch} ${commit:0:8})"
			((added++))
		elif [ "${existing_entries[$path]}" = "$new_line_payload" ]; then
			operation_logs="$operation_logs|No change (${branch} ${commit:0:8})"
			status_type="ok"
			((unchanged++))
		else
			# Compare old vs new commit/branch
			local old_val="${existing_entries[$path]}"
			local old_url old_branch old_commit
			IFS=$'\t' read -r old_url old_branch old_commit <<<"$old_val"
			operation_logs="$operation_logs|Updating entry ${old_branch}:${old_commit:0:8} → ${branch}:${commit:0:8}"
			((updated++))
		fi

		# Append to new file content
		new_content+="$path $url $branch $commit"$'\n'

		# Output tree for this dependency
		echo "${BLUE}┌─ ${path}${RESET}" >&2
		IFS='|' read -ra log_lines <<<"$operation_logs"
		for log_line in "${log_lines[@]}"; do
			[ -n "$log_line" ] && git_deps_log_output "$log_line"
		done
		local dep_status_label="${GREEN}[OK]${RESET}"
		case "$status_type" in
		err) dep_status_label="${RED}[ERR]${RESET}" ;;
		warn) dep_status_label="${ORANGE}[WARN]${RESET}" ;;
		esac
		echo "${BLUE}└─ ${path} ${dep_status_label}${RESET}" >&2
		echo "" >&2
	done <<<"$state"

	git_deps_log_message "Recording $count dependency states to $GIT_DEPS_FILE"

	if git_deps_write "${new_content%$'\n'}"; then
		git_deps_log_tip "Saved: added=$added updated=$updated unchanged=$unchanged"
		return 0
	else
		git_deps_log_error "Failed to save dependency state"
		return 1
	fi
}

function git-deps-push {
	git_deps_log_error "Push command not yet implemented"
	git_deps_log_tip "Use 'git-deps pull' to sync dependencies, or manually push changes in dependency directories"
	return 1
}

function git-deps-update {
	local args="$@"
	local old_ifs="$IFS"
	IFS=$'\n'
	local STATUS
	local TOTAL=0
	local CURRENT=0
	local ERRORS=0

	git_deps_log_action "Updating dependencies"

	# Count total dependencies
	for LINE in $(git_deps_read); do
		((TOTAL++))
	done

	if [ $TOTAL -eq 0 ]; then
		git_deps_log_tip "No dependencies found in .gitdeps"
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
		git_deps_log_message "[$CURRENT/$TOTAL] Updating ${path} [${FIELDS[2]}]"

		local update_output
		update_output=$(git_deps_update "${FIELDS[@]}")
		IFS='-' read -ra STATUS <<<"$update_output"
		local DEP_RESULT="ok"
		case "${STATUS[0]}" in
		ok)
			DEP_RESULT="ok"
			;;
		err)
			((ERRORS++))
			DEP_RESULT="err"
			;;
		*)
			DEP_RESULT="warn"
			;;
		esac

		# Present a tree similar to pull/checkout with status badge
		echo "${BLUE}┌─ ${path}${RESET}" >&2
		git_deps_log_output "Update result: ${update_output}"
		local dep_status_label=""
		case "$DEP_RESULT" in
		err) dep_status_label="${RED}[ERR]${RESET}" ;;
		warn) dep_status_label="${ORANGE}[WARN]${RESET}" ;;
		*) dep_status_label="${GREEN}[OK]${RESET}" ;;
		esac
		echo "${BLUE}└─ ${path} ${dep_status_label}${RESET}" >&2
		echo "" >&2
	done

	if [ $ERRORS -eq 0 ]; then
		git_deps_log_tip "All dependencies updated successfully"
	else
		git_deps_log_error "Failed to update $ERRORS dependencies"
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

	git_deps_add "$repo" "$path" "$branch" "$commit" "$force"
}

function git-deps-checkout {
	local force="false"
	local strict="false"
	local repo_filter=""

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-f | --force)
			force="true"
			shift
			;;
		-s | --strict)
			strict="true"
			shift
			;;
		*)
			if [ -z "$repo_filter" ]; then
				repo_filter="$1"
			fi
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

	# Count total dependencies
	for LINE in $(git_deps_read); do
		if [ -z "$repo_filter" ] || [[ "${LINE%%|*}" == *"$repo_filter"* ]]; then
			((TOTAL++))
		fi
	done

	if [ $TOTAL -eq 0 ]; then
		git_deps_log_tip "No dependencies found in .gitdeps"
		return 0
	fi

	for LINE in $(git_deps_read); do
		IFS='|' read -ra FIELDS <<<"$LINE"
		if [[ "${FIELDS[0]}" =~ ^- ]] || [ ${#FIELDS[@]} -lt 3 ]; then continue; fi
		local path="${FIELDS[0]}"
		local repo="${FIELDS[1]}"
		local branch="${FIELDS[2]:-main}"
		local commit="${FIELDS[3]:-}"

		# Skip if filter doesn't match
		if [ -n "$repo_filter" ] && [[ "$path" != *"$repo_filter"* ]]; then
			continue
		fi

		((CURRENT++))
		git_deps_log_message "[$CURRENT/$TOTAL] Checking out $path [$branch]"

		local operation_logs=""
		local DEP_RESULT="ok"

		# Clone if path doesn't exist
		if [ ! -e "$path" ]; then
			operation_logs="Cloning $repo..."
			if ! git_deps_op_clone "$repo" "$path"; then
				operation_logs="$operation_logs|Failed to clone $repo"
				((ERRORS++))
				DEP_RESULT="err"
			else
				operation_logs="$operation_logs|Repository cloned successfully"
			fi
		fi

		# Checkout to specified revision
		if [ -e "$path/.git" ]; then
			local target_rev="${commit:-$branch}"
			local local_changes=$(git_deps_op_localchanges "$path")
			local current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null)
			local is_ahead="false"

			# Check if target revision exists and if local is ahead of it
			if git -C "$path" rev-parse --verify "$target_rev^{commit}" >/dev/null 2>&1; then
				local target_commit=$(git -C "$path" rev-parse "$target_rev^{commit}" 2>/dev/null)
				if [ "$current_commit" != "$target_commit" ]; then
					if git_deps_op_is_ancestor "$path" "$target_commit" "$current_commit"; then
						is_ahead="true"
					fi
				fi
			fi

			# Determine if we should skip checkout
			local should_skip="false"
			local skip_reason=""

			if [ -n "$local_changes" ]; then
				should_skip="true"
				if [ "$is_ahead" = "true" ]; then
					skip_reason="local is ahead with uncommitted changes"
				else
					skip_reason="has uncommitted changes"
				fi
			elif [ "$is_ahead" = "true" ]; then
				should_skip="true"
				skip_reason="local is ahead of $target_rev"
			fi

			if [ "$should_skip" = "true" ] && [ "$force" != "true" ]; then
				if [ "$strict" = "true" ]; then
					operation_logs="$operation_logs|${RED}Cannot checkout: $skip_reason${RESET}"
					((ERRORS++))
					DEP_RESULT="err"
				else
					operation_logs="$operation_logs|${ORANGE}Skipping checkout: $skip_reason${RESET}"
					((WARNINGS++))
					DEP_RESULT="warn"
				fi
			else
				operation_logs="$operation_logs|Checking out $target_rev..."
				if git_deps_op_checkout "$path" "$target_rev"; then
					: # success, nothing extra to do
				else
					# Show the actual git error
					local error_msg=""
					if [ -n "$GIT_CHECKOUT_ERROR" ]; then
						# Extract the most relevant line from git error
						error_msg=$(echo "$GIT_CHECKOUT_ERROR" | grep -E "^error:" | head -1 | sed 's/^error: //')
						if [ -z "$error_msg" ]; then
							error_msg=$(echo "$GIT_CHECKOUT_ERROR" | head -1)
						fi
					fi
					if [ -n "$error_msg" ]; then
						operation_logs="$operation_logs|${RED}Failed to checkout $target_rev: $error_msg${RESET}"
					else
						operation_logs="$operation_logs|${RED}Failed to checkout $target_rev${RESET}"
					fi
					((ERRORS++))
					DEP_RESULT="err"
				fi
			fi
		fi

		# Display tree structure for this dependency
		if [ -n "$operation_logs" ]; then
			echo "${BLUE}┌─ ${path}${RESET}" >&2
			IFS='|' read -ra log_lines <<<"$operation_logs"
			for log_line in "${log_lines[@]}"; do
				if [ -n "$log_line" ]; then
					git_deps_log_output "$log_line"
				fi
			done
			local dep_status_label=""
			case "$DEP_RESULT" in
			err) dep_status_label="${RED}[ERR]${RESET}" ;;
			warn) dep_status_label="${ORANGE}[WARN]${RESET}" ;;
			*) dep_status_label="${GREEN}[OK]${RESET}" ;;
			esac
			echo "${BLUE}└─ ${path} ${dep_status_label}${RESET}" >&2
			echo "" >&2
		fi
	done

	if [ $ERRORS -eq 0 ]; then
		if [ $WARNINGS -gt 0 ]; then
			git_deps_log_warning "Checkout completed with $WARNINGS warning(s)"
			git_deps_log_tip "Use --force to override and checkout anyway"
		elif [ $TOTAL -eq 1 ]; then
			git_deps_log_success "Dependency checkout completed successfully"
		else
			git_deps_log_success "All $TOTAL dependencies checked out successfully"
		fi
	else
		git_deps_log_error "Failed to checkout $ERRORS out of $TOTAL dependencies"
		git_deps_log_tip "Use --force to override and checkout anyway"
		return 1
	fi
}

function git-deps-import {
	local DEPS_PATH=${1:-deps}

	git_deps_log_action "Importing dependencies from $DEPS_PATH"

	if [ ! -d "$DEPS_PATH" ]; then
		git_deps_log_error "Directory not found: $DEPS_PATH"
		git_deps_log_tip "Create the directory or specify a different path"
		return 1
	fi

	git_deps_log_message "Scanning $DEPS_PATH for git repositories"

	local count=0
	local processed=0
	local added=0
	local updated=0
	local unchanged=0
	local errors=0

	# Cache existing entries for change detection
	declare -A existing_entries
	if [ -e "$GIT_DEPS_FILE" ]; then
		while IFS=$'\t ' read -r e_path e_url e_branch e_commit _rest; do
			[ -z "$e_path" ] && continue
			[[ "$e_path" =~ ^# ]] && continue
			existing_entries["$e_path"]="${e_url}\t${e_branch}\t${e_commit}"
		done < <(grep -v '^[[:space:]]*#' "$GIT_DEPS_FILE" 2>/dev/null || true)
	fi

	for REPO in "$DEPS_PATH"/*; do
		if [ -e "$REPO/.git" ]; then
			((count++))
			local operation_logs="Scanning $REPO..."
			local dep_status="ok"
			local url=$(git -C "$REPO" remote get-url origin 2>/dev/null || echo "unknown")
			local branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
			local commit=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo "unknown")

			if [ "$url" = "unknown" ] || [ "$commit" = "unknown" ]; then
				operation_logs="$operation_logs|Failed to read origin or commit"
				dep_status="err"
				((errors++))
			else
				local payload="${url}\t${branch}\t${commit}"
				if [ -z "${existing_entries[$REPO]+x}" ]; then
					operation_logs="$operation_logs|Adding entry (${branch} ${commit:0:8})"
					git_deps_ensure_entry "$REPO" "$url" "$branch" "$commit"
					((added++))
				elif [ "${existing_entries[$REPO]}" = "$payload" ]; then
					operation_logs="$operation_logs|Unchanged (${branch} ${commit:0:8})"
					((unchanged++))
				else
					local old_val="${existing_entries[$REPO]}"
					local old_url old_branch old_commit
					IFS=$'\t' read -r old_url old_branch old_commit <<<"$old_val"
					operation_logs="$operation_logs|Updating ${old_branch}:${old_commit:0:8} → ${branch}:${commit:0:8}"
					git_deps_ensure_entry "$REPO" "$url" "$branch" "$commit"
					((updated++))
				fi
			fi

			# Tree output
			echo "${BLUE}┌─ ${REPO}${RESET}" >&2
			IFS='|' read -ra log_lines <<<"$operation_logs"
			for log_line in "${log_lines[@]}"; do
				[ -n "$log_line" ] && git_deps_log_output "$log_line"
			done
			local dep_status_label="${GREEN}[OK]${RESET}"
			case "$dep_status" in
			err) dep_status_label="${RED}[ERR]${RESET}" ;;
			warn) dep_status_label="${ORANGE}[WARN]${RESET}" ;;
			esac
			echo "${BLUE}└─ ${REPO} ${dep_status_label}${RESET}" >&2
			echo "" >&2
		fi
	done

	if [ $count -eq 0 ]; then
		git_deps_log_tip "No git repositories found in $DEPS_PATH"
	else
		if [ $errors -eq 0 ]; then
			git_deps_log_tip "Import summary: total=$count added=$added updated=$updated unchanged=$unchanged"
		else
			git_deps_log_error "Import partial: total=$count added=$added updated=$updated unchanged=$unchanged errors=$errors"
			git_deps_log_tip "Check repositories with errors for valid git remotes"
			return 1
		fi
	fi
}

# Function: git-deps-pull
# Pulls and updates all dependencies from their remote repositories
# Returns: Number of errors encountered
function git-deps-pull {
	local force="false"

	# Parse arguments for force flag
	while [[ $# -gt 0 ]]; do
		case $1 in
		-f | --force)
			force="true"
			shift
			;;
		*)
			shift
			;;
		esac
	done

	IFS=$'\n'
	local STATUS
	local FIELDS
	local ERRORS=0
	local TOTAL=0
	local CURRENT=0

	git_deps_log_action "Pulling dependencies"

	# Count total dependencies first
	for LINE in $(git_deps_read); do
		((TOTAL++))
	done

	if [ $TOTAL -eq 0 ]; then
		git_deps_log_tip "No dependencies found in .gitdeps"
		return 0
	fi

	local operation_start=$(date +%s)

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

		local repo_start=$(date +%s)
		local operation_logs=""
		local DEP_RESULT="ok" # ok|warn|err

		# Check for unpushed commits and ask for confirmation
		if [ -e "$REPO/.git" ] && git_deps_op_has_unpushed_commits "$REPO"; then
			if ! git_deps_confirm "Dependency '$REPO' has unpushed commits. Continue pulling?" "$force"; then
				operation_logs="Skipping $REPO due to user choice"
				DEP_RESULT="warn"
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
					operation_logs="$operation_logs|$clone_output|$REPO cloned and ready (${duration}s)"
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
				((ERRORS++))
				DEP_RESULT="err"
			else
				operation_logs="Pulling $REPO [$REV]..."
				local git_output
				git_output=$(git -C "$REPO" pull origin "$REV" 2>&1)
				local pull_exit=$?
				if [ "$pull_exit" -ne 0 ]; then
					operation_logs="$operation_logs|Pull failed for $REPO"
					if echo "$git_output" | grep -q "branch.*not found"; then
						operation_logs="$operation_logs|Branch '$REV' not found. Available branches:"
						local branches=$(git -C "$REPO" branch -r 2>/dev/null | head -5 | sed 's|origin/|  └─ |')
						operation_logs="$operation_logs|$branches"
					else
						operation_logs="$operation_logs|Check repository status: cd $REPO && git status"
					fi
					((ERRORS++))
					DEP_RESULT="err"
				else
					local end_time=$(date +%s)
					local duration=$((end_time - repo_start))
					if echo "$git_output" | grep -q "Already up to date"; then
						operation_logs="$operation_logs|$REPO is up to date (${duration}s)"
					else
						operation_logs="$operation_logs|$REPO updated successfully (${duration}s)"
					fi
					# DEP_RESULT remains ok
				fi
			fi
		fi

		# Display tree structure for this dependency (with status badge)
		if [ -n "$operation_logs" ]; then
			echo "${BLUE}┌─ ${REPO}${RESET}" >&2
			IFS='|' read -ra log_lines <<<"$operation_logs"
			for log_line in "${log_lines[@]}"; do
				if [ -n "$log_line" ]; then
					git_deps_log_output "$log_line"
				fi
			done
			local dep_status_label=""
			case "$DEP_RESULT" in
			err) dep_status_label="${RED}[ERR]${RESET}" ;;
			warn) dep_status_label="${ORANGE}[WARN]${RESET}" ;;
			*) dep_status_label="${GREEN}[OK]${RESET}" ;;
			esac
			echo "${BLUE}└─ ${REPO} ${dep_status_label}${RESET}" >&2
			echo "" >&2
		fi
	done

	local total_time=$(date +%s)
	local total_duration=$((total_time - operation_start))

	if [ "$ERRORS" -eq 0 ]; then
		if [ "$TOTAL" -eq 1 ]; then
			git_deps_log_success "Dependency pull completed (${total_duration}s)"
		else
			git_deps_log_success "All $TOTAL dependencies pulled successfully (${total_duration}s)"
		fi
	else
		git_deps_log_error "Failed to pull $ERRORS out of $TOTAL dependencies"
		git_deps_log_tip "Check individual repositories for issues"
	fi

	return "$ERRORS"
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
  status [PATH...]           Shows the status of each dependency, or specific ones
  checkout [PATH]            Checks out the dependency
  pull [PATH]                Pulls (and update) dependencies
  push [PATH]                Push  (and update) dependencies
  sync [PATH]                Push and then pull dependencies
  state                      Shows the current state
  save                       Saves the current state to $GIT_DEPS_FILE
  import [PATH]              Imports dependencies from PATH=deps/

"
		;;
	add)
		shift
		git-deps-add "$@"
		;;
	status | st)
		shift
		git-deps-status "$@"
		;;
	checkout | so)
		shift
		git-deps-checkout "$@"
		;;
	pull | pl)
		shift
		git-deps-pull "$@" # Emits its own summary; avoid duplicate generic error
		;;
	push | ph)
		shift
		if ! git-deps-push "$@"; then
			git_deps_log_error "Could not push dependencies"
			git_deps_log_tip "Some dependencies may need to be manually merged with 'git pull' first."
		fi

		;;
	state | st)
		shift
		git-deps-state "$@"
		;;
	save | s)
		shift
		git-deps-save "$@"
		;;
	sync | sy)
		shift
		if git-deps-push "$@"; then
			if git-deps-pull "$@"; then
				return 0
			else
				return 1
			fi
		else
			git_deps_log_error "Could not push dependencies"
			git_deps_log_tip "Some dependencies may need to be manually merged with 'git pull' first."
		fi
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
		git_deps_log_tip "Run '$GIT_DEPS_MODE-deps help' to see available commands"
		return 1
		;;
	esac
}
# Only run the main function if the script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	git-deps "$@"
fi
# EOF
