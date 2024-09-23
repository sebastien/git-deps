#!/usr/bin/env bash

GIT_DEPS_FILE=".gitdeps"
GIT_DEPS_SOURCE="file"

function git_deps_log_action {
	echo "--> $@" >/dev/stdout
	return 0
}

function git_deps_log_message {
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

function git_deps_read_file {
	if [ -e "$GIT_DEPS_FILE" ]; then
		cat "$GIT_DEPS_FILE"
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
# function git_deps_status {
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
	modified="$(git -C "$path" status --porcelain | grep -v '??')"
	# ` M` for modified
	# `??` for added but untracked
	if [ -n "$modified" ]; then
		echo "no-modified"
	else
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
}

function git_deps_update {
	local path="$1"
	local rev="$2"
	git_log_output "up $path → $rev" "$(git -C "$path" checkout "$rev" 2>&1)"
}

# --
# Ensures that the given PATH is checked out at the REPO revision.
function git_deps_ensure {
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

# --
# Updates the deps file.
function git-deps-ensure {
	IFS=$'\n'
	local STATUS
	for LINE in $(git_deps_read); do
		set -a FIELDS
		IFS='|' read -ra FIELDS <<<"$LINE"
		# PATH REPO REV
		IFS='-' read -ra STATUS <<<"$(git_deps_ensure "${FIELDS[@]}")"
		echo "${FIELDS[0]} ${FIELDS[2]} → ${STATUS[@]}"
	done
}

function git-deps {
	case "$1" in 
		status|st)
			shift
			git-deps-status "$@"
			;;
		pull|pl)
			shift
			git-deps-pull "$@"
			;;
		ensure|en|checkout|co)
			shift
			git-deps-ensure "$@"
			;;

		*)
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
