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

function git_deps_log_action {
	local message="$*"
	echo "${BLUE} → $message$RESET" >&2
	return 0
}

function git_deps_log_message {
	local message="$*"
	echo " … $message$RESET" >&2
	return 0
}

function git_deps_log_tip {
	local message="$*"
	echo "${BLUE_LT} ✱ $message$RESET" >&2
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
	echo "${GREEN} -  OK  $message${RESET}" >&2
}

function git_deps_log_warning {
	local message="$*"
	echo "${ORANGE}/!\\ WRN $message${RESET}" >&2
	return 1
}

function git_deps_log_error {
	local message="$*"
	echo "${RED}!!! ERR $message${RESET}" >&2
	return 1
}

function git_deps_fmt_path {
	local path="$*"
	echo -n "$path"
}

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
		grep -v '#' "$GIT_DEPS_FILE" | sed 's/[[:space:]]/|/g'
		return $?
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
	echo "$content" | sed 's/|/[[:space:]]/g' >"$GIT_DEPS_FILE"
}

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

# ----------------------------------------------------------------------------
#
# GIT/JJ WRAPPER
#
# ----------------------------------------------------------------------------

function git_deps_op_clone {
	local repo="$1"
	local repo_path="$2"
	local parent
	parent="$(dirname "$repo_path")"
	if [ ! -e "$parent" ]; then
		mkdir -p "$parent"
	fi
	if ! git clone "$repo" "$repo_path"; then
		git_deps_log_error "Failed to clone dependency at: $repo_path"
		exit 1
	else
		git_deps_log_success "Dependency clone at: $repo_path"
	fi
	if [ "$GIT_DEPS_MODE" == "jj" ]; then
		if ! env -C "$repo_path" jj git init --colocate; then
			git_deps_log_warning "Failed to colocate dependency with jj at: $repo_path"
		else
			git_deps_log_message "JJ/Git colocation enabled: $repo_path"
		fi
	fi
}

function git_deps_op_fetch {
	local path="$1"
	local res=0
	git_deps_log_output_start
	git -C "$path" fetch
	res=$?
	git_deps_log_output_end
	return $res
}

function git_deps_op_checkout {
	local path="$1"
	local rev="$2"
	local res=0
	git_deps_log_output_start
	git -C "$path" checkout "$rev"
	res=$?
	git_deps_log_output_end
	return $res

}

function git_deps_op_localchanges {
	local path="$1"
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

function git_deps_op_commit_id {
	local path="$1"
	local rev="${2:-HEAD}"
	if ! git -C "$path" rev-parse "$rev" 2>/dev/null; then
		return 1
	fi
}

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

function git_deps_op_status {
	local path="$1"
	local expected="$2"
	local current="$3"
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

function git_deps_status {
	local path="$1"
	local rev="$2"
	local modified
	# TODO: Should check for incoming
	if [ ! -e "$path" ] || [ ! -e "$path/.git" ]; then
		echo "missing"
	else
		modified="$(git_deps_op_localchanges "$path")"
		# ` M` for modified
		# `??` for added but untracked
		if [ -n "$modified" ]; then
			echo "no-modified"
		else
			case "$(git_deps_op_identify_rev "$path" "$rev")" in
			branch)
				# TODO: We should probably not fetch all the time
				git_deps_log_action "[$(git_deps_fmt_path "$path")] Fetching new commits…"
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

function git_deps_update {
	local path="$1"
	local repo="$2"
	local branch="${3:-main}"
	if [ -z "$path" ]; then
		git_deps_log_error "Dependency missing directory: $*"
		return 1
	elif [ -z "$repo" ]; then
		git_deps_log_error "Dependency missing repository: $*"
		return 1
	elif [ -z "$branch" ]; then
		git_deps_log_error "Dependency missing branch: $*"
		return 1
	fi
	if [ ! -e "$path" ]; then
		git_deps_log_action "Retrieving dependency: $path ← $repo [$branch]"
		git_deps_op_clone "$repo" "$path"
	fi
	set -a STATUS
	local old_ifs="$IFS"
	IFS='-' read -ra STATUS <<<"$(git_deps_status "$path" "$branch")"
	IFS="$old_ifs"
	case "${STATUS[0]}" in
	ok)
		case "${STATUS[1]}" in
		behind)
			# FIXME: Not right!
			# git_deps_update "$path" "$branch"
			echo "ok-updated"
			;;
		same)
			echo "ok-same"
			;;
		synced)
			echo "ok-synced"
			;;
		*)
			echo "${STATUS[0]}-${STATUS[1]}"
			;;
		esac
		;;
	maybe)
		git_deps_log_error "Unsupported status: ${STATUS[0]}-${STATUS[1]}"
		echo "err-unsupported"
		;;
	*)
		git_deps_log_error "Unsupported status: ${STATUS[0]}"
		echo "err-unsupported"
		;;
	esac

}

# ----------------------------------------------------------------------------
#
# HIGH LEVEL COMMANDS
#
# ----------------------------------------------------------------------------

function git-deps-status {
	local repo_filter="${1:-}"
	local STATUS
	local old_ifs="$IFS"
	IFS=$'\n'
	for REPO in $(git_deps_list "$repo_filter"); do
		set -a FIELDS
		local temp_ifs="$IFS"
		IFS=' ' read -ra FIELDS <<<"$(git_deps_state "$REPO")"
		IFS="$temp_ifs"
		STATUS=$(git_deps_status "${FIELDS[0]}" "${FIELDS[2]}")
		echo "${BOLD}[${FIELDS[0]}]$RESET (${FIELDS[2]}) $(git_deps_op_commit_id "${FIELDS[0]}") = ${STATUS} "
	done
	IFS="$old_ifs"
}

function git-deps-checkout {
	local repo_filter="${1:-}"
	for REPO in $(git_deps_list "$repo_filter"); do
		set -a FIELDS
		read -ra FIELDS <<<"$(git_deps_state "$REPO")"
		git_deps_update "${FIELDS[0]}" "${FIELDS[1]}" "${FIELDS[2]}" "${FIELDS[3]}"
	done
}

# Commang: git-deps-state
function git-deps-state {
	# TODO: Should improve/format presentation
	git_deps_state
}

function git-deps-save {
	local args="$@"
	local state="$(git_deps_state "$args")"
	git_deps_log_action "Updating state: ${BOLD}$(git_deps_path)"
	git_deps_log_output_start
	echo "$state"
	git_deps_log_output_end
	git_deps_write "$state"
}

function git-deps-update {
	local args="$@"
	local old_ifs="$IFS"
	IFS=$'\n'
	local STATUS
	for LINE in $(git_deps_read); do
		set -a FIELDS
		local temp_ifs="$IFS"
		IFS='|' read -ra FIELDS <<<"$LINE"
		IFS="$temp_ifs"
		# PATH REPO REV
		IFS='-' read -ra STATUS <<<"$(git_deps_update "${FIELDS[@]}")"
		IFS="$temp_ifs"
		echo "${FIELDS[0]} ${FIELDS[2]} → ${STATUS[@]}"
	done
	IFS="$old_ifs"
}

function git-deps-import {
	local deps_path="${1:-deps}"
	for REPO in $deps_path/*; do
		if [ -e "$REPO/.git" ]; then
			git_deps_ensure_entry "$REPO" "$(git -C "$REPO" remote get-url origin)" "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" "$(git -C "$REPO" rev-parse HEAD)"
		fi
	done

}

function git-deps-pull {
	local args="$@"
	local old_ifs="$IFS"
	IFS=$'\n'
	local STATUS
	local FIELDS
	local ERRORS=0
	# TODO: Support filtering arguments
	echo "-----"
	git_deps_read
	echo "-----"
	for LINE in $(git_deps_read); do
		local temp_ifs="$IFS"
		IFS='|' read -ra FIELDS <<<"$LINE"
		IFS="$temp_ifs"
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
	IFS="$old_ifs"
	return $ERRORS
}

function git-deps {
	local command="$1"
	case "$command" in
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
  status                     Shows the status of each dependency
  checkout [PATH]            Checks out the dependency
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
