#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"

test-init "Checkout never discards local work"

remote="$TEST_PATH/remote.git"
seed="$TEST_PATH/seed"
mkdir -p "$seed"
git -C "$seed" init -q -b main
git -C "$seed" config user.name "Test User"
git -C "$seed" config user.email "test@example.com"
echo "one" >"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -q -m "First commit"
first_commit=$(git -C "$seed" rev-parse HEAD)
echo "two" >>"$seed/file.txt"
git -C "$seed" commit -q -am "Second commit"
git clone -q --bare "$seed" "$remote"

mkdir -p deps
git clone -q "$remote" deps/dep
git -C deps/dep config user.name "Test User"
git -C deps/dep config user.email "test@example.com"
# Pin the dependency to the older commit so a checkout is required
printf 'deps/dep file://%s main %s\n' "$remote" "$first_commit" >.gitdeps

test-step "Non-forced checkout refuses to run over uncommitted changes"
echo "local work" >>deps/dep/file.txt
head_before=$(git -C deps/dep rev-parse HEAD)
set +e
output=$("$BASE_PATH/bin/git-deps" checkout 2>&1)
status=$?
set -e
if [ "$status" -eq 0 ] && echo "$output" | grep -q "Cannot checkout: has uncommitted changes"; then
	test-ok "Checkout warns and does not fail on uncommitted changes"
else
	test-fail "Checkout should warn about uncommitted changes (exit=$status)"
fi
test-expect "$(git -C deps/dep rev-parse HEAD)" "$head_before" "HEAD was not moved"
test-substring "$(cat deps/dep/file.txt)" "local work"

test-step "Forced checkout still refuses to run over uncommitted changes"
set +e
output=$("$BASE_PATH/bin/git-deps" checkout --force 2>&1)
status=$?
set -e
if [ "$status" -eq 0 ] && echo "$output" | grep -q "Cannot checkout: has uncommitted changes"; then
	test-ok "Forced checkout preserves uncommitted changes"
else
	test-fail "Forced checkout must never discard uncommitted changes (exit=$status)"
fi
test-expect "$(git -C deps/dep rev-parse HEAD)" "$head_before" "HEAD was still not moved"
test-substring "$(cat deps/dep/file.txt)" "local work"

test-step "Non-forced checkout refuses to switch with unpushed commits"
git -C deps/dep checkout -q -- .
echo "unpushed" >>deps/dep/file.txt
git -C deps/dep commit -q -am "Unpushed commit"
unpushed_head=$(git -C deps/dep rev-parse HEAD)
set +e
output=$("$BASE_PATH/bin/git-deps" checkout 2>&1)
status=$?
set -e
if [ "$status" -eq 0 ] && echo "$output" | grep -q "Cannot checkout: has unpushed commits"; then
	test-ok "Checkout warns about unpushed commits"
else
	test-fail "Checkout should warn about unpushed commits (exit=$status)"
fi
test-expect "$(git -C deps/dep rev-parse HEAD)" "$unpushed_head" "Unpushed HEAD was preserved"

test-step "Forced checkout proceeds with unpushed commits"
test-expect-success "$BASE_PATH/bin/git-deps" checkout --force
test-expect "$(git -C deps/dep rev-parse HEAD)" "$first_commit" "Forced checkout moved to the pinned commit"
test-expect "$(git -C deps/dep rev-parse main)" "$unpushed_head" "Unpushed commit remains reachable on main"

# EOF
