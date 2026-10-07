#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"

test-init "Update Dependencies at a Date"

repo="$TEST_PATH/repo"
mkdir -p "$repo"
(
	cd "$repo"
	git init -q -b main
	git config user.name "Test User"
	git config user.email "test@example.com"
	echo first >file
	git add file
	GIT_AUTHOR_DATE="2001-01-01T00:00:00Z" GIT_COMMITTER_DATE="2001-01-01T00:00:00Z" git commit -q -m first
	echo second >file
	git add file
	GIT_AUTHOR_DATE="2003-01-01T00:00:00Z" GIT_COMMITTER_DATE="2003-01-01T00:00:00Z" git commit -q -m second
)

test-step "--at checks out the latest commit not after the requested time"
test-expect-success "$BASE_PATH/bin/git-deps" add deps/sample "file://$repo" main
first_commit=$(git -C "$repo" rev-list --max-parents=0 HEAD)
second_commit=$(git -C "$repo" rev-parse HEAD)
update_output=$("$BASE_PATH/bin/git-deps" update --at "2002-01-01T00:00:00Z" deps/sample 2>&1)
test-substring "$update_output" "$second_commit"
test-substring "$update_output" "$first_commit"
test-substring "$update_output" "$(TZ="${TZ:-:/etc/localtime}" date -d '2003-01-01T00:00:00Z' '+%Y-%m-%d %H:%M:%S')"
test-substring "$update_output" "$(TZ="${TZ:-:/etc/localtime}" date -d '2001-01-01T00:00:00Z' '+%Y-%m-%d %H:%M:%S')"
test-expect "$(git -C deps/sample rev-parse HEAD)" "$first_commit"

test-step "omitted --at date is inferred and paths remain selectable"
test-expect-success "$BASE_PATH/bin/git-deps" update --at deps/sample
test-expect "$(git -C deps/sample log -1 --format=%s)" "second"
test-expect-failure "$BASE_PATH/bin/git-deps" update --at "2002-01-01" --pinned

test-step "update without --at retains latest-commit behavior"
test-expect-success "$BASE_PATH/bin/git-deps" update
test-expect "$(git -C deps/sample log -1 --format=%s)" "second"

# EOF
