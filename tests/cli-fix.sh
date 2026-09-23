#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"

test-init "CLI Fix Tests"

test-step "Repair a malformed .gitdeps file"
printf '# Header comment\ndeps/a\thttps://example.com/a.git\tmain\tabc123\textra1\textra2\n\n  # Spaced comment\ndeps/b    https://example.com/b.git   dev\ndeps/a https://example.com/a.git main abc123\ndeps/c https://example.com/c.git\nlonelypath\n' >.gitdeps

test-expect-success "$BASE_PATH/bin/git-deps" fix

expected=$'# Header comment\ndeps/a https://example.com/a.git main abc123\n  # Spaced comment\ndeps/b https://example.com/b.git dev\ndeps/c https://example.com/c.git main'
test-expect "$(<.gitdeps)" "$expected" ".gitdeps was normalised"

test-step "Entries missing a branch use the configured default"
printf 'deps/x https://example.com/x.git\n' >.gitdeps
test-expect-success "$BASE_PATH/bin/git-deps" fix --branch develop
test-expect "$(<.gitdeps)" "deps/x https://example.com/x.git develop" "missing branch filled in"

test-step "Dry run prints the repair without writing it"
printf 'deps/a https://example.com/a.git main abc extra\n' >.gitdeps
original=$(<.gitdeps)
dry_run_output=$("$BASE_PATH/bin/git-deps" fix --dry-run 2>/dev/null)
test-expect "$(<.gitdeps)" "$original" "file unchanged by dry run"
test-substring "$dry_run_output" "deps/a https://example.com/a.git main abc"

test-step "An already-clean file reports no changes"
printf '# Header\ndeps/a https://example.com/a.git main abc123\n# EOF\n' >.gitdeps
clean=$(<.gitdeps)
fix_output=$("$BASE_PATH/bin/git-deps" fix 2>&1)
test-expect "$(<.gitdeps)" "$clean" "clean file left untouched"
test-substring "$fix_output" "No changes needed"

test-step "A missing .gitdeps file is an error"
rm -f .gitdeps
test-expect-failure "$BASE_PATH/bin/git-deps" fix

test-step "Unknown options are rejected"
printf 'deps/a https://example.com/a.git main\n' >.gitdeps
test-expect-failure "$BASE_PATH/bin/git-deps" fix --nope

# EOF
