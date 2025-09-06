#!/usr/bin/env bash
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/git-deps.sh"
source "$BASE/tests/lib-testing.sh"

# Test: T002-save
# Test `git-deps save` uses local branch and commit
#

test-start

# 1) Create a .gitdeps file with a sample repository
test-step "Create .gitdeps file with sample repository"
cat > .gitdeps << 'EOF'
test-repo	https://github.com/octocat/Hello-World.git	master	7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
EOF
test-exist ".gitdeps" "Created .gitdeps file"

# 2) Clone the repository
test-step "Clone the test repository"
if git clone https://github.com/octocat/Hello-World.git test-repo 2>/dev/null; then
    test-ok "Repository cloned successfully"
else
    test-fail "Failed to clone repository"
fi

# 3) Switch to a different branch and commit
test-step "Switch to a different branch"
if git -C test-repo checkout -b feature-branch 2>/dev/null; then
    test-ok "Switched to feature-branch"
else
    test-fail "Failed to switch to feature-branch"
fi

# Make a commit on the new branch
test-step "Make a commit on the new branch"
echo "test change" > test-repo/test.txt
git -C test-repo add test.txt
git -C test-repo commit -m "Test commit" 2>/dev/null || true
test-ok "Made a commit on feature-branch"

# 4) Run git-deps save
test-step "Run git-deps save"
if git-deps save; then
    test-ok "git-deps save succeeded"
else
    test-fail "git-deps save failed"
fi

# 5) Verify the .gitdeps file was updated with local branch and commit
test-step "Verify .gitdeps was updated with local branch"
if grep -q "feature-branch" .gitdeps; then
    test-ok ".gitdeps contains the local branch name"
else
    test-fail ".gitdeps does not contain the local branch name"
fi

test-step "Verify .gitdeps was updated with local commit"
CURRENT_COMMIT=$(git -C test-repo rev-parse HEAD)
if grep -q "$CURRENT_COMMIT" .gitdeps; then
    test-ok ".gitdeps contains the current commit hash"
else
    test-fail ".gitdeps does not contain the current commit hash"
fi

# 6) Verify the original commit is no longer in .gitdeps
test-step "Verify original commit was replaced"
if grep -q "7fd1a60b01f91b314f59955a4e4d4e80d8edf11d" .gitdeps; then
    test-fail ".gitdeps still contains the original commit hash"
else
    test-ok ".gitdeps no longer contains the original commit hash"
fi

test-end

# EOF