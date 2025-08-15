#!/usr/bin/env bash

# Test cases that should fail with an error and non-zero exit code

source "$(dirname "$0")/lib-testing.sh"

test-init "Integration Error Tests"

# Helper function to create a test git repo
create_test_repo() {
    local repo_path="$1"
    local branch="${2:-main}"
    
    mkdir -p "$repo_path"
    cd "$repo_path"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "# Test repo" > README.md
    git add README.md
    git commit -q -m "Initial commit"
    
    if [ "$branch" != "main" ]; then
        git checkout -q -b "$branch"
        echo "# Feature branch" >> README.md
        git add README.md
        git commit -q -m "Feature commit"
    fi
}

test-step "Error: Trying to add an already existing dependency"

# Create test repo
repo_url="file://$TEST_PATH/test-repo"
create_test_repo "$TEST_PATH/test-repo"

# Add dependency first time (should succeed)
test-expect-success "$BASE_PATH/bin/git-deps" add "$repo_url" "deps/test-repo" "main"
test-ok "First add should succeed"

# Try to add same dependency again (should fail)
test-expect-failure "$BASE_PATH/bin/git-deps" add "$repo_url" "deps/test-repo" "main"
test-ok "Second add should fail with error"

# Force add should succeed
test-expect-success "$BASE_PATH/bin/git-deps" add -f "$repo_url" "deps/test-repo" "main" 
test-ok "Force add should succeed"

test-step "Error: Trying to pull a branch that doesn't exist"

# Create repo with only main branch
another_repo_url="file://$TEST_PATH/another-repo"
create_test_repo "$TEST_PATH/another-repo" "main"

# Try to add dependency with non-existent branch
test-expect-failure "$BASE_PATH/bin/git-deps" add "$another_repo_url" "deps/another" "nonexistent-branch"
test-ok "Adding non-existent branch should fail"

test-step "Error: Trying to pull a commit that doesn't exist"

# Try to add dependency with invalid commit hash
test-expect-failure "$BASE_PATH/bin/git-deps" add "$another_repo_url" "deps/another" "main" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
test-ok "Adding non-existent commit should fail"

test-step "Error: Trying to pull a dependency that has local changes"

# First, add a clean dependency
clean_repo_url="file://$TEST_PATH/clean-repo"  
create_test_repo "$TEST_PATH/clean-repo"
test-expect-success "$BASE_PATH/bin/git-deps" add "$clean_repo_url" "deps/clean" "main"

# Make local changes in the dependency
cd "deps/clean"
echo "Local changes" >> README.md
git add README.md
git commit -q -m "Local changes"
cd "$TEST_PATH"

# Now try to pull - should fail due to local changes
test-expect-failure "$BASE_PATH/bin/git-deps" pull
test-ok "Pull with local committed changes should fail"

test-step "Error: Invalid repository URL"

# Try to add dependency with invalid URL
test-expect-failure "$BASE_PATH/bin/git-deps" add "https://invalid.example.com/nonexistent.git" "deps/invalid" "main"
test-ok "Adding invalid repository URL should fail"

test-step "Error: Missing required arguments"

# Try add command with missing arguments
test-expect-failure "$BASE_PATH/bin/git-deps" add
test-ok "Add without arguments should fail"

test-expect-failure "$BASE_PATH/bin/git-deps" add "$repo_url"
test-ok "Add with only repo URL should fail"

test-step "Error: Invalid path for dependency"

# Try to add dependency to invalid/protected path
test-expect-failure "$BASE_PATH/bin/git-deps" add "$repo_url" "/" "main"
test-ok "Adding to root path should fail"

test-expect-failure "$BASE_PATH/bin/git-deps" add "$repo_url" "/invalid/path" "main"
test-ok "Adding to protected path should fail"

test-step "Error: Corrupted .gitdeps file"

# Create completely corrupted .gitdeps
echo -e "garbage\x00\x01\x02binary-data" > .gitdeps
test-expect-failure "$BASE_PATH/bin/git-deps" status
test-ok "Corrupted .gitdeps should cause error"

test-step "Error: Repository access denied"

# Create a repo and then make it inaccessible 
restricted_repo="$TEST_PATH/restricted-repo"
create_test_repo "$restricted_repo"
chmod 000 "$restricted_repo"

test-expect-failure "$BASE_PATH/bin/git-deps" add "file://$restricted_repo" "deps/restricted" "main"
test-ok "Inaccessible repository should fail"

# Restore permissions for cleanup
chmod 755 "$restricted_repo" 2>/dev/null || true

test-end