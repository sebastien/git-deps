#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"

test-init "CLI Pull Tests"

function create_test_repo {
	local repo_path="$1"
	local branch="${2:-main}"

	mkdir -p "$repo_path"
	(
		cd "$repo_path" || exit 1
		git init -q
		git config user.name "Test User"
		git config user.email "test@example.com"
		echo "# Test repo" >README.md
		git add README.md
		git commit -q -m "Initial commit"

		if [ "$branch" != "main" ]; then
			git checkout -q -b "$branch"
			echo "# Branch commit" >>README.md
			git add README.md
			git commit -q -m "Branch commit"
		fi
	)
}

test-step "pull PATH only processes selected dependency"

sdk_remote="$TEST_PATH/sdk-remote"
select_remote="$TEST_PATH/select-remote"
create_test_repo "$sdk_remote" "main"
create_test_repo "$select_remote" "main"

sdk_url="file://$sdk_remote"
select_url="file://$select_remote"

test-expect-success "$BASE_PATH/bin/git-deps" add "deps/sdk" "$sdk_url" "main"
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/select.js" "$select_url" "main"

(
	cd "deps/sdk" || exit 1
	echo "Local commit not pushed" >>README.md
	git add README.md
	git commit -q -m "Unpushed local commit"
)

pull_output=$("$BASE_PATH/bin/git-deps" pull "deps/select.js" 2>&1)
test-substring "$pull_output" "deps/select.js"
if echo "$pull_output" | grep -Fq "Dependency 'deps/sdk' has unpushed commits"; then
	test-fail "pull PATH should not inspect non-selected dependency"
else
	test-ok "pull PATH skips non-selected dependencies"
fi

test-step "pull skips a dependency when confirmation is declined"
set +e
declined_output=$(printf 'n\n' | "$BASE_PATH/bin/git-deps" pull 2>&1)
declined_status=$?
set -e
if [ "$declined_status" -eq 0 ] && echo "$declined_output" | grep -Fq "Skipping deps/sdk due to user choice" && ! echo "$declined_output" | grep -Fq "Pulling deps/sdk"; then
	test-ok "Declined pull leaves the dependency untouched"
else
	test-fail "Declined pull should skip the dependency and succeed"
fi

test-step "pull PATH rejects unknown dependency path"
if invalid_output=$("$BASE_PATH/bin/git-deps" pull "deps/unknown" 2>&1); then
	test-fail "pull with unknown path should fail"
else
	test-substring "$invalid_output" "Path 'deps/unknown' is not a registered dependency"
	test-ok "Unknown dependency path is rejected"
fi

# EOF
