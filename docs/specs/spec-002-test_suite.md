# Git Deps Test suite

Git deps test suite should cover the following use cases:

What should warn:
- Parsing syntax errors in the configuration
- Extra information in the configuration
- Duplication in the configuration
- Branches/commits referenced in the config that do not exist in the checked out repos

What should fail with an error:
- Trying to add an already existing dependency
- Trying to pull a branch or commit that doesn't exist
- Trying to pull a dependency that has local changes

What should ask for confirmation interactively unless there's an -f|--force flag:
- Pulling a dependency with local commited changes that have not been pushed
- Changing the branch or commit of a dependency which commit/branch does not exist in the remote

## Implementation

Using `tests/lib-testing.sh`:

- Implement `tests/integration-warnings.sh` to exercise the warning cases
- Implement `tests/integration-errors.sh` to exercise the error cases
- Implement `tests/integration-confirm.sh` to exercise the confirm cases

Note that most will fail given that this is not implemented yet. Try to update
`src/sh/git-deps.sh` to support the test case. If too complex, leave that as
a todo for next time.


