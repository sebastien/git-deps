# #!/usr/bin/env bash
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/git-deps.sh"
source "$BASE/tests/lib-testing.sh"

# Test: T001-checkout
# Test `git-deps` checkout
# 

test-start

# 1) Create a .gitdeps file with a sample public github repository to clone
test-step "Create .gitdeps file with sample repository"
cat > .gitdeps << 'EOF'
test-repo	https://github.com/octocat/Hello-World.git	master	7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
EOF
test-exist ".gitdeps" "Created .gitdeps file"

# 2) Ensure that the current directory is empty (except for .gitdeps)
test-step "Verify initial directory state"
if [ -d test-repo ]; then
    test-fail "test-repo directory should not exist initially"
else
    test-ok "test-repo directory does not exist initially"
fi

# 3) Run `git-deps checkout`, ensure it succeeds
test-step "Run git-deps checkout"
if git-deps checkout; then
    test-ok "git-deps checkout succeeded"
else
    test-fail "git-deps checkout failed"
fi

# 4) Ensures that the dependency is there
test-step "Verify dependency directory exists"
test-exist "test-repo" "Dependency directory was created"
test-exist "test-repo/.git" "Dependency is a git repository"

# 5) Ensures it is on the expected branch
test-step "Verify repository is on correct branch"
CURRENT_BRANCH=$(git -C test-repo rev-parse --abbrev-ref HEAD)
test-expect "$CURRENT_BRANCH" "master" "Repository is on master branch"

# 6) Ensures it is on the expected commit
test-step "Verify repository is on correct commit"
CURRENT_COMMIT=$(git -C test-repo rev-parse HEAD)
test-expect "$CURRENT_COMMIT" "7fd1a60b01f91b314f59955a4e4d4e80d8edf11d" "Repository is on expected commit"

# 7) Run `git-deps status` and ensure the result is as expected
test-step "Verify git-deps status output"
if STATUS_OUTPUT=$(git-deps status 2>/dev/null); then
    if test-substring "$STATUS_OUTPUT" "test-repo"; then
        test-ok "Status output contains repository name"
    fi
    if test-substring "$STATUS_OUTPUT" "ok-"; then
        test-ok "Status shows repository is in good state"
    fi
    test-ok "git-deps status command executed successfully"
else
    test-fail "git-deps status command failed"
fi

test-end

# EOF

