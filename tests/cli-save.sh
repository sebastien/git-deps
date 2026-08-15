#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"

test-init "CLI Save Tests"

test-step "Create a local bare remote and dependency clone"
remote="$TEST_PATH/remote.git"
seed="$TEST_PATH/seed"
mkdir -p "$seed"
git -C "$seed" init -q -b main
git -C "$seed" config user.name "Test User"
git -C "$seed" config user.email "test@example.com"
echo "initial" >"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -q -m "Initial commit"
initial_commit=$(git -C "$seed" rev-parse HEAD)
git clone -q --bare "$seed" "$remote"
mkdir -p deps
git clone -q "$remote" deps/test-repo
git -C deps/test-repo config user.name "Test User"
git -C deps/test-repo config user.email "test@example.com"
printf 'deps/test-repo file://%s main %s\n' "$remote" "$initial_commit" >.gitdeps

test-step "Make an unpushed commit"
echo "unpushed" >>deps/test-repo/file.txt
git -C deps/test-repo add file.txt
git -C deps/test-repo commit -q -m "Unpushed commit"
unpushed_commit=$(git -C deps/test-repo rev-parse HEAD)
original_deps=$(<.gitdeps)

test-step "Normal save rejects the unpushed commit"
if save_output=$($BASE_PATH/bin/git-deps save 2>&1); then
	test-fail "git-deps save should reject unpushed commits"
else
	test-substring "$save_output" "not reachable from a cached remote ref"
	test-expect "$(<.gitdeps)" "$original_deps" ".gitdeps was not modified"
fi

test-step "Safe save records the nearest cached remote ancestor"
test-expect-success "$BASE_PATH/bin/git-deps" save --safe
test-substring "$(<.gitdeps)" "${initial_commit}"
if grep -q "$unpushed_commit" .gitdeps; then
	test-fail "Safe save recorded the unpushed commit"
else
	test-ok "Safe save omitted the unpushed commit"
fi

test-step "A pushed commit is accepted after refreshing cached refs"
git -C deps/test-repo push -q origin main
git -C deps/test-repo fetch -q origin
test-expect-success "$BASE_PATH/bin/git-deps" save
test-substring "$(<.gitdeps)" "$unpushed_commit"

test-step "Save reports a repository with no cached remote refs"
git -C deps/test-repo remote remove origin
if save_output=$($BASE_PATH/bin/git-deps save 2>&1); then
	test-fail "git-deps save should fail without cached remote refs"
else
	test-substring "$save_output" "has no cached remote refs"
fi

# EOF
