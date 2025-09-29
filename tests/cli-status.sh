#!/usr/bin/env bash

# Test cases for the updated git-deps status command

source "$(dirname "$0")/lib-testing.sh"

test-init "CLI Status Tests"

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

test-step "Test status output format"

# Create remote repo for testing
remote_repo="$TEST_PATH/test-repo"
create_remote_with_history "$remote_repo"
remote_url="file://$remote_repo"

# Initialize git-deps in test directory
cd "$TEST_PATH"

# Add dependency
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/test-repo" "$remote_url" "main"

# Test basic status output
test-step "Basic status output"
output=$("$BASE_PATH/bin/git-deps" status 2>&1)

	# Check for the improved format patterns
	test-substring "$output" "deps/test-repo"
	test-substring "$output" "dep"
 	test-substring "$output" "local"
 	test-substring "$output" "remote"

# Check for date format (YYYY-MM-DD)
if echo "$output" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
    test-ok "Dates are included in output"
else
    test-fail "Expected dates in YYYY-MM-DD format"
fi

test-ok "Status output contains new format elements"

test-step "Test synced dependency status"

	# Initially, everything should be synced
	output=$("$BASE_PATH/bin/git-deps" status 2>&1)
	test-substring "$output" "[SYNCED]"
	test-ok "Synced dependency shows correct status"

test-step "Test local changes (uncommitted)"

# Make uncommitted changes
cd "deps/test-repo"
echo "Local uncommitted change" >> README.md
cd "$TEST_PATH"

	output=$("$BASE_PATH/bin/git-deps" status 2>&1)
	test-substring "$output" "[UNCOMMITTED]"
	test-ok "Uncommitted changes detected"

test-step "Test local changes (committed)"

# Commit the local changes
cd "deps/test-repo"
git add README.md
git commit -q -m "Local committed change"
cd "$TEST_PATH"

output=$("$BASE_PATH/bin/git-deps" status 2>&1)
	# Accept "[AHEAD]" when local is ahead of remote
	if echo "$output" | grep -q "\[AHEAD\]"; then
	    test-ok "Local committed changes detected"
	else
	    test-fail "Expected local changes to be detected"
	fi

test-step "Test ahead/behind counts"

# Add more commits locally
cd "deps/test-repo"
echo "Another local change" >> README.md
git add README.md
git commit -q -m "Another local change"
cd "$TEST_PATH"

output=$("$BASE_PATH/bin/git-deps" status 2>&1)
# Look for (+N) pattern after date
if echo "$output" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2} \(\+[0-9]+\)'; then
    test-ok "Ahead count displayed correctly after date"
else
    test-fail "Expected ahead count after date"
fi

test-step "Test remote ahead of local"

# Reset local to be behind remote
cd "deps/test-repo"
git reset --hard HEAD~3
cd "$TEST_PATH"

output=$("$BASE_PATH/bin/git-deps" status 2>&1)
# Accept either "behind" or "behind changed"
if echo "$output" | grep -qE "(behind|behind changed)"; then
    test-ok "Behind status detected"
else
    test-fail "Expected behind status to be detected"
fi

test-step "Test missing dependency"

# Remove dependency directory
rm -rf "deps/test-repo"

	output=$("$BASE_PATH/bin/git-deps" status 2>&1)
	test-substring "$output" "[MISSING]"
	test-ok "Missing dependency detected"

test-step "Test unavailable remote"

# Create dependency with bad remote URL
echo -e "deps/bad-remote\thttps://nonexistent.invalid/repo.git\tmain\tabc123" >> .gitdeps

	output=$("$BASE_PATH/bin/git-deps" status 2>&1)
	test-substring "$output" "[UNAVAILABLE]"
	test-ok "Unavailable remote detected"

test-step "Test missing branch in remote"

# Create a repo without the specified branch
limited_repo="$TEST_PATH/limited-repo"
create_test_repo "$limited_repo" "main"
limited_url="file://$limited_repo"

# Add dependency referencing non-existent branch
echo -e "deps/missing-branch\t$limited_url\tfeature-branch\t" >> .gitdeps

	output=$("$BASE_PATH/bin/git-deps" status 2>&1)
	test-substring "$output" "[MISSING]"
	test-ok "Missing branch in remote detected"

test-step "Test status colors (when enabled)"

# Colors should be present in output when NO_COLOR is not set
unset NO_COLOR
output=$("$BASE_PATH/bin/git-deps" status 2>&1)

# Check that ANSI color codes are present (basic check)
if echo "$output" | grep -q $'\033\['; then
    test-ok "Color codes present in output"
else
    test-fail "Expected color codes in output"
fi

test-step "Test status without colors"

# Colors should be absent when NO_COLOR is set
export NO_COLOR=1
output=$("$BASE_PATH/bin/git-deps" status 2>&1)

# Check that ANSI color codes are NOT present
if echo "$output" | grep -q $'\033\['; then
    test-fail "Unexpected color codes in NO_COLOR mode"
else
    test-ok "No color codes when NO_COLOR is set"
fi

test-step "Test status with multiple dependencies"

# Add multiple dependencies with different states
multi_repo1="$TEST_PATH/multi1"
multi_repo2="$TEST_PATH/multi2"
create_test_repo "$multi_repo1" "main"
create_test_repo "$multi_repo2" "develop"

multi_url1="file://$multi_repo1"
multi_url2="file://$multi_repo2"

test-expect-success "$BASE_PATH/bin/git-deps" add "deps/multi1" "$multi_url1" "main"
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/multi2" "$multi_url2" "develop"

output=$("$BASE_PATH/bin/git-deps" status 2>&1)
test-substring "$output" "deps/multi1"
test-substring "$output" "deps/multi2"
test-ok "Multiple dependencies shown in status"

test-step "Test empty repository (no dependencies)"

# Create fresh test directory
empty_test_path="$TEST_PATH/empty"
mkdir -p "$empty_test_path"
cd "$empty_test_path"

# Should show no dependencies message
output=$("$BASE_PATH/bin/git-deps" status 2>&1)
test-substring "$output" "No dependencies found"
test-ok "Empty repository handled correctly"

test-end