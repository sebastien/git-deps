#!/usr/bin/env bash

# Test cases that should generate warnings but not fail

source "$(dirname "$0")/lib-testing.sh"

test-init "Integration Warning Tests"

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

# Helper function to create invalid .gitdeps file
create_invalid_gitdeps() {
    local content="$1"
    echo -e "$content" > .gitdeps
}

test-step "Warning: Parsing syntax errors in configuration"

# Test malformed .gitdeps file
create_invalid_gitdeps "incomplete-line-missing-repo"
test-expect-success "$BASE_PATH/bin/git-deps" status
test-ok "Should warn about malformed .gitdeps entry"

# Test .gitdeps with invalid characters
create_invalid_gitdeps "repo\thttps://github.com/test/repo\tbranch\tcommit\textra-field"
test-expect-success "$BASE_PATH/bin/git-deps" status
test-ok "Should warn about extra fields in .gitdeps"

test-step "Warning: Extra information in configuration"

# Create valid repo first
repo_url="file://$TEST_PATH/test-repo"
create_test_repo "$TEST_PATH/test-repo"

# Add dependency normally
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/test-repo" "$repo_url" "main"

# Manually add extra field to .gitdeps
sed -i '' 's/$/\textra-field/' .gitdeps

# Check status - should succeed but show warnings
output=$("$BASE_PATH/bin/git-deps" status 2>&1)
if echo "$output" | grep -q "WARN.*Extra information"; then
    test-ok "Should warn about extra information in .gitdeps"
else
    test-fail "Should warn about extra information but didn't"
fi

test-step "Warning: Duplication in configuration"

# Create .gitdeps with duplicate entries
create_invalid_gitdeps "deps/dup\t$repo_url\tmain\tabc123\ndeps/dup\t$repo_url\tmain\txyz789"

# Check status - should succeed but show warnings
output=$("$BASE_PATH/bin/git-deps" status 2>&1)
if echo "$output" | grep -q "WARN.*Duplicate dependency"; then
    test-ok "Should warn about duplicate dependency paths"
else
    test-fail "Should warn about duplicate paths but didn't"
fi

test-step "Warning: Referenced branches/commits don't exist in checked out repos"

# Create a repo and add it as dependency
create_test_repo "$TEST_PATH/existing-repo"
existing_repo_url="file://$TEST_PATH/existing-repo"

# Add dependency with valid branch
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/existing" "$existing_repo_url" "main"

# Manually modify .gitdeps to reference non-existent branch
sed -i '' 's/main/nonexistent-branch/' .gitdeps

# Check status - should succeed but show warnings
output=$("$BASE_PATH/bin/git-deps" status 2>&1)
if echo "$output" | grep -q "WARN.*does not exist"; then
    test-ok "Should warn about branch that doesn't exist in repo"
else
    test-fail "Should warn about non-existent branch but didn't"
fi

# Reset and test with non-existent commit
sed -i '' 's/nonexistent-branch/main/' .gitdeps
sed -i '' 's/[0-9a-f]\{7,40\}/deadbeefdeadbeefdeadbeefdeadbeefdeadbeef/' .gitdeps

output=$("$BASE_PATH/bin/git-deps" status 2>&1)
if echo "$output" | grep -q "WARN.*does not exist"; then
    test-ok "Should warn about commit that doesn't exist in repo"
else
    test-fail "Should warn about non-existent commit but didn't"
fi

test-step "Warning: .gitdeps file missing or empty"

# Remove .gitdeps file
rm -f .gitdeps
test-expect-success "$BASE_PATH/bin/git-deps" status
test-ok "Should handle missing .gitdeps gracefully"

# Create empty .gitdeps
touch .gitdeps
test-expect-success "$BASE_PATH/bin/git-deps" status
test-ok "Should handle empty .gitdeps gracefully"

test-step "Comment lines in .gitdeps should be ignored"

# Create .gitdeps with comments and valid entries
create_invalid_gitdeps "# This is a comment\ndeps/test-repo\t$repo_url\tmain\tabc123\n# Another comment\n   # Comment with leading spaces\ndeps/another-repo\thttps://github.com/test/another.git\tmain"

# Check status - should succeed and ignore comments
output=$("$BASE_PATH/bin/git-deps" status 2>&1)
if echo "$output" | grep -q "deps/test-repo\|deps/another-repo"; then
    test-ok "Should process valid entries and ignore comment lines"
else
    test-fail "Should process valid entries but comments may not be ignored properly"
fi

# Test that comments don't appear in parsed output
parsed_output=$("$BASE_PATH/bin/git-deps" state 2>&1)
if echo "$parsed_output" | grep -q "#"; then
    test-fail "Comments should not appear in parsed output"
else
    test-ok "Comments are properly filtered out from parsed output"
fi

test-end