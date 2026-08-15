#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"

test-init "CLI Import Tests"

function create_import_repo {
	local repo_path="$1"
	local branch="${2:-main}"
	local remote_path="$3"

	mkdir -p "$repo_path"
	(
		cd "$repo_path"
		git init -q -b main
		git config user.name "Test User"
		git config user.email "test@example.com"
		echo "main" >README.md
		git add README.md
		git commit -q -m "Initial commit"
		git remote add origin "file://$remote_path"
		if [ "$branch" != "main" ]; then
			git checkout -q -b "$branch"
			echo "$branch" >README.md
			git commit -q -am "Feature commit"
		fi
	)
}

test-step "import defaults to deps and creates .gitdeps"
mkdir -p deps
create_import_repo "$TEST_PATH/deps/one" main "$TEST_PATH/remote-one"
test-expect-success "$BASE_PATH/bin/git-deps" import
test-exist ".gitdeps" "Import created .gitdeps"
test-substring "$(<.gitdeps)" "deps/one" "file://" "main"

test-step "import preserves symlink paths"
create_import_repo "$TEST_PATH/littlemake" main "$TEST_PATH/remote-littlemake"
ln -s "$TEST_PATH/littlemake" deps/littlemake
test-expect-success "$BASE_PATH/bin/git-deps" import deps/littlemake
test-substring "$(<.gitdeps)" "deps/littlemake"

test-step "import accepts multiple paths and recursion"
mkdir -p extra/nested
create_import_repo "$TEST_PATH/extra/two" main "$TEST_PATH/remote-two"
create_import_repo "$TEST_PATH/extra/nested/three" main "$TEST_PATH/remote-three"
test-expect-success "$BASE_PATH/bin/git-deps" import "$TEST_PATH/extra/two" "$TEST_PATH/extra/nested" --recursive
test-substring "$(<.gitdeps)" "extra/two" "extra/nested/three"

test-step "import checks out the configured branch"
git -C deps/one checkout -q -b feature
echo "feature" >deps/one/README.md
git -C deps/one commit -q -am "Feature commit"
test-expect "$(git -C deps/one status --porcelain)" "" "Feature repository has no local changes"

one_commit=$(git -C deps/one rev-list --max-parents=0 HEAD)
cat >.gitdeps <<EOF
deps/one file://$TEST_PATH/remote-one main
EOF
test-expect-success "$BASE_PATH/bin/git-deps" import deps/one
test-expect "$(git -C deps/one branch --show-current)" "main" "Import restored configured branch"

test-step "import checks out a configured commit"
cat >.gitdeps <<EOF
deps/one file://$TEST_PATH/remote-one main $one_commit
EOF
git -C deps/one checkout -q feature
test-expect-success "$BASE_PATH/bin/git-deps" import deps/one
test-expect "$(git -C deps/one rev-parse HEAD)" "$one_commit" "Import restored configured commit"

test-step "import warns and succeeds when a configured dependency has local changes"
echo "Local change" >>deps/one/README.md
set +e
import_output=$("$BASE_PATH/bin/git-deps" import deps/one 2>&1)
import_status=$?
set -e
if [ "$import_status" -eq 0 ] && echo "$import_output" | grep -q "⚠.*cannot checkout with local changes" && echo "$import_output" | grep -q "warnings=1"; then
	test-ok "Import warns without failing or rewriting local changes"
else
	test-fail "Import should warn and succeed when local changes prevent checkout"
fi
if grep -q '^Local change$' deps/one/README.md; then
	test-ok "Import preserved local changes"
else
	test-fail "Import should preserve local changes"
fi

# EOF
