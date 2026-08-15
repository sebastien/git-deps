#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"
# Source the implementation to unit-test the relative path helper directly
source "$BASE_PATH/src/sh/git-deps.sh"

test-init "Relative path helper"

test-step "Relative paths are normalised"
test-expect "$(git_deps_relative_path "deps/x")" "deps/x" "Plain relative path is unchanged"
test-expect "$(git_deps_relative_path "./deps/y")" "deps/y" "Leading ./ is removed"

test-step "Paths below the workspace are made relative"
test-expect "$(git_deps_relative_path "$PWD/deps/z")" "deps/z" "Absolute path below PWD is stripped"

test-step "Paths outside the workspace resolve correctly"
outside="$(mktemp -d)"
mkdir -p "$outside/repo"
relative="$(git_deps_relative_path "$outside/repo")"
if [[ "$relative" != /* ]]; then
	test-ok "Outside path is returned as a relative path"
else
	test-fail "Outside path should be relative, got: $relative"
fi
if [ -e "$PWD/$relative" ]; then
	test-ok "Relative path resolves back to the target"
else
	test-fail "Relative path does not resolve to $outside/repo"
fi
rm -rf "$outside"

# EOF
