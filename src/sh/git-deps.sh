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
GIT_DEPS_FILE=".gitdeps"
GIT_DEPS_SOURCE="file"

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
	echo "${GREEN} → $@$RESET" >&2
	return 0
}

function git_deps_log_message {
	echo " … $@$RESET" >&2
	return 0
}

function git_deps_log_tip {
	echo "${BLUE_LT} ✱ $@$RESET" >&2
	return 0
}

function git_deps_log_output_start {
	echo -n "${BLUE_LT}"
}

function git_deps_log_output_end {
	echo -n "${RESET}"
}

# Function: git_deps_log_error
# Logs an error message in red color
# Parameters:
#   message - Error message to display
function git_deps_log_error {
	echo "${RED}!!! ERR $*${RESET}" >&2
	return 1
}

# Function: git_deps_log_warning
# Logs a warning message in orange color
# Parameters:
#   message - Warning message to display  
function git_deps_log_warning {
	echo "${ORANGE}!!! WARN $*${RESET}" >&2
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
		git_deps_log_message "Force flag set, proceeding without confirmation"
		return 0
	fi
	
	echo -n "${YELLOW}$message [y/N]: ${RESET}" >&2
	read -r response
	case "$response" in
	[yY]|[yY][eE][sS])
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

function git_deps_read_file {
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
			IFS=$'\t' read -ra fields <<< "$line"
			local field_count=${#fields[@]}
			
			# Validate field count
			if [ $field_count -lt 3 ]; then
				git_deps_log_warning "Line $line_num: incomplete entry, expected at least 3 fields (path, url, branch)"
				has_errors=true
			elif [ $field_count -gt 4 ]; then
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
		done < "$GIT_DEPS_FILE"
		
		# Normalize spaces as pipe `|` for compatibility
		cat "$GIT_DEPS_FILE" | sed 's/[[:space:]]/|/g'
		return 0
	else
		git_deps_log_error "Could not find deps file: $GIT_DEPS_FILE"
		return 1
	fi
}

function git_deps_write_file {
	echo "$@" | sed 's/|/[[:space:]]/g' >"$GIT_DEPS_FILE"
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
		local EXISTING=$(grep -E "$REPO[[:blank:]]" $GIT_DEPS_FILE)
		if [ -z "$EXISTING" ]; then
			echo -e "$LINE" >>"$GIT_DEPS_FILE"
			git_deps_log_tip "Added dependency $REPO [$BRANCH] to .gitdeps"
		elif [ "$EXISTING" == "$LINE" ]; then
			git_deps_log_message "$REPO already registered with same configuration"
		else
			local TMPFILE=$(mktemp $GIT_DEPS_FILE.XXX)
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
		git_deps_read_file
		return 0
		;;
	*)
		git_deps_log_error "Unsupported source: $GIT_DEPS_SOURCE"
		return 1
		;;
	esac
}

function git_deps_write {
	case "$GIT_DEPS_SOURCE" in
	file)
		git_deps_write_file "$@"
		return 0
		;;
	*)
		git_deps_log_error "Unsupported source: $GIT_DEPS_SOURCE"
		return 1
		;;
	esac
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
	local path="$2"
	local parent="$(dirname "$path")"
	
	# Create parent directory if it doesn't exist
	if [ ! -e "$parent" ]; then
		mkdir -p "$parent"
	fi
	
	# Clone the repository with progress logging
	git_deps_log_message "Cloning $repo (this may take a moment...)"
	
	if [ "$GIT_DEPS_MODE" == "jj" ]; then
		# Show progress for jj clone
		git_deps_log_message "Running: jj git clone --colocate"
		if ! jj git clone --colocate "$repo" "$path"; then
			git_deps_log_error "Unable to clone repository: $repo"
			return 1
		fi
	else
		# Show progress for git clone
		git_deps_log_message "Running: git clone --progress"
		if ! git clone --progress "$repo" "$path"; then
			git_deps_log_error "Unable to clone repository: $repo"
			return 1
		fi
	fi
	
	git_deps_log_message "Clone completed successfully"
	return 0
}

function git_deps_op_fetch {
	local path="$1"
	git_deps_log_message "Fetching updates (this may take a moment...)"
	if git -C "$path" fetch --progress; then
		git_deps_log_message "Fetch completed successfully"
		return 0
	else
		git_deps_log_error "Fetch failed"
		return 1
	fi
}

function git_deps_op_checkout {
	local path="$1"
	local rev="$2"
	
	# Check if it's a branch that exists
	if git -C "$path" show-ref --quiet --heads "$rev" 2>/dev/null; then
		git_deps_log_message "Checking out $rev"
		git -C "$path" checkout "$rev" 2>/dev/null
	# Check if it's a tag that exists
	elif git -C "$path" show-ref --quiet --tags "$rev" 2>/dev/null; then
		git_deps_log_message "Checking out $rev"
		git -C "$path" checkout "$rev" 2>/dev/null
	# Check if it's a valid commit
	elif git -C "$path" rev-parse --verify "$rev^{commit}" >/dev/null 2>&1; then
		git_deps_log_message "Checking out $rev"
		git -C "$path" checkout "$rev" 2>/dev/null
	else
		# Determine if it's a branch or commit that doesn't exist
		if [[ "$rev" =~ ^[a-f0-9]{7,40}$ ]]; then
			git_deps_log_error "Commit '$rev' does not exist in repository: $(git -C "$path" remote get-url origin)"
		else
			git_deps_log_error "Branch '$rev' does not exist in repository: $(git -C "$path" remote get-url origin)"
		fi
		return 1
	fi
}

# --
# Returns a non-empty string if there are local changes.
function git_deps_op_localchanges {
	if [ "$GIT_DEPS_MODE" == "jj" ]; then
		# Working copy changes:
		# A .gitdeps
		# Working copy : klywuowv ee6d952f (no description set)
		# Parent commit: zzzzzzzz 00000000 (empty) (no description set)
		jj -R "$path" status | head -n -2 | tail -n +2
	else
		git -C "$path" status --porcelain | grep -v '??'
	fi
}

# --
# Returns the (git) commit id for the current revision
function git_deps_op_commit_id {
	if ! git -C "$1" rev-parse "${2:-HEAD}" 2>/dev/null; then
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
	if git -C "$1" show-ref --quiet --heads "$2" || git -C "$1" show-ref --quiet --tags "$2"; then
		echo "branch"
	elif git -C "$1" rev-parse --verify "$2^{commit}" >/dev/null 2>&1; then
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

# --
# Takes `PATH` `EXPECTED` `CURRENT` and returns one of the following:
# - `ok-same` both repvisions are the same
# - `ok-behind` current is behind expected (can fast-forward)
# - `ok-synced`
# - `maybe-ahead` current may be ahead of behind (may need a merge)
# - `no-unsynced` current version is is not
function git_deps_op_status {
	local path="$1"
	local expected="$2"
	local current="$2"
	if [ "$expected" == "$current" ]; then
		echo "ok-same"
	elif git -C "$path" merge-base --is-ancestor "$expected" "$current"; then
		# TODO: We should have a force argument to proceed there
		echo "maybe-ahead"
	# Is current an ancestor of expected (current is behind)
	elif git -C "$path" merge-base --is-ancestor "$current" "$expected"; then
		echo "ok-behind"
	elif [ -z "$(git -C "$path" branch -r --contains "$current")" ]; then
		echo "no-unsynced"
	else
		echo "ok-synced"
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
	grep -E "^$path[[:blank:]]" "$GIT_DEPS_FILE" >/dev/null 2>&1
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
		git_deps_log_error "Usage: git-deps add REPO PATH [BRANCH] [COMMIT]"
		return 1
	fi
	
	# Check if dependency already exists (unless force is specified)
	if [ "$force" != "true" ] && git_deps_has "$path"; then
		git_deps_log_error "Dependency already registered at '$path'"
		git_deps_log_tip "Run git-deps add -f $repo $path $branch $commit"
		return 1
	fi
	
	git_deps_log_action "Adding $repo to $path"
	
	# Clone the repository
	if ! git_deps_op_clone "$repo" "$path"; then
		return 1
	fi
	
	# Checkout the specified branch or commit
	if ! git_deps_op_checkout "$path" "$branch"; then
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
	
	git_deps_log_tip "$repo[$branch] is now available in $path"
	return 0
}

# ----------------------------------------------------------------------------
#
# HIGH LEVEL COMMANDS
#
# ----------------------------------------------------------------------------

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
	local status=""
	local color=""
	
	# Check if local exists
	if [ ! -e "$path" ] || [ ! -e "$path/.git" ]; then
		status="behind"
		color="${YELLOW}"
	else
		local current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "")
		
		# Check if we can access remote
		if ! git -C "$path" ls-remote --exit-code "$repo" >/dev/null 2>&1; then
			status="unavailable"
			color="${RED}"
		elif [ -n "$commit" ] && ! git -C "$path" cat-file -e "$commit" 2>/dev/null; then
			# Check if specific commit exists
			status="missing"
			color="${RED}"
		elif [ -n "$branch" ] && ! git -C "$path" ls-remote --exit-code "$repo" "refs/heads/$branch" >/dev/null 2>&1; then
			# Check if branch exists in remote
			status="missing"
			color="${RED}"
		elif [ -n "$commit" ] && [ "$current_commit" = "$commit" ] && [ -z "$(git_deps_op_localchanges "$path")" ]; then
			# Exact match with specified commit and no local changes
			status="synced"
			color="${GREEN}"
		elif [ -z "$commit" ] && [ -z "$(git_deps_op_localchanges "$path")" ]; then
			# No specific commit specified, check against current state
			status="synced"
			color="${GREEN}"
		else
			# Check dep status against local and remote
			local remote_commit=$(git -C "$path" ls-remote "$repo" "$branch" 2>/dev/null | cut -f1)
			local dep_commit="${commit}"
			
			# If local differs from dep, show outdated
			if [ -n "$dep_commit" ] && [ "$current_commit" != "$dep_commit" ]; then
				status="outdated"
				color="${ORANGE}"
			# If dep is behind local or remote, show behind
			elif [ -n "$dep_commit" ] && [ -n "$current_commit" ]; then
				if git -C "$path" rev-parse --verify "$dep_commit" >/dev/null 2>&1; then
					if git -C "$path" merge-base --is-ancestor "$dep_commit" "$current_commit" 2>/dev/null; then
						status="behind"
						color="${YELLOW}"
					elif [ -n "$remote_commit" ] && git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
						if git -C "$path" merge-base --is-ancestor "$dep_commit" "$remote_commit" 2>/dev/null; then
							status="behind"
							color="${YELLOW}"
						else
							status="synced"
							color="${GREEN}"
						fi
					else
						status="synced"
						color="${GREEN}"
					fi
				else
					status="behind"
					color="${YELLOW}"
				fi
			else
				status="synced"
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
	local status=""
	local color=""
	
	# Check if local exists
	if [ ! -e "$path" ] || [ ! -e "$path/.git" ]; then
		status="missing"
		color="${GRAY}"
		echo "${color}${status}${RESET}"
		return
	fi
	
	local current_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "")
	local target_commit="${commit}"
	local local_changes=$(git_deps_op_localchanges "$path")
	
	# If no specific commit in dependency, use remote branch head
	if [ -z "$target_commit" ]; then
		if git -C "$path" ls-remote --exit-code "$repo" "refs/heads/$branch" >/dev/null 2>&1; then
			target_commit=$(git -C "$path" ls-remote "$repo" "$branch" 2>/dev/null | cut -f1)
		fi
	fi
	
	# Check for uncommited changes first
	if [ -n "$local_changes" ]; then
		# Check if we're also ahead of remote when uncommitted
		local remote_commit=""
		if git -C "$path" ls-remote --exit-code "$repo" "refs/heads/$branch" >/dev/null 2>&1; then
			remote_commit=$(git -C "$path" ls-remote "$repo" "$branch" 2>/dev/null | cut -f1)
		fi
		
		if [ -n "$remote_commit" ] && [ "$current_commit" != "$remote_commit" ]; then
			if git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
				if git -C "$path" merge-base --is-ancestor "$remote_commit" "$current_commit" 2>/dev/null; then
					status="ahead uncommited"
					color="${GOLD}"
				else
					status="uncommited"
					color="${GOLD}"
				fi
			else
				status="ahead uncommited"
				color="${GOLD}"
			fi
		else
			status="uncommited"
			color="${GOLD}"
		fi
	else
		# Determine base status relative to remote only (remove dep_relation logic)
		local remote_relation=""
		
		# Check relationship with remote
		local remote_commit=""
		if git -C "$path" ls-remote --exit-code "$repo" "refs/heads/$branch" >/dev/null 2>&1; then
			remote_commit=$(git -C "$path" ls-remote "$repo" "$branch" 2>/dev/null | cut -f1)
		fi
		
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
				status="behind"; 
				color="${YELLOW}" ;;
			ahead) 
				status="ahead"; 
				color="" ;;
			conflict) 
				status="conflict"; 
				color="${RED}" ;;
			*)
				# Everything matches
				status="synced"
				color="${GREEN}" ;;
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
	local status=""
	local color=""
	
	# Check if remote is accessible
	if ! git ls-remote --exit-code "$repo" >/dev/null 2>&1; then
		status="unavailable"
		color="${GRAY}"
		echo "${color}${status}${RESET}"
		return
	fi
	
	# Check if branch/commit exists in remote
	if [ -n "$branch" ] && ! git ls-remote --exit-code "$repo" "refs/heads/$branch" >/dev/null 2>&1; then
		status="missing"
		color="${RED}"
		echo "${color}${status}${RESET}"
		return
	fi
	
	# Get remote commit
	local remote_commit=""
	if [ -n "$branch" ]; then
		remote_commit=$(git ls-remote "$repo" "refs/heads/$branch" 2>/dev/null | cut -f1)
	fi
	
	if [ -z "$remote_commit" ]; then
		status="missing"
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
				status="synced"
				color="${GREEN}"
			# Check if we can resolve remote commit in local repo
			elif git -C "$path" rev-parse --verify "$remote_commit" >/dev/null 2>&1; then
				if git -C "$path" merge-base --is-ancestor "$remote_commit" "$local_commit" 2>/dev/null; then
					# Remote is ancestor of local - remote is behind
					status="behind"
					color="${YELLOW}"
				elif git -C "$path" merge-base --is-ancestor "$local_commit" "$remote_commit" 2>/dev/null; then
					# Local is ancestor of remote - remote is ahead
					status="ahead"
					color=""
				else
					# Diverged - remote has different commits
					status="ahead"
					color=""
				fi
			else
				# Remote commit not in local - remote is ahead
				status="ahead"
				color=""
			fi
		else
			status="ahead"
			color=""
		fi
	elif [ -n "$dep_commit" ] && [ "$remote_commit" = "$dep_commit" ]; then
		# If no local path but remote matches dependency commit
		status="synced"
		color="${GREEN}"
	else
		status="ahead"
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
	local rev="${3:-main}"
	local commit="$4"
	local force="${5:-false}"
	
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

# Function: git-deps-status
# Outputs the status of each dependency in the new format with dates
function git-deps-status {
	IFS=$'\n'
	local TOTAL=0
	local CURRENT=0
	
	git_deps_log_action "Checking dependency status"
	
	# Count total dependencies
	for LINE in $(git_deps_read); do
		((TOTAL++))
	done
	
	if [ $TOTAL -eq 0 ]; then
		git_deps_log_tip "No dependencies found in .gitdeps"
		return 0
	fi
	
	git_deps_log_message "Analyzing $TOTAL dependencies..."
	
	for LINE in $(git_deps_read); do
		((CURRENT++))
		set -a FIELDS
		IFS='|' read -ra FIELDS <<<"$LINE"
		local path="${FIELDS[0]}"
		local repo="${FIELDS[1]}"  
		local branch="${FIELDS[2]}"
		local commit="${FIELDS[3]:-}"
		
		git_deps_log_message "[$CURRENT/$TOTAL] Analyzing dependency: $path"
		
		# Get commit IDs and dates
		local dep_commit="${commit}"
		local local_commit=$(git_deps_op_commit_id "$path" 2>/dev/null || echo "unknown")
		local remote_commit=""
		if [ -e "$path/.git" ]; then
			git_deps_log_message "Checking remote status for $path..."
			remote_commit=$(git -C "$path" ls-remote "$repo" "$branch" 2>/dev/null | cut -f1 | head -1 || echo "unknown")
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
				git_deps_log_message "Fetching commit info for date calculation..."
				if git -C "$path" fetch origin >/dev/null 2>&1; then
					remote_date=$(git_deps_op_commit_date "$path" "$remote_commit" 2>/dev/null || echo "")
				fi
			fi
		fi
		
		# Calculate status for each component
		local dep_status=$(git_deps_status_dep "$path" "$repo" "$branch" "$commit")
		local local_status=$(git_deps_status_local "$path" "$repo" "$branch" "$commit") 
		local remote_status=$(git_deps_status_remote "$repo" "$branch" "$commit" "$path")
		
		# Output in the new format with dates
		git_deps_log_tip "$path"
		echo " … │ dep      [$branch] ${dep_commit:-$local_commit} $dep_status ${dep_date}"
		
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
		echo " … │ local    [$branch] ${local_commit:-unknown} $local_status ${local_date}$local_ahead"
		
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
		echo " … │ remote   [$branch] ${remote_commit:-unknown} $remote_status ${remote_date}$remote_ahead"
	done
	
	git_deps_log_message "Status check completed"
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
		echo "${FIELDS[0]} ${FIELDS[1]} ${FIELDS[2]} ${FIELDS[3]} $(git_deps_op_commit_id "${FIELDS[0]}" 2>/dev/null || echo "unknown")"
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
	
	if [ $count -eq 0 ]; then
		git_deps_log_message "No dependencies to save"
		git_deps_log_tip "Use 'git-deps add' to add dependencies first"
		return 0
	fi
	
	git_deps_log_message "Recording $count dependency states to $GIT_DEPS_FILE"
	
	if git_deps_write "$state"; then
		git_deps_log_tip "Dependency state saved successfully"
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
	
	git_deps_log_message "Processing $TOTAL dependencies..."
	
	for LINE in $(git_deps_read); do
		((CURRENT++))
		set -a FIELDS
		IFS='|' read -ra FIELDS <<<"$LINE"
		# PATH REPO REV
		git_deps_log_message "[$CURRENT/$TOTAL] Updating ${FIELDS[0]} [${FIELDS[2]}]"
		IFS='-' read -ra STATUS <<<"$(git_deps_update "${FIELDS[@]}")"
		case "${STATUS[0]}" in
		ok)
			git_deps_log_tip "${FIELDS[0]} → ${STATUS[@]}"
			;;
		err)
			((ERRORS++))
			;;
		*)
			echo "${FIELDS[0]} ${FIELDS[2]} → ${STATUS[@]}"
			;;
		esac
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
		-f|--force)
			force="true"
			shift
			;;
		*)
			if [ -z "$repo" ]; then
				repo="$1"
			elif [ -z "$path" ]; then
				path="$1"
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
	
	for REPO in "$DEPS_PATH"/*; do
		if [ -e "$REPO/.git" ]; then
			((count++))
			git_deps_log_message "Processing $(basename "$REPO")"
			
			local url=$(git -C "$REPO" remote get-url origin 2>/dev/null || echo "unknown")
			local branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
			local commit=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo "unknown")
			
			if [ "$url" != "unknown" ] && [ "$commit" != "unknown" ]; then
				git_deps_ensure_entry "$REPO" "$url" "$branch" "$commit"
				((processed++))
			else
				git_deps_log_error "Could not read repository info for $REPO"
			fi
		fi
	done
	
	if [ $count -eq 0 ]; then
		git_deps_log_tip "No git repositories found in $DEPS_PATH"
	elif [ $processed -eq $count ]; then
		git_deps_log_tip "Successfully imported $processed dependencies"
	else
		git_deps_log_error "Imported $processed out of $count repositories"
		git_deps_log_tip "Check failed repositories for valid git remotes"
		return 1
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
		-f|--force)
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
	
	git_deps_log_message "Processing $TOTAL dependencies..."
	
	for LINE in $(git_deps_read); do
		((CURRENT++))
		IFS='|' read -ra FIELDS <<<"$LINE"
		# PATH REPO REV
		local REPO="${FIELDS[0]}"
		local URL="${FIELDS[1]}"
		local REV="${FIELDS[2]:-main}"
		
		git_deps_log_message "[$CURRENT/$TOTAL] Processing $REPO"
		
		# Check for unpushed commits and ask for confirmation
		if [ -e "$REPO/.git" ] && git_deps_op_has_unpushed_commits "$REPO"; then
			if ! git_deps_confirm "Dependency '$REPO' has unpushed commits. Continue pulling?" "$force"; then
				git_deps_log_message "Skipping $REPO due to user choice"
				continue
			fi
		fi
		
		STATUS=$(git_deps_status "$REPO" "$REV")
		case "$STATUS" in
		ok-same)
			git_deps_log_message "$REPO is already up to date"
			;;
		ok-* | maybe-ahead)
			git_deps_log_message "Pulling $REPO [$REV] (this may take a moment...)"
			if ! git -C "$REPO" pull origin "$REV" 2>/dev/null; then
				git_deps_log_error "Pull failed for $REPO"
				git_deps_log_tip "Branch '$REV' may not exist in repository: $URL"
				((ERRORS++))
			else
				git_deps_log_tip "$REPO [$REV] updated successfully"
			fi
			;;
		no-*)
			git_deps_log_error "Cannot pull $REPO: $STATUS"
			git_deps_log_tip "Manual intervention required - check for local changes"
			((ERRORS++))
			;;
		err-*)
			git_deps_log_error "Could not process $REPO: $STATUS"
			((ERRORS++))
			;;
		missing)
			git_deps_log_message "[$CURRENT/$TOTAL] Cloning $URL (this may take a moment...)"
			git_deps_log_message "Checking out $REV"
			if [ ! -e "$(dirname "$REPO")" ]; then
				mkdir -p "$(dirname "$REPO")"
			fi
			if ! git_deps_op_clone "$URL" "$REPO"; then
				git_deps_log_error "Unable to clone repository: $URL"
				((ERRORS++))
			elif ! git_deps_op_checkout "$REPO" "$REV"; then
				((ERRORS++))
			else
				git_deps_log_tip "$URL[$REV] is now available in $REPO"
			fi
			;;
		*)
			git_deps_log_error "Unknown status for $REPO: $STATUS"
			((ERRORS++))
			;;
		esac
	done
	
	if [ $ERRORS -eq 0 ]; then
		git_deps_log_tip "All dependencies pulled successfully"
	else
		git_deps_log_error "Failed to pull $ERRORS out of $TOTAL dependencies"
	fi
	
	return $ERRORS
}

# Function: git-deps
# Main entry point for git-deps commands
# Parameters:
#   subcommand - Command to execute (status, pull, push, etc.)
#   ... - Additional arguments passed to subcommand
function git-deps {
	case "$1" in
	add | a)
		shift
		git-deps-add "$@"
		;;
	status | st)
		shift
		git-deps-status "$@"
		;;
	pull | pl)
		shift
		if ! git-deps-pull "$@"; then
			git_deps_log_error "Could not pull dependencies"
			git_deps_log_tip "Some dependencies may need to be manually merged with 'git pull'"
		fi
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
		# TODO: each?
		cat <<EOF
Usage: $GIT_DEPS_MODE-deps <subcommand> [options]

$GIT_DEPS_MODE-deps is an alternative to submodules that keeps dependencies in
sync.

Available subcommands:
  add [-f|--force] REPO PATH [BRANCH] [COMMIT]  Add a new dependency
  status                     Shows the status of each dependency
  ensure [PATH]              Ensure the dependency is correct
  pull [PATH]                Pulls and update dependencies
  push [PATH]                Push and update dependencies
  sync [PATH]                Push and then pull dependencies
  state                      Shows the current state
  save                       Saves the current state to $GIT_DEPS_FILE
  import [PATH]              Imports dependencies from PATH=deps/

EOF
		;;
	esac
}
git-deps "$@"
# …
# EOF
