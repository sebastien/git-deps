#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"

test-init "CLI Path Argument Consistency Tests"

function create_test_repo {
	local repo_path="$1"
	local branch="${2:-main}"

	mkdir -p "$repo_path"
	(
		cd "$repo_path" || exit 1
		git init -q
		git config user.name "Test User"
		git config user.email "test@example.com"
		echo "# Test repo" >README.md
		git add README.md
		git commit -q -m "Initial commit"

		if [ "$branch" != "main" ]; then
			git checkout -q -b "$branch"
			echo "# Branch commit" >>README.md
			git add README.md
			git commit -q -m "Branch commit"
		fi
	)
}

test-step "update PATH only processes selected dependencies"
repo_a="$TEST_PATH/repo-a"
repo_b="$TEST_PATH/repo-b"
create_test_repo "$repo_a"
create_test_repo "$repo_b"
url_a="file://$repo_a"
url_b="file://$repo_b"

test-expect-success "$BASE_PATH/bin/git-deps" add "deps/a" "$url_a" "main"
test-expect-success "$BASE_PATH/bin/git-deps" add "deps/b" "$url_b" "main"

echo "Uncommitted change" >>"$TEST_PATH/deps/a/README.md"

update_output=$("$BASE_PATH/bin/git-deps" update "deps/b" 2>&1)
test-substring "$update_output" "deps/b"
if echo "$update_output" | grep -Fq "deps/a"; then
	test-fail "update PATH should not process non-selected dependencies"
else
	test-ok "update PATH skips non-selected dependencies"
fi

test-step "checkout PATH only processes selected dependencies"
checkout_repo_a="$TEST_PATH/checkout-a"
checkout_repo_b="$TEST_PATH/checkout-b"
create_test_repo "$checkout_repo_a"
create_test_repo "$checkout_repo_b"
checkout_url_a="file://$checkout_repo_a"
checkout_url_b="file://$checkout_repo_b"

cat >.gitdeps <<EOF
deps/checkout-a	$checkout_url_a	main
deps/checkout-b	$checkout_url_b	main
EOF

rm -rf "$TEST_PATH/deps/checkout-a" "$TEST_PATH/deps/checkout-b"

checkout_output=$("$BASE_PATH/bin/git-deps" checkout "deps/checkout-a" 2>&1)
test-substring "$checkout_output" "deps/checkout-a"
test-exist "$TEST_PATH/deps/checkout-a/.git" "Selected dependency was checked out"
if [ -e "$TEST_PATH/deps/checkout-b/.git" ]; then
	test-fail "checkout PATH should not process non-selected dependencies"
else
	test-ok "checkout PATH skips non-selected dependencies"
fi

test-step "unknown path is rejected consistently"
if bad_update=$("$BASE_PATH/bin/git-deps" update "deps/unknown" 2>&1); then
	test-fail "update with unknown path should fail"
else
	test-substring "$bad_update" "Path 'deps/unknown' is not a registered dependency"
	test-ok "update rejects unknown paths"
fi

if bad_checkout=$("$BASE_PATH/bin/git-deps" checkout "deps/unknown" 2>&1); then
	test-fail "checkout with unknown path should fail"
else
	test-substring "$bad_checkout" "Path 'deps/unknown' is not a registered dependency"
	test-ok "checkout rejects unknown paths"
fi

# EOF
