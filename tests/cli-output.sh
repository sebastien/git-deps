#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib-testing.sh"

# Pull in helper functions (e.g. git_deps_op_commit_date) for direct assertions.
source "$(dirname "$0")/../src/sh/git-deps.sh"

test-init "CLI Output Rules"

export NO_COLOR=1 TZ=Etc/GMT-2

# Build a small local remote + clone to exercise no-op and change paths.
remote="$TEST_PATH/remote"
git init -q -b main "$remote"
git -C "$remote" config user.name Test
git -C "$remote" config user.email test@example.com
echo initial >"$remote/file"
git -C "$remote" add file
GIT_COMMITTER_DATE=2001-01-01T00:00:00Z git -C "$remote" commit -qm initial

git clone -q "$remote" deps/sample
commit=$(git -C "$remote" rev-parse HEAD)
echo "deps/sample $remote main $commit" >.gitdeps

test-step "No-op mutations are silent on stdout and stderr"
for command in checkout 'checkout --missing' update 'update --pinned' 'update --at 2002-01-01' pull save fix 'import deps/sample'; do
	read -ra args <<<"$command"
	output=$("$BASE_PATH/bin/git-deps" "${args[@]}" 2>&1)
	test-expect "$output" "" "No-op '$command' produces no output"
done

test-step "Commit dates use local time"
test-expect "$(git_deps_op_commit_date deps/sample)" "2001-01-01 02:00:00"

test-step "A successful update reports the change and the new commit date"
echo changed >>"$remote/file"
git -C "$remote" commit -qam changed
output=$("$BASE_PATH/bin/git-deps" update 2>&1)
test-substring "$output" "deps/sample" "$(git -C deps/sample rev-parse HEAD)"
test-expect "$(git -C "$remote" rev-parse HEAD)" "$(git -C deps/sample rev-parse HEAD)" "Checkout advanced to remote HEAD"

test-step "Re-running the same update is silent"
test-expect "$("$BASE_PATH/bin/git-deps" update 2>&1)" "" "Second update is a no-op"

test-step "Failures carry context and a tip"
if output=$("$BASE_PATH/bin/git-deps" add deps/bad "$TEST_PATH/absent" 2>&1); then
	test-fail "add with a missing repository should fail"
else
	test-substring "$output" "deps/bad" "absent" "Tip:"
	test-ok "Error names the dependency, the repository, and a tip"
fi

test-step "Credentials in URLs are redacted from failures"
if output=$(NO_COLOR=1 "$BASE_PATH/bin/git-deps" add deps/creds "https://user:s3cr3t@127.0.0.1:9/r.git" main 2>&1); then
	test-fail "add against an unreachable repository should fail"
else
	if printf '%s' "$output" | grep -Fq "https://***@127.0.0.1:9/r.git"; then
		test-ok "Redacted URL is shown"
	else
		test-fail "Expected redacted URL in output"
	fi
	if printf '%s' "$output" | grep -q "s3cr3t"; then
		test-fail "Credential leaked in error output"
	else
		test-ok "Credentials are redacted"
	fi
fi

test-step "Non-interactive output has no ANSI; CLICOLOR_FORCE re-enables it"
# The harness captures output, so stderr is not a terminal.
unset NO_COLOR
output=$("$BASE_PATH/bin/git-deps" add deps/ansi "$TEST_PATH/absent" 2>&1) || true
if printf '%s' "$output" | grep -q $'\033\['; then
	test-fail "Redirected output contained ANSI sequences"
else
	test-ok "Redirected output has no ANSI sequences"
fi
output=$(CLICOLOR_FORCE=1 "$BASE_PATH/bin/git-deps" add deps/ansi "$TEST_PATH/absent" 2>&1) || true
if printf '%s' "$output" | grep -q $'\033\['; then
	test-ok "CLICOLOR_FORCE re-enables ANSI"
else
	test-fail "CLICOLOR_FORCE did not re-enable ANSI"
fi
export NO_COLOR=1

test-step "Missing configuration: read-only commands are silent, mutations fail"
missing="$TEST_PATH/noconfig"
mkdir -p "$missing"
for command in status state list; do
	read -ra args <<<"$command"
	out=$(cd "$missing" && "$BASE_PATH/bin/git-deps" "${args[@]}" 2>&1)
	test-expect "$out" "" "read-only '$command' is silent without .gitdeps"
done
for command in update checkout pull fix 'remove deps/x'; do
	read -ra args <<<"$command"
	rm -f "$missing/.gitdeps"
	if out=$(cd "$missing" && "$BASE_PATH/bin/git-deps" "${args[@]}" 2>&1); then
		test-fail "mutation '$command' should fail without .gitdeps"
	else
		if printf '%s' "$out" | grep -Fq "[.gitdeps] could not be found"; then
			test-ok "mutation '$command' fails with context"
		else
			test-fail "expected '[$GIT_DEPS_FILE] could not be found', got: $out"
		fi
	fi
done

test-step "Save creates .gitdeps when missing"
rm -f "$missing/.gitdeps"
if out=$(cd "$missing" && "$BASE_PATH/bin/git-deps" save 2>&1); then
	test-exist "$missing/.gitdeps" "save created .gitdeps"
else
	test-fail "save should create .gitdeps instead of failing, got: $out"
fi

test-end

# EOF
