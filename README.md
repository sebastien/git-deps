```
  _____ _ _      ____
 |   __|_| |_   |    \ ___ ___ ___
 |  |  | |  _|  |  |  | -_| . |_ -|
 |_____|_|_|    |____/|___|  _|___|
                          |_|
```


`git-deps` (and `jj-deps`) is a Git submodule alternative that simplifies
working with multi-repository projects, and resolves some of the problems
with `git submodules`, in particular:

- Cloning will always succeed: cloning won't fail if a dependency is missing.
- No problem with recursive submodules: dependencies are only pulled/updated
  for the current repository.
- Easy to spot differences and update: the CLI makes it very easy to see the
  state of dependencies.
- Works with both `git` and `jj`

```
▷ git-deps status
 ▶ Checking dependency status…
 ⋯ Fetching updates in parallel (max 4 concurrent)…
 ⋯ Parallel fetch complete
┌─ deps/sdk
├─ Checking deps/sdk…
├─ Skipping recently fetched repo: deps/sdk
├─ deps/sdk updated
├─ dep      ✓ [SYNCED] [main] 31e5d3d37b5cf83e976fb1a2137c4ffeef3b58d0 2026-01-21
├─ local    ✓ [SYNCED] [main] 31e5d3d37b5cf83e976fb1a2137c4ffeef3b58d0 2026-01-21
├─ remote   ✓ [SYNCED] [main] 31e5d3d37b5cf83e976fb1a2137c4ffeef3b58d0 2026-01-21
└─ deps/sdk ✓ [SYNCED]
┌─ deps/ui
├─ Checking deps/ui…
├─ Fetching updates (this may take a moment…)
├─ dep      ✓ [SYNCED] [main] 0d891b3aaa953f9fd17951340c68b0ee72e8d494 2026-01-23
├─ local    ✓ [SYNCED] [main] 0d891b3aaa953f9fd17951340c68b0ee72e8d494 2026-01-23
├─ remote   ✓ [SYNCED] [main] 0d891b3aaa953f9fd17951340c68b0ee72e8d494 2026-01-23
└─ deps/ui ✓ [SYNCED]
┌─ deps/services
├─ Checking deps/services…
├─ Fetching updates (this may take a moment…)
├─ dep      ⚠ [OUTDATED] [main] 7a1f1f753ad4a6c940c932b1fb4611fc4275491f 2026-01-21
├─ local    ↓ [BEHIND] [main] bd2bc6ca3949fb3c171c190a5ab0ea5a650da243 2026-01-23 (+119)
├─ remote   [MISSING] [main] origin/SP-789-RunWorkflowsLocally
└─ deps/services ↓ [BEHIND]
```

# Quick start

Add dependencies to your project using `git-deps add`:

```bash
git-deps add deps/appenv git@github.com:sebastien/appenv.git master
git-deps add deps/git-kv git@github.com:sebastien/git-kv.git main
```

`git-deps status` will tell you the status of the dependencies, whether they're
checked out or not

```
$ git-deps status
deps/appenv master ok-same
deps/git-kv main ok-same new commits…
```

To bring your dependencies up to date, do `git-deps pull`, this will likely
succeed, unless you have local changes or have unsynced changes.

```
deps/appenv|git@github.com:sebastien/appenv.git|master
ok-same
 → [deps/appenv] Pulling master…
From github.com:sebastien/appenv
 * branch            master     -> FETCH_HEAD
Already up to date.
```

To push changes, `cd` into your dependency directory and use standard git commands (`commit`, `push`) to resolve any issues. `git-deps push` is not yet implemented.

Whenever you want to save the current state of your dependencies, do  `git-deps save`.

# Commands

- `git-deps add <path> <url> [branch] [commit]` - Add a new dependency
- `git-deps remove [--force] <path>...` - Remove one or more dependencies from `.gitdeps`
- `git-deps checkout [--force] [--missing] [PATH...]` - Checkout dependencies to their configured state (`--missing` clones only absent ones; never discards uncommitted changes)
- `git-deps import [--recursive] [PATH...]` - Import existing repositories from one or more paths (defaults to `deps/`)
- `git-deps pull [--force] [PATH...]` - Pull updates for dependencies
- `git-deps save [--safe]` - Save the current state (commit hashes) of dependencies to `.gitdeps` (`--safe` saves the nearest cached remote ancestor)
- `git-deps fix [--dry-run] [--branch NAME]` - Repair `.gitdeps` (strip extra fields, drop unusable lines, deduplicate paths)
- `git-deps status [PATH...]` - Show the status of dependencies
- `git-deps update [--pinned] [--force] [PATH...]` - Update dependencies to latest from remote

# Format


The `.git-deps` file format is a list of tab or space separated fields:

- Dependency local path, e.g. `deps/repo`
- Repository URL, e.g. `git@github.com:user/repo.git`
- Repository branch/tag/commit `main`
- Optional: specific commit that overrides the previous, e.g. `5fc4a3412`

```
deps/appenv git@github.com:sebastien/appenv.git master  fcbd00e34ba2ba0232f446e8f37ab287426d1094
```
