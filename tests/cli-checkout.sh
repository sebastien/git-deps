#!/usr/bin/env bash
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/git-deps.sh"
source "$BASE/tests/lib-testing.sh"

# Test: T001-checkout
# Test `git-deps` checkout with the new local-only semantics
#

# IMPORTANT: Under the new semantics, checkout is local-only (no network).
# To checkout to a pinned commit, you must first run `git-deps update --pinned`
# to fetch the commit from remote.

test-start

# 1) Create a .gitdeps file with a sample public github repository
# NOTE: We use a branch without a pinned commit so checkout can work locally
test-step "Create .gitdeps file with sample repository"
cat >.gitdeps <<'EOF'
test-repo	https://github.com/octocat/Hello-World.git	master
EOF
test-exist ".gitdeps" "Created .gitdeps file"

# 2) Ensure that the current directory is empty (except for .gitdeps)
test-step "Verify initial directory state"
if [ -d test-repo ]; then
	test-fail "test-repo directory should not exist initially"
else
	test-ok "test-repo directory does not exist initially"
fi

# 3) First run `git-deps update` to clone and fast-forward to latest
# (this is the network operation that fetches from remote)
test-step "Run git-deps update to fetch dependency"
if git-deps update; then
	test-ok "git-deps update succeeded"
else
	test-fail "git-deps update failed"
fi

# 4) Run `git-deps checkout` - should be no-op since already at correct state
test-step "Run git-deps checkout (should be no-op)"
if git-deps checkout; then
	test-ok "git-deps checkout succeeded"
else
	test-fail "git-deps checkout failed"
fi

# 5) Ensures the dependency is there
test-step "Verify dependency directory exists"
test-exist "test-repo" "Dependency directory was created"
test-exist "test-repo/.git" "Dependency is a git repository"

# 6) Ensures it is on the expected branch
test-step "Verify repository is on correct branch"
CURRENT_BRANCH=$(git -C test-repo rev-parse --abbrev-ref HEAD)
test-expect "$CURRENT_BRANCH" "master" "Repository is on master branch"

# 7) Run `git-deps status` and ensure the result is as expected
test-step "Verify git-deps status output"
if STATUS_OUTPUT=$(git-deps status 2>/dev/null); then
	if test-substring "$STATUS_OUTPUT" "test-repo"; then
		test-ok "Status output contains repository name"
	fi
	if test-substring "$STATUS_OUTPUT" "SYNCED"; then
		test-ok "Status shows repository is in good state"
	fi
	test-ok "git-deps status command executed successfully"
else
	test-fail "git-deps status command failed"
fi

test-end

# EOF
