#!/usr/bin/env bash

# Test cases for new git-deps semantics
# - checkout: local-only, aligns to .gitdeps
# - update: fetches latest, fails on uncommitted/unpushed changes unless --force

source "$(dirname "$0")/lib-testing.sh"

test-init "Integration Confirmation Tests"

# Helper function to create a test git repo
# Uses git -C to avoid changing working directory
create_test_repo() {
    local repo_path="$1"
    local branch="${2:-main}"
    
    mkdir -p "$repo_path"
    git -C "$repo_path" init -q
    git -C "$repo_path" config user.name "Test User"
    git -C "$repo_path" config user.email "test@example.com"
    echo "# Test repo" > "$repo_path/README.md"
    git -C "$repo_path" add README.md
    git -C "$repo_path" commit -q -m "Initial commit"
    
    if [ "$branch" != "main" ]; then
        git -C "$repo_path" checkout -q -b "$branch"
        echo "# Feature branch" >> "$repo_path/README.md"
        git -C "$repo_path" add README.md
        git -C "$repo_path" commit -q -m "Feature commit"
    fi
}

# Helper to create remote repo with additional commits
# Uses git -C to avoid changing working directory
create_remote_with_history() {
    local repo_path="$1"
    create_test_repo "$repo_path"
    # Add more commits to simulate remote changes
    echo "Remote change 1" >> "$repo_path/README.md"
    git -C "$repo_path" add README.md
    git -C "$repo_path" commit -q -m "Remote change 1"
    
    echo "Remote change 2" >> "$repo_path/README.md"
    git -C "$repo_path" add README.md
    git -C "$repo_path" commit -q -m "Remote change 2"
}

# Test 1: Update with unpushed commits should fail
test-step "Test 1: Update fails with unpushed commits"
remote_repo="$TEST_PATH/remote-repo"
create_remote_with_history "$remote_repo"
remote_url="file://$remote_repo"
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/remote" "$remote_url" "main"

# Make local changes and commit them (but don't push)
echo "Local committed change" >> "$TEST_PATH/deps/remote/README.md"
git -C "$TEST_PATH/deps/remote" add README.md
git -C "$TEST_PATH/deps/remote" commit -q -m "Local committed change"

# Add more commits to remote to create divergence
echo "More remote changes" >> "$remote_repo/README.md"
git -C "$remote_repo" add README.md
git -C "$remote_repo" commit -q -m "More remote changes"

# Update should fail with error about unpushed changes
set +e
UPDATE_OUTPUT=$("$BASE_PATH/bin/git-deps" update 2>&1)
UPDATE_EXIT=$?
set -e
if [ $UPDATE_EXIT -ne 0 ] && echo "$UPDATE_OUTPUT" | grep -qi "unpushed"; then
    test-ok "Update fails with unpushed commits error"
else
    test-fail "Should have failed with unpushed commits error (exit=$UPDATE_EXIT)"
fi

# Test 2: Update with --force should attempt to proceed
test-step "Test 2: Update with --force flag"
test-expect-failure "$BASE_PATH/bin/git-deps" update --force
test-ok "Update attempts to proceed with --force but fails on divergence"

# Test 3: Update with non-existent branch should fail
test-step "Test 3: Update fails with non-existent branch"
limited_repo="$TEST_PATH/limited-repo"
create_test_repo "$limited_repo" "main"
limited_url="file://$limited_repo"
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/limited" "$limited_url" "main"

# Try to update .gitdeps to reference a branch that doesn't exist in remote
echo -e "deps/limited\t$limited_url\tfeature-branch\tabc123" > .gitdeps

set +e
UPDATE_OUTPUT=$("$BASE_PATH/bin/git-deps" update 2>&1)
set -e
if echo "$UPDATE_OUTPUT" | grep -qi "clone\|err-clone"; then
    test-ok "Update fails with missing branch error"
else
    test-fail "Should have failed with clone error"
fi

# Test 4: Update with uncommitted changes should fail
test-step "Test 4: Update fails with uncommitted changes"
clean_repo="$TEST_PATH/clean-repo"
create_test_repo "$clean_repo"
clean_url="file://$clean_repo"
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/clean" "$clean_url" "main"

# Make local uncommitted changes
echo "Uncommitted local changes" >> "$TEST_PATH/deps/clean/README.md"

set +e
UPDATE_OUTPUT=$("$BASE_PATH/bin/git-deps" update 2>&1)
set -e
if echo "$UPDATE_OUTPUT" | grep -qi "uncommitted changes"; then
    test-ok "Update fails with uncommitted changes error"
else
    test-fail "Should have failed with uncommitted changes error"
fi

# Test 5: Remove command not implemented
test-step "Test 5: Remove command not implemented"
remove_repo="$TEST_PATH/remove-repo" 
create_test_repo "$remove_repo"
remove_url="file://$remove_repo"
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/to-remove" "$remove_url" "main"
test-expect-failure "$BASE_PATH/bin/git-deps" remove "deps/to-remove"
test-ok "Remove command returns error as expected"

# Test 6: Checkout should clone missing dependencies
test-step "Test 6: Checkout clones missing dependencies"
checkout_repo="$TEST_PATH/checkout-repo"
create_test_repo "$checkout_repo"
checkout_url="file://$checkout_repo"
echo -e "deps/checkout\t$checkout_url\tmain" > .gitdeps

if [ -d "deps/checkout" ]; then
    test-fail "deps/checkout should not exist before checkout"
fi
test-expect-success git-deps checkout
test-exist "deps/checkout" "Checkout clones missing dependency"
test-exist "deps/checkout/.git" "Checkout creates git repository"

# Test 7: Checkout should be no-op when already at correct state
test-step "Test 7: Checkout is no-op when already correct"
test-expect-success git-deps checkout
test-ok "Checkout succeeds when already at correct state"

test-end
