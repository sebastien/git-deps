#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"/tests/lib-testing.sh

if [ $# == 0 ]; then
	FILES=$(find "$BASE" -name "*.*")
else
	FILES=$*
fi

test-start

for TEST in $FILES; do
	case "$TEST" in
	*/lib-*.sh) ;;
	*/harness.sh) ;;
	*/*.sh)
		if [ "$TEST_COUNT" -gt 0 ]; then
			test_log_separator
		fi
		export TEST_COUNT
		if test-run "${DIM}»${PURPLE}" "$TEST"; then
			test-ok "Unit test succeeded: ${YELLOW}$TEST"
		else
			test-fail "Unit test failed: ${RED}$TEST"
		fi
		;;
	esac
done

test_log_separator
if test-end; then
	echo "${GREEN}EOK${RESET}"
else
	echo "${RED}EFAIL${RESET}"
fi
# EOF
