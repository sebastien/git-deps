# git-deps(1) - Git submodule alternative

## NAME

git-deps, jj-deps - Git submodule alternative for multi-repository projects

## SYNOPSIS

**git-deps** *add* [*-f|--force*] *path* *repo* [*branch*] [*commit*]  
**git-deps** [*subcommand*] [*options*]  
**jj-deps** [*subcommand*] [*options*]

## DESCRIPTION

`git-deps` is a Git submodule alternative that simplifies working with multi-repository projects. It resolves some of the problems with `git submodules` by ensuring clones always succeed even if dependencies are unavailable, and provides loose coupling that makes it more resilient than git submodule.

The tool works with both `git` and `jj` version control systems, automatically detecting which to use based on the repository type and command name.

## KEY CONCEPTS

`git-deps` has two main commands for managing dependencies:

- **`checkout`** - Restores dependencies to match the state in `.gitdeps` (local-only, no network)
- **`update`** - Fetches latest from remotes and fast-forwards dependencies (network operation)

### Workflow

```bash
# Initial setup - get dependencies to saved state
$ git-deps checkout

# Later, get latest updates from remotes
$ git-deps update

# After testing, save the new state
$ git-deps save
```

## CONFIGURATION

Dependencies are tracked in a `.gitdeps` file in the repository root. Each line specifies a dependency with tab or space-separated fields:

- **path** - Local path where dependency should be checked out (e.g., `deps/repo`)
- **url** - Repository URL (e.g., `git@github.com:user/repo.git`)
- **branch** - Branch, tag, or commit to track (e.g., `main`)
- **commit** - Optional specific commit hash that overrides branch

### Example .gitdeps file:
```
# Dependencies for the project
deps/appenv	git@github.com:sebastien/appenv.git	master
deps/git-kv	git@github.com:sebastien/git-kv.git	main	fcbd00e34ba2ba0232f446e8f37ab287426d1094
# End of dependencies
```

## COMMANDS

### add, a [*-f|--force*] *repo* *path* [*branch*] [*commit*]
Adds a new dependency to the project. Creates the specified path, clones the repository, and checks out the specified branch or commit. Adds an entry to the `.gitdeps` file.

**Parameters:**
- **repo** - Repository URL to clone (e.g., `git@github.com:user/repo.git`)
- **path** - Local path where dependency will be checked out (e.g., `deps/mylib`)
- **branch** - Optional branch, tag, or commit to checkout (defaults to `main`)
- **commit** - Optional specific commit hash to checkout
- **-f, --force** - Force addition even if dependency already exists at path

**Example:**
```
$ git-deps add deps/library git@github.com:user/library.git main
 → Adding git@github.com:user/library.git to deps/library
 … Cloning git@github.com:user/library.git
 … Checking out main
 ✱ git@github.com:user/library.git[main] is now available in deps/library
```

**Errors:**
- Dependency already registered at path (use `-f` to override)
- Unable to clone repository
- Branch or commit does not exist in repository

### status, st
Shows the status of each dependency. Reports whether dependencies are missing, up-to-date, behind, ahead, or have local modifications.

**Example:**
```
$ git-deps status
 → Checking dependency status
 … Checking 2 dependencies
 ✱ deps/appenv [master] up to date
 … deps/git-kv [main] can be updated
```

### checkout, co [*-f|--force*] [*path*]
Restores all dependencies to match the saved state in `.gitdeps`. This is a **local-only operation** - it does not fetch from remotes. It simply checks out to the pinned commit or branch specified in `.gitdeps`.

**Key behaviors:**
- **NO network operations** - works with local refs only
- **STRICT safety checks** - fails if there are uncommitted changes or unpushed commits
- **Smart checkout** - skips if already at correct state
- **Branch change confirmation** - asks before switching branches (unless `--force`)

**Options:**
- **-f, --force** - Override safety checks and skip confirmations
- **path** - Optional filter to checkout only specific dependency

**Safety checks (both must pass, or use --force):**
1. No uncommitted changes
2. No unpushed commits

**Error recovery tips:**
When checkout fails, it provides specific recovery actions:
- Uncommitted changes → `cd <path> && git status` to commit/stash
- Unpushed commits → `cd <path> && git push` to push
- Missing pinned commit → `git-deps update --pinned` to fetch it

**Example:**
```
$ git-deps checkout
 → Checking out dependencies
 … [1/2] Checking out deps/appenv [master]
   = Cloning git@github.com:sebastien/appenv.git...
   = Repository cloned successfully
   = Already on master (a1b2c3d4)
 └─ deps/appenv [OK]

 … [2/2] Checking out deps/git-kv [main]
   = Already on main (e5f6g7h8)
 └─ deps/git-kv [OK]

 ✱ All 2 dependencies checked out successfully
```

### update, up [*--pinned*] [*-f|--force*] [*path*]
Fetches latest changes from remotes and updates dependencies. By default, performs a **fast-forward** to the latest commit on the configured branch, ignoring any pinned commit in `.gitdeps`.

**Key behaviors:**
- **Fetches from remote** - always gets latest commits
- **STRICT safety checks** - fails if there are uncommitted changes or unpushed commits
- **Fast-forward only** - fails if local branch has diverged
- **Two modes:**
  - **Default**: Fast-forward to latest branch HEAD (ignores pinned commit)
  - **--pinned**: Checkout to exact pinned commit from `.gitdeps`

**Options:**
- **--pinned** - Checkout to pinned commit instead of fast-forwarding to latest
- **-f, --force** - Override safety checks
- **path** - Optional filter to update only specific dependency

**Safety checks (both must pass, or use --force):**
1. No uncommitted changes
2. No unpushed commits

**Error recovery tips:**
- Uncommitted changes → `cd <path> && git status` to commit/stash
- Unpushed commits → `cd <path> && git push` to push
- Diverged branch → `git-deps checkout` to reset to saved state
- Missing pinned commit (after fetch) → commit may have been force-pushed

**Example - Default mode (fast-forward):**
```
$ git-deps update
 → Updating dependencies
 … [1/2] Updating deps/appenv [master]
   = Fetching latest commits for deps/appenv
   = Fast-forwarding deps/appenv to a1b2c3d4...
 └─ deps/appenv [OK]

 … [2/2] Updating deps/git-kv [main]
   = Fetching latest commits for deps/git-kv
   = deps/git-kv already at latest commit e5f6g7h8 on main
 └─ deps/git-kv [OK]

 ✱ All dependencies updated successfully
```

**Example - Pinned mode:**
```
$ git-deps update --pinned
 → Updating dependencies
 … [1/2] Updating deps/appenv [master]
   = Fetching latest commits for deps/appenv
   = Checking out to pinned commit a1b2c3d4...
 └─ deps/appenv [OK]
```

### push, ph
Pushes changes in all dependency repositories to their remotes.

### save, s
Saves the current state of all dependencies to the `.gitdeps` file, updating commit hashes to match current checkouts.

### state
Shows the current state of all dependencies including paths, URLs, branches, and current commit hashes.

### import, im [*path*]
Imports existing Git repositories from a directory (defaults to `deps/`) into the `.gitdeps` file.

## OUTPUT FORMAT

All git-deps commands use a consistent output format:

- **→** (arrow) - Main actions and operations being performed
- **…** (ellipsis) - Progress steps and intermediate operations  
- **✱** (star) - Success messages, completion status, and helpful tips
- **!!! ERR** - Error messages, followed by helpful tips when available

This provides clear visibility into what the tool is doing and helps with troubleshooting when issues occur.

## STATUS CODES

Dependencies can have the following statuses:

- **ok-same** - Current checkout matches expected revision
- **ok-behind** - Current checkout is behind expected revision (can fast-forward)
- **ok-ahead** - Current checkout is ahead of expected revision
- **ok-synced** - Current checkout is synced with remote
- **maybe-ahead** - Current revision may be ahead or behind (needs manual resolution)
- **no-modified** - Repository has local modifications
- **no-unsynced** - Current version is not synced with remote
- **missing** - Dependency directory does not exist
- **err-

*** - Various error conditions

## ENVIRONMENT

**GIT_DEPS_MODE**  
Set to "jj" to force jj mode, otherwise auto-detected

**GIT_DEPS_FILE**  
Path to dependencies file (default: ".gitdeps")

**NO_COLOR**  
Disable colored output when set

## FILES

**.gitdeps**  
Dependencies specification file

## EXAMPLES

**Add a new dependency:**
```bash
# Add a dependency and clone it
git-deps add deps/library git@github.com:user/library.git main

# Add with specific commit
git-deps add deps/tool git@github.com:user/tool.git v1.2.3 abc1234

# Force add over existing dependency
git-deps add -f deps/library git@github.com:user/updated.git main
```

**Initial project setup:**
```bash
# After cloning a project with .gitdeps, checkout dependencies
git-deps checkout
```

**Get latest updates:**
```bash
# Check current status
git-deps status

# Update to latest from remotes
git-deps update

# If you want the exact pinned versions instead
git-deps update --pinned

# Save the new state after testing
git-deps save
```

**Working with local changes:**
```bash
# Make changes in a dependency
cd deps/mylib
# ... make changes and commit ...
cd ../..

# Try to update - will fail due to unpushed commits
git-deps update
# !!! ERR Cannot update deps/mylib: has unpushed commits
# → Push changes first: cd deps/mylib && git push

# Push changes, then update
git-deps push
git-deps update
```

**Import existing dependencies:**
```bash
git-deps import deps/
git-deps save
```

## EXIT STATUS

Returns 0 on success, non-zero on error.

## SEE ALSO

git-submodule(1), git(1), jj(1)

## AUTHOR

Written by Sebastien Pierre.

## REPORTING BUGS

Report bugs at: https://github.com/sebastien/git-deps

## COPYRIGHT

This is free software; see the source for copying conditions.
