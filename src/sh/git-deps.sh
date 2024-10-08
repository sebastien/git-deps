#!/usr/bin/env bash

GIT_DEPS_FILE=".gitdeps"
GIT_DEPS_SOURCE="file"

function git_deps_log_mark {
	# Save cursor position
	echo -en '\033[s'
}

function git_deps_log_clear {
	# Clear
	echo -en '\033[1G\033[K'
	echo -en '\033[u'
}

function git_deps_log_action {
	echo "$@" >/dev/stdout
	return 0
}

function git_deps_log_message {
	echo "$@" >/dev/stdout
	return 0
}

function git_deps_log_tip {
	echo "$@" >/dev/stdout
	return 0
}

function git_log_output {
	echo "$1"
	shift
	while IFS= read -r line; do
		echo " » $line"
	done <<< "$*"
}

function git_deps_log_error {
	echo "!!! ERR $*" >/dev/stderr
	return 1
}

function git_deps_path () {
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
		sed 's/[[:space:]]\+/|/g' < "$GIT_DEPS_FILE" 
		return 0
	else
		return 1
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


function git_identify_rev {
	if git show-ref --quiet --heads "$1" || git show-ref --quiet --tags "$1"; then
		echo "branch"
	elif git rev-parse --verify "$1^{commit}" >/dev/null 2>&1; then
		echo "hash"
	else
		echo "unknown"
	fi
}

function git_deps_status {
	local path="$1"
	local rev="$2"
	local modified
	# TODO: Should check for incoming
	if [ ! -e "$path" ] || [ ! -e "$path/.git" ]; then
		echo "missing"
	else
		modified="$(git -C "$path" status --porcelain | grep -v '??')"
		# ` M` for modified
		# `??` for added but untracked
		if [ -n "$modified" ]; then
			echo "no-modified"
		else
			case "$(git_identify_rev "$rev")" in
				branch)
					# TODO: We should probably not fetch all the time
					git_deps_log_mark
					git_deps_log_action "[Fetching new commits…]"
					git -C "$path" fetch
					git_deps_log_clear
					rev="origin/$rev"
					;;
				hash)
					;;
			esac
			local expected
			expected=$(git -C "$path" rev-parse "$rev" 2>/dev/null || echo "err-expected_not_found")
			local current
			current=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "err-current_not_found")
			if [ "$expected" != "$current" ]; then
				# Is expected an ancestor of current (current is ahead)
				if git -C "$path" merge-base --is-ancestor "$expected" "$current"; then
					# TODO: We should have a force argument to proceed there
					echo  "maybe-ahead"
				# Is current an ancestor of expected (current is behind)
				elif git -C "$path" merge-base --is-ancestor "$current" "$expected"; then
					echo "ok-behind"
				elif [ -z "$(git -C "$path" branch -r --contains "$current")" ]; then
					echo "no-unsynced"
				else
					echo "ok-synced"
				fi
			else
				echo "ok-same"
			fi
		fi
	fi
}

# --
# Ensures that the given PATH is checked out at the REPO revision.
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
		git clone "$repo" "$path"
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
		echo "${FIELDS[0]} ${FIELDS[2]} ${STATUS} "
	done
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

# --
# Updates the deps pull.
function git-deps-pull {
	IFS=$'\n'
	local STATUS
	local FIELDS
	local ERRORS=0
	for LINE in $(git_deps_read); do
		IFS='|' read -ra FIELDS <<<"$LINE"
		echo "$LINE"
		# PATH REPO REV
		local REPO="${FIELDS[0]}"
		local URL="${FIELDS[1]}"
		local REV="${FIELDS[2]}"
		STATUS=$(git_deps_status "$REPO" "$REV")
		echo "$STATUS"
		case "$STATUS" in
			ok-*|maybe-ahead)
				git_deps_log_action "[$REPO] Pulling $REV…"
				if ! git -C "$REPO" pull origin "$REV"; then
					git_deps_log_error "$REPO: Pull failed"
					git_deps_log_tip "$REPO: Manual intervention is required to fix"
					((ERRORS++))
				fi
				;;
			no-*)
				git_deps_log_error "[$REPO] Cannot merge"
				((ERRORS++))
				# TODO: Not sure why/what we can do from there
				# TODO: Increment errors
				;;
			err-*)
				git_deps_log_error "$REPO: Could not process due to error $STATUS"
				((ERRORS++))
				;;
			missing)
				git_deps_log_action "[$REPO] Cloning $URL@$REV…"
				if [ ! -e "$(dirname "$REPO")" ]; then
					mkdir -p $(dirname "$REPO")
				fi
				if ! git clone "$URL" "$REPO"; then
					git_deps_log_error "$REPO: Clone failed"
					git_deps_log_tip "$REPO: Manual intervention is required to fix"
					((ERRORS++))
				elif ! git -C "$REPO" checkout "$REV"; then
					git_deps_log_error "$REPO: Checkout failed"
					git_deps_log_tip "$REPO: Manual intervention is required to fix"
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

function git-deps {
	case "$1" in 
		status|st)
			shift
			git-deps-status "$@"
			;;
		pull|pl)
			shift
			if ! git-deps-pull "$@"; then
				git_deps_log_error "Could not pull dependencies"
				git_deps_log_tip "Some dependencies may need to be manually merged with 'git pull'"
			fi
			;;
		push|ph)
			shift
			if ! git-deps-push "$@"; then
				git_deps_log_error "Could not push dependencies"
				git_deps_log_tip "Some dependencies may need to be manually merged with 'git pull' first."
			fi

			;;
		sync|sy)
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
		update|up)
			shift
			git-deps-update "$@"
			;;

		*)
			# TODO: each?
			echo '
Usage: git deps <subcommand> [options]

git-deps is an alternative to git-submodules that keeps dependencies in
sync.

Available subcommands:
  status                     Shows the status of each dependency
  ensure [PATH]              Ensure the dependency is correct
  pull [PATH]                Pulls (and update) dependencies
  push [PATH]                Push  (and update) dependencies
  sync [PATH]                Push and then pull dependencies

'
	;;
	esac
}
git-deps "$@"
# EOF
