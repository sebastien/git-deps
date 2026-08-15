#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"

test-init "Checkout --missing preserves existing dependencies"

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

test-step "check out an initial dependency"
repo="$TEST_PATH/repo-missing"
create_test_repo "$repo"

cat >.gitdeps <<EOF
deps/present	file://$repo	main
deps/absent	file://$repo	main
EOF

test-expect-success "$BASE_PATH/bin/git-deps" checkout "deps/present"
test-exist "deps/present/.git" "Present dependency was checked out"

test-step "make the present dependency diverge and dirty"
(
	cd deps/present
	git checkout -q -b feature
	echo "Uncommitted change" >>README.md
)

checkout_output=$(NO_COLOR=1 "$BASE_PATH/bin/git-deps" checkout 2>&1)
if [ -n "$checkout_output" ]; then
	test-ok "plain checkout completes with a dirty diverged dependency"
else
	test-fail "plain checkout should report a dirty diverged dependency"
fi

test-step "checkout --missing leaves existing checkouts untouched"
missing_output=$("$BASE_PATH/bin/git-deps" checkout --missing 2>&1)
test-substring "$missing_output" "Already present, skipped"

branch=$(git -C deps/present rev-parse --abbrev-ref HEAD)
test-expect "$branch" "feature" "Existing dependency keeps its branch"
if grep -q "Uncommitted change" deps/present/README.md; then
	test-ok "Existing dependency keeps its local changes"
else
	test-fail "Existing dependency lost its local changes"
fi

test-step "checkout --missing still clones absent dependencies"
test-exist "deps/absent/.git" "Absent dependency was cloned"
absent_branch=$(git -C deps/absent rev-parse --abbrev-ref HEAD)
test-expect "$absent_branch" "main" "Absent dependency was checked out"

# EOF
