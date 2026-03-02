#!/usr/bin/env bash

# Git Deps Test Runner
# Runs all integration tests for git-deps

set -euo pipefail

BASE_PATH="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_DIR="$BASE_PATH/tests"

echo "🧪 Git Deps Test Suite"
echo "======================"

total_tests=0
passed_tests=0
failed_tests=0

run_test() {
	local test_file="$1"
	local test_name="$(basename "$test_file" .sh)"
	local exit_code=0

	echo "📝 Running $test_name..."

	# Disable errexit temporarily for this function
	set +e
	timeout 120 "$test_file"
	exit_code=$?
	set -e

	if [ $exit_code -eq 0 ]; then
		echo "✅ $test_name PASSED"
		((passed_tests++)) || true
	else
		echo "❌ $test_name FAILED"
		((failed_tests++)) || true
	fi
	((total_tests++)) || true
	echo
}

# Run all integration tests
for test_file in "$TEST_DIR"/integration-*.sh; do
	if [ -x "$test_file" ]; then
		run_test "$test_file"
	fi
done

echo "📊 Test Results:"
echo "================"
echo "Total:  $total_tests"
echo "Passed: $passed_tests"
echo "Failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
	echo "🎉 All tests passed!"
	exit 0
else
	echo "💥 $failed_tests test(s) failed"
	exit 1
fi
