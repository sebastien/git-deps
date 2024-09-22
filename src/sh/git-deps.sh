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
		echo -n "no-modified"
	else
		local expected
		expected=$(git -C "$path" rev-parse "$rev" 2>/dev/null || echo -n "expected-not-found")
		local current
		current=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo -n "current-not-found")
		if [ "$expected" != "$current" ]; then
			# Is expected an ancestor of current (current is ahead)
			if git -C "$path" merge-base --is-ancestor "$expected" "$current"; then
				# TODO: We should have a force argument to proceed there
				echo -n "maybe-ahead"
			# Is current an ancestor of expected (current is behind)
			elif git -C "$path" merge-base --is-ancestor "$current" "$expected"; then
				echo -n "ok-behind"
			elif [ -z "$(git -C "$path" branch -r --contains "$current")" ]; then
				echo -n "no-unsynced"
			else
				echo -n "ok-synced"
			fi
		else
			echo -n "ok-same"
		fi
	fi
}

function git_deps_update {
	local path="$1"
	local rev="$2"
	git_log_output "up $path → $rev" "$(git -C "$path" checkout "$rev" 2>&1)"
}

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
					;;
				*)
					;;
			esac
			;;
		maybe)
			;;
		*)
			;;
	esac
	echo "${STATUS[0]} [${STATUS[1]}] $path@$rev"

}

# --
# Updates the deps file.
function git-deps-update {
	IFS=$'\n'
	for LINE in $(git_deps_read); do
		set -a FIELDS
		IFS='|' read -ra FIELDS <<<"$LINE"
		git_deps_ensure "${FIELDS[@]}"
	done
}

git-deps-update
# EOF
