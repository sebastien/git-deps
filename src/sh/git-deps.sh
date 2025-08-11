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
		# Normalizes spaces as pipe `|`
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
		git_deps_log_action "Added $REPO $URL [$BRANCH] @$COMMIT"
		echo -e "$LINE" >"$GIT_DEPS_FILE"
	else
		local EXISTING=$(grep -E "$REPO[[:blank:]]" $GIT_DEPS_FILE)
		if [ -z "$EXISTING" ]; then
			git_deps_log_action "Added $REPO $URL [$BRANCH] @$COMMIT"
			echo -e "$LINE" >>"$GIT_DEPS_FILE"
		elif [ "$EXISTING" == "$LINE" ]; then
			git_deps_log_message "$REPO already registered"
		else
			local TMPFILE=$(mktemp $GIT_DEPS_FILE.XXX)
			grep -v -E "^$REPO[[:blank:]]" "$GIT_DEPS_FILE" >"$TMPFILE"
			echo -e "$LINE" >>"$TMPFILE"
			cat "$TMPFILE" >"$GIT_DEPS_FILE"
			unlink "$TMPFILE"
			git_deps_log_action "Updated $REPO $URL [$BRANCH] @$COMMIT"
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
	
	# Clone the repository
	git_deps_log_message "Cloning $repo"
	if [ "$GIT_DEPS_MODE" == "jj" ]; then
		if ! jj git clone --colocate "$repo" "$path" 2>/dev/null; then
			git_deps_log_error "Unable to clone repository: $repo"
			return 1
		fi
	else
		if ! git clone "$repo" "$path" 2>/dev/null; then
			git_deps_log_error "Unable to clone repository: $repo"
			return 1
		fi
	fi
	return 0
}

function git_deps_op_fetch {
	local path="$1"
	git -C "$path" fetch
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

# Function: git_deps_status
# Checks the status of a dependency
# Parameters:
#   path - Path to dependency
#   rev - Expected revision
# Returns: Status string (missing, ok-same, ok-behind, etc.)
function git_deps_status {
	local path="$1"
	local rev="$2"
	local modified
	# TODO: Should check for incoming
	if [ ! -e "$path" ] || [ ! -e "$path/.git" ]; then
		echo "missing"
	else
		modified="$(git_deps_op_localchanges)"
		# ` M` for modified
		# `??` for added but untracked
		if [ -n "$modified" ]; then
			echo "no-modified"
		else
			case "$(git_deps_op_identify_rev "$path" "$rev")" in
			branch)
				# TODO: We should probably not fetch all the time
				git_deps_log_action "[Fetching new commits…]"
				git_deps_op_fetch "$path"
				rev="origin/$rev"
				;;
			hash) ;;
			esac
			local expected
			expected=$(git_deps_op_commit_id "$path" "$rev" || echo "err-expected_not_found")
			local current
			current=$(git_deps_op_commit_id "$path" || echo "err-current_not_found")
			git_deps_op_status "$path" "$expected" "$current"
		fi
	fi
}

# Function: git_deps_update
# Updates a dependency to the specified revision
# Parameters:
#   path - Path to dependency
#   repo - Repository URL
#   rev - Target revision (defaults to main)
function git_deps_update {
	local path="$1"
	local repo="$2"
	local rev="${3:-main}"
	if [ -z "$path" ]; then
		git_deps_log_error "Dependency missing directory: $*"
		return 1
	elif [ -z "$repo" ]; then
		git_deps_log_error "Dependency missing repository: $*"
		return 1
	elif [ -z "$rev" ]; then
		git_deps_log_error "Dependency missing revision: $*"
		return 1
	fi
	if [ ! -e "$path" ]; then
		git_deps_log_action "Retrieving dependency: $path ← $repo [$rev]"
		git_deps_op_clone "$repo" "$path"
	fi
	set -a STATUS
	IFS='-' read -ra STATUS <<<"$(git_deps_status "$path" "$rev")"
	case "${STATUS[0]}" in
	ok)
		case "${STATUS[1]}" in
		behind)
			git_deps_update "$path" "$rev"
			echo "ok-updated"
			;;
		*)
			echo "${STATUS[0]}"
			;;
		esac
		;;
	maybe)
		git_deps_log_error "Unsupported status: ${STATUS[0]}"
		echo "err-unsupported"
		;;
	*)
		git_deps_log_error "Unsupported status: ${STATUS[0]}"
		echo "err-unsupported"
		;;
	esac

}

# --
# Outputs the status of each
function git-deps-status {
	IFS=$'\n'
	local STATUS
	for LINE in $(git_deps_read); do
		set -a FIELDS
		IFS='|' read -ra FIELDS <<<"$LINE"
		STATUS=$(git_deps_status "${FIELDS[0]}" "${FIELDS[2]}")
		echo "${FIELDS[0]} ${FIELDS[2]} $(git_deps_op_commit_id "${FIELDS[0]}") → ${STATUS} "
	done
}

function git-deps-state {
	IFS=$'\n'
	local STATUS
	for LINE in $(git_deps_read); do
		set -a FIELDS
		IFS='|' read -ra FIELDS <<<"$LINE"
		echo "${FIELDS[0]} ${FIELDS[1]} ${FIELDS[2]} ${FIELDS[3]} $(git_deps_op_commit_id "${FIELDS[0]}")"
	done
}

function git-deps-save {
	local state="$(git-deps-state "$@")"
	git_deps_log_action "Updating state: ${BOLD}$(git_deps_path)"
	git_deps_log_output_start
	echo "$state"
	git_deps_log_output_end
	git_deps_write "$state"
}

function git-deps-update {
	IFS=$'\n'
	local STATUS
	for LINE in $(git_deps_read); do
		set -a FIELDS
		IFS='|' read -ra FIELDS <<<"$LINE"
		# PATH REPO REV
		IFS='-' read -ra STATUS <<<"$(git_deps_update "${FIELDS[@]}")"
		echo "${FIELDS[0]} ${FIELDS[2]} → ${STATUS[@]}"
	done
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
	for REPO in $DEPS_PATH/*; do
		if [ -e "$REPO/.git" ]; then
			git_deps_ensure_entry "$REPO" "$(git -C "$REPO" remote get-url origin)" "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" "$(git -C "$REPO" rev-parse HEAD)"
		fi
	done

}

# Function: git-deps-pull
# Pulls and updates all dependencies from their remote repositories
# Returns: Number of errors encountered
function git-deps-pull {
	IFS=$'\n'
	local STATUS
	local FIELDS
	local ERRORS=0
	# TODO: Support filtering arguments
	echo "-----"
	git_deps_read
	echo "-----"
	for LINE in $(git_deps_read); do
		IFS='|' read -ra FIELDS <<<"$LINE"
		# PATH REPO REV
		local REPO="${FIELDS[0]}"
		local URL="${FIELDS[1]}"
		local REV="${FIELDS[2]:-main}"
		STATUS=$(git_deps_status "$REPO" "$REV")
		case "$STATUS" in
		ok-* | maybe-ahead)
			git_deps_log_action "[$REPO] Pulling ${REV} from ${URL}…"
			if ! git -C "$REPO" pull origin "$REV"; then
				git_deps_log_error "[$REPO] Pull failed"
				git_deps_log_tip "[$REPO] Maybe revision or branch ⑂${REV} does not exist in origin repository?"
				((ERRORS++))
			fi
			;;
		no-*)
			git_deps_log_error "[$REPO] Cannot merge $STATUS"
			((ERRORS++))
			# TODO: Not sure why/what we can do from there
			# TODO: Increment errors
			;;
		err-*)
			git_deps_log_error "[$REPO] Could not process due to error $STATUS"
			((ERRORS++))
			;;
		missing)
			git_deps_log_action "[$REPO] Cloning $URL@${REV}…"
			if [ ! -e "$(dirname "$REPO")" ]; then
				mkdir -p $(dirname "$REPO")
			fi
			if ! git_deps_op_clone "$URL" "$REPO"; then
				git_deps_log_error "[$REPO] Clone failed: url=$ORANGE$URL"
				git_deps_log_tip "[$REPO] Manual intervention is required to fix"
				((ERRORS++))
			elif ! git_deps_op_checkout "$REPO" "$REV"; then
				git_deps_log_error "[$REPO] Checkout failed"
				git_deps_log_tip "[$REPO] Maybe revision or branch $REV does not exist in origin repository?"
				((ERRORS++))
			fi
			;;
		*)
			git_deps_log_error "Unknown status: $STATUS"
			;;
		esac
	done
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
		echo "
Usage: $GIT_DEPS_MODE-deps <subcommand> [options]

$GIT_DEPS_MODE-deps is an alternative to submodules that keeps dependencies in
sync.

Available subcommands:
  add [-f|--force] REPO PATH [BRANCH] [COMMIT]  Add a new dependency
  status                     Shows the status of each dependency
  ensure [PATH]              Ensure the dependency is correct
  pull [PATH]                Pulls (and update) dependencies
  push [PATH]                Push  (and update) dependencies
  sync [PATH]                Push and then pull dependencies
  state                      Shows the current state
  save                       Saves the current state to $GIT_DEPS_FILE
  import [PATH]              Imports dependencies from PATH=deps/

"
		;;
	esac
}
git-deps "$@"
# …
# EOF
