# AGENTS.md

Guidelines for working with the `git-deps`/`jj-deps` codebase - a Bash-based Git submodule alternative.

## Build/Test/Lint Commands

```bash
# Run all tests
make test

# Run a single test file
bash tests/harness.sh tests/cli-status.sh
bash tests/harness.sh tests/integration-errors.sh

# Run test categories
bash tests/harness.sh tests/cli-*.sh      # CLI tests only
bash tests/harness.sh tests/integration-*.sh  # Integration tests only

# Linting (shellcheck)
make lint

# Formatting (shfmt)
make fmt

# Interactive shell with git-deps in PATH
make shell

# Install locally (symlinks to ~/.local/bin)
make install
```

## Code Style Guidelines

### Bash Conventions
- **Shebang**: Always use `#!/usr/bin/env bash`
- **Strict mode**: `set -euo pipefail` at start of all scripts
- **EOF marker**: End all scripts with `# EOF` comment
- **Indentation**: Use tabs (not spaces)
- **Line endings**: Unix-style (LF only)

### Naming Conventions
- **Functions**: `snake_case` with `git_deps_` prefix for main code, `test_*` for tests
  - Example: `git_deps_log_action`, `git_deps_status`, `test_init`
- **Variables**: UPPER_CASE for globals/constants, lower_case for locals
  - Example: `GIT_DEPS_FILE`, `local message="$1"`
- **Environment variables**: `GIT_DEPS_*` prefix
  - Example: `GIT_DEPS_MODE`, `GIT_DEPS_PARALLEL`

### Function Style
```bash
# Use 'function name {' syntax (not 'name() {')
function git_deps_log_action {
	local message="$*"
	echo "${BLUE} ▶ $message$RESET" >&2
	return 0
}
```

### Documentation Comments
```bash
# Function: git_deps_log_error
# Logs an error message in red color
# Parameters:
#   message - Error message to display
function git_deps_log_error {
	local message="$*"
	echo "${RED}✗ Error: $message${RESET}" >&2
	return 1
}
```

### Error Handling
- Use `set -euo pipefail` in all scripts
- Functions that fail should `return 1`
- Log errors to stderr (`>&2`)
- Use `git_deps_log_error` for user-facing errors
- Use `git_deps_log_warning` for non-fatal issues

### Variable Declaration
```bash
# Always declare local variables
local message="$*"
local repo_path="$1"
local branch="${2:-main}"  # With default value

# Globals with defaults
GIT_DEPS_FILE="${GIT_DEPS_FILE:-.gitdeps}"
```

### Imports/Dependencies
```bash
# Source test library (for tests)
source "$(dirname "$0")/lib-testing.sh"

# Calculate base path dynamically
BASE_PATH="$(dirname "$(dirname "$(readlink -f "$0")")")"
```

### Testing Patterns
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib-testing.sh"

test-init "Test Suite Name"

test-step "Description of what we're testing"
test-expect-success command arg1 arg2
test-ok "Expected outcome happened"

test-step "Testing error case"
test-expect-failure command invalid-arg
test-ok "Error was properly raised"
```

### Color Output
- Use defined color variables: `BLUE`, `GREEN`, `RED`, `YELLOW`, `ORANGE`, `PURPLE`, etc.
- Respect `NO_COLOR` environment variable
- Output UI elements to stderr (`>&2`)
- Symbols: `▶` (action), `⋯` (step), `✓` (success), `⚠` (warning), `✗` (error)

## Project Structure

```
git-deps/
├── bin/
│   ├── git-deps           # Main entry point
│   └── jj-deps -> ../src/sh/git-deps.sh  # Symlink for jj mode
├── src/sh/
│   └── git-deps.sh        # Main implementation (2337 lines)
├── tests/
│   ├── harness.sh         # Test runner
│   ├── lib-testing.sh     # Testing framework
│   ├── cli-*.sh           # CLI unit tests
│   ├── integration-*.sh   # Integration tests
│   └── run/               # Test run artifacts
├── docs/
│   ├── design.md          # Design documentation
│   └── manual.md          # User manual
├── Makefile               # Build automation
└── README.md              # Project overview
```

## Key Implementation Notes

- Supports both `git` and `jj` (Jujutsu) VCS modes
- Configuration stored in `.gitdeps` file (tab/space-separated fields)
- Parallel fetching with max concurrent jobs (default: 4)
- Uses RAP (Report Anything Protocol) format for test output
- All operations respect `GIT_DEPS_OFFLINE`, `GIT_DEPS_PARALLEL`, etc.

## Important notes

- DO NOT alter the version control
- DO NOT run commands outside of this directory, use ./tmp/ for tests
