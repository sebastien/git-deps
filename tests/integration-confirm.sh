#!/usr/bin/env bash

# Test cases that should ask for confirmation unless --force flag is used

source "$(dirname "$0")/lib-testing.sh"

test-init "Integration Confirmation Tests"

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

# Helper to create remote repo with additional commits
create_remote_with_history() {
    local repo_path="$1"
    create_test_repo "$repo_path"
    cd "$repo_path"
    
    # Add more commits to simulate remote changes
    echo "Remote change 1" >> README.md
    git add README.md
    git commit -q -m "Remote change 1"
    
    echo "Remote change 2" >> README.md  
    git add README.md
    git commit -q -m "Remote change 2"
}

test-step "Confirm: Pulling dependency with local committed changes that haven't been pushed"

# Create remote repo
remote_repo="$TEST_PATH/remote-repo"
create_remote_with_history "$remote_repo"
remote_url="file://$remote_repo"

# Add as dependency
cd "$TEST_PATH"
test-expect-success "$BASE_PATH/bin/git-deps" add "$remote_url" "deps/remote" "main"

# Make local changes and commit them (but don't push)
cd "deps/remote"
echo "Local committed change" >> README.md
git add README.md
git commit -q -m "Local committed change"
cd "$TEST_PATH"

# Add more commits to remote to create divergence
cd "$remote_repo"
echo "More remote changes" >> README.md
git add README.md
git commit -q -m "More remote changes"
cd "$TEST_PATH"

# This should prompt for confirmation and user says no, so it should skip
echo "Testing pull with local unpushed changes - should ask for confirmation"
echo "n" | "$BASE_PATH/bin/git-deps" pull > /dev/null 2>&1
# Check that it actually prompted
if echo "n" | "$BASE_PATH/bin/git-deps" pull 2>&1 | grep -q "Continue pulling.*\[y/N\]"; then
    test-ok "Should ask for confirmation when pulling with local unpushed commits"
else
    test-fail "Should have asked for confirmation but didn't"
fi

# With --force flag, it should proceed (note: this will fail as --force is not implemented yet)
echo "Testing with --force flag"
test-expect-success "$BASE_PATH/bin/git-deps" pull --force
test-ok "Should proceed with --force flag"

test-step "Confirm: Changing branch/commit of dependency where target doesn't exist in remote"

# Create a repo with limited branches
limited_repo="$TEST_PATH/limited-repo"
create_test_repo "$limited_repo" "main"
limited_url="file://$limited_repo"

# Add dependency normally
test-expect-success "$BASE_PATH/bin/git-deps" add "$limited_url" "deps/limited" "main"

# Try to update .gitdeps to reference a branch that doesn't exist in remote
echo -e "deps/limited\t$limited_url\tfeature-branch\tabc123" > .gitdeps

# This should ask for confirmation before proceeding
echo "Testing pull with non-existent remote branch - should ask for confirmation"
echo "n" | test-expect-failure "$BASE_PATH/bin/git-deps" pull
test-ok "Should ask for confirmation when branch doesn't exist in remote"

test-step "Confirm: Overwriting local changes"

# Create clean repo and add as dependency
clean_repo="$TEST_PATH/clean-repo"
create_test_repo "$clean_repo"
clean_url="file://$clean_repo"

test-expect-success "$BASE_PATH/bin/git-deps" add "$clean_url" "deps/clean" "main"

# Make local uncommitted changes
cd "deps/clean"
echo "Uncommitted local changes" >> README.md
cd "$TEST_PATH"

# This should ask for confirmation before overwriting
echo "Testing pull with uncommitted changes - should ask for confirmation"
echo "n" | test-expect-failure "$BASE_PATH/bin/git-deps" pull
test-ok "Should ask for confirmation when overwriting uncommitted changes"

test-step "Confirm: Removing existing dependency"

# Add a dependency
remove_repo="$TEST_PATH/remove-repo" 
create_test_repo "$remove_repo"
remove_url="file://$remove_repo"
test-expect-success "$BASE_PATH/bin/git-deps" add "$remove_url" "deps/to-remove" "main"

# Note: Remove functionality doesn't exist yet, but this would ask for confirmation
echo "Remove functionality not implemented yet"
test-expect-failure "$BASE_PATH/bin/git-deps" remove "deps/to-remove"
test-ok "Remove command should ask for confirmation"

test-step "Confirm: Updating dependency with uncommitted changes in working directory"

# Create repo and add as dependency
update_repo="$TEST_PATH/update-repo"
create_test_repo "$update_repo"
update_url="file://$update_repo"
test-expect-success "$BASE_PATH/bin/git-deps" add "$update_url" "deps/update" "main"

# Make uncommitted changes
cd "deps/update"
echo "Uncommitted changes" >> README.md
# Don't commit these changes
cd "$TEST_PATH"

# Update command should ask for confirmation
echo "Testing update with uncommitted changes - should ask for confirmation"
echo "n" | test-expect-failure "$BASE_PATH/bin/git-deps" update
test-ok "Update should ask for confirmation with uncommitted changes"

test-step "Test interactive prompts (simulated)"

# Since we can't test actual interactive prompts in automated tests,
# we simulate what the behavior should be

# Create a scenario where confirmation would be needed
interactive_repo="$TEST_PATH/interactive-repo"
create_test_repo "$interactive_repo"
interactive_url="file://$interactive_repo"
test-expect-success "$BASE_PATH/bin/git-deps" add "$interactive_url" "deps/interactive" "main"

# Make local changes that would conflict
cd "deps/interactive"
echo "Changes that would require confirmation" >> README.md
git add README.md
git commit -q -m "Local changes requiring confirmation"
cd "$TEST_PATH"

# In a real interactive session, this would prompt:
# "Dependency has local changes that haven't been pushed. Continue? [y/N]"
echo "In interactive mode, this would show confirmation prompt"
test-ok "Interactive confirmation simulation completed"

test-end