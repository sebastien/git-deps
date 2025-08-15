# git-deps(1) - Git submodule alternative

## NAME

git-deps, jj-deps - Git submodule alternative for multi-repository projects

## SYNOPSIS

**git-deps** *add* [*-f|--force*] *repo* *path* [*branch*] [*commit*]  
**git-deps** [*subcommand*] [*options*]  
**jj-deps** [*subcommand*] [*options*]

## DESCRIPTION

`git-deps` is a Git submodule alternative that simplifies working with multi-repository projects. It resolves some of the problems with `git submodules` by ensuring clones always succeed even if dependencies are unavailable, and provides loose coupling that makes it more resilient than git submodule.

The tool works with both `git` and `jj` version control systems, automatically detecting which to use based on the repository type and command name.

## CONFIGURATION

Dependencies are tracked in a `.gitdeps` file in the repository root. Each line specifies a dependency with tab or space-separated fields:

- **path** - Local path where dependency should be checked out (e.g., `deps/repo`)
- **url** - Repository URL (e.g., `git@github.com:user/repo.git`)
- **branch** - Branch, tag, or commit to track (e.g., `main`)
- **commit** - Optional specific commit hash that overrides branch

### Example .gitdeps file:
```
deps/appenv	git@github.com:sebastien/appenv.git	master
deps/git-kv	git@github.com:sebastien/git-kv.git	main	fcbd00e34ba2ba0232f446e8f37ab287426d1094
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
$ git-deps add git@github.com:user/library.git deps/library main
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

### pull, pl
Pulls and updates all dependencies from their remote repositories. Clones missing dependencies and pulls updates for existing ones.

**Example:**
```
$ git-deps pull
 → Pulling dependencies
 … Processing 2 dependencies
 … Pulling deps/appenv [master]
 ✱ deps/appenv [master] updated successfully
 … Cloning git@github.com:sebastien/git-kv.git
 … Checking out main
 ✱ git@github.com:sebastien/git-kv.git[main] is now available in deps/git-kv
 ✱ All dependencies pulled successfully
```

### push, ph
Pushes changes in all dependency repositories to their remotes.

### sync, sy
Performs push followed by pull operations on all dependencies.

### save, s
Saves the current state of all dependencies to the `.gitdeps` file, updating commit hashes to match current checkouts.

### state
Shows the current state of all dependencies including paths, URLs, branches, and current commit hashes.

### update, up
Updates dependencies to match the specifications in `.gitdeps`.

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
- **err-\*** - Various error conditions

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
git-deps add git@github.com:user/library.git deps/library main

# Add with specific commit
git-deps add git@github.com:user/tool.git deps/tool v1.2.3 abc1234

# Force add over existing dependency
git-deps add -f git@github.com:user/updated.git deps/library main
```

**Initialize dependencies manually:**
```bash
# Create .gitdeps file manually
echo "deps/lib	git@github.com:user/lib.git	main" > .gitdeps

# Pull dependencies
git-deps pull
```

**Check status and update:**
```bash
git-deps status
git-deps pull
git-deps save
```

**Import existing dependencies:**
```bash
git-deps import deps/
git-deps save
```

## EXIT STATUS

Returns 0 on success, non-zero on error. For pull operations, returns the number of errors encountered.

## SEE ALSO

git-submodule(1), git(1), jj(1)

## AUTHOR

Written by Sebastien Pierre.

## REPORTING BUGS

Report bugs at: https://github.com/sebastien/git-deps

## COPYRIGHT

This is free software; see the source for copying conditions.