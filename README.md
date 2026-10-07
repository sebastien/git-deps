```
 ▄▀▀▀▀▀▀▀▀▀█ █▀▀▀▀█ █▀▀▀▀▀▀▀▀▀▀█      █▀▀▀▀▀▀▀▀▀▄   ▄▀▀▀▀▀▀▀▀▀█ █▀▀▀▀▀▀▀▀▀▄  █▀▀▀▀▀▀▀▀▀▀▓
█·   ▄▄▄▄▄▄█ ▀    ▓ █▄▄▄·   ▄▄▄█      ▀    ▄▄ .  █ █·   ▄▄▄▄▄▄█ ▀    ▄▄  ∙ █ ▀    ▄▄▄ ∙ ▒
▓  . ▓ ▄▄▄▄▄ ▓    ▓    ▓  . ▓         ▓    ▓ ▌   ▓ ▓  . ▓▄▄▄▄▄▄ ▓    ▓▄▌   ▓ ▓    ▓ ▀▀▀▀▀
▒ ∙  ▒ ▄   ▒ ▒   ·▒    ▒ ∙  ▒         ▒  · ▒▄▓   ▒ ▒ ∙  ▄▄▄▄▄▄▒ ▒   ·▄▄▄▄▄▀  ░▄▄▄ ▀▀▀▀▀▀▒
░    ░▄░   ░ ░ .  ░    ░    ░         ░       ·. ░ ░    ░▄▄▄▄▄▄ ░ .  ░       ▄▄▄▄▄  ▒  .░
█    .    ·█ █    █    █    █         █   .      █ █    .    ·█ █    █       ▓   ▀▀▀▀∙  █
█▄▄▄▄▄▄▄▄▄▄█ █▄▄▄▄█    █▄▄▄▄█         █▄▄▄▄▄▄▄▄▄▄█ █▄▄▄▄▄▄▄▄▄▄█ █▄▄▄▄█       ░▄▄▄▄▄▄▄▄▄▄█
```


`git-deps` (and `jj-deps`) is a Git submodule alternative that simplifies
working with multi-repository projects, and resolves some of the problems
with `git submodules`, in particular:

- *Safer*: cloning will always succeed, even when a dependency is missing,
  transitive dependencies won't trigger a cloning cascade.
- *Easier*: easy commands to check the status of dependencies, update them,
  pull them, etc.
- *Versatile*: works with both `git` and `jj`

The version control mode is detected automatically; `jj-deps` runs the same
tool in Jujutsu mode.

`git-deps status` reports the saved (`dep`), local (`local`) and remote
(`remote`) state of each dependency on a single line:

```
$ git-deps status
 ✓ [deps/sdk] dep=✓ [SYNCED] [main] 31e5d3d37b5cf83e976fb1a2137c4ffeef3b58d0 2026-01-21 10:04:12 | local=✓ [SYNCED] [main] 31e5d3d37b5cf83e976fb1a2137c4ffeef3b58d0 2026-01-21 10:04:12 | remote=✓ [SYNCED] [main] 31e5d3d37b5cf83e976fb1a2137c4ffeef3b58d0 2026-01-21 10:04:12
 ⚠ [deps/services] dep=⚠ [OUTDATED] [main] 7a1f1f753ad4a6c940c932b1fb4611fc4275491f 2026-01-21 08:30:00 | local=↓ [BEHIND] [main] bd2bc6ca3949fb3c171c190a5ab0ea5a650da243 2026-01-23 17:12:44 (+119) | remote= [MISSING] [main] origin/SP-789-RunWorkflowsLocally
```

# Quick start

Add dependencies to your project using `git-deps add`:

```bash
git-deps add deps/appenv git@github.com:sebastien/appenv.git master
git-deps add deps/git-kv git@github.com:sebastien/git-kv.git main
```

Each successful addition is reported once:

```
$ git-deps add deps/appenv git@github.com:sebastien/appenv.git master
 ✓ [deps/appenv] Added from git@github.com:sebastien/appenv.git on master at a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 (2026-01-21 10:04:12)
```

`git-deps status` then tells you the state of the dependencies, whether they're
checked out or not (see the sample above).

To bring your dependencies up to date, use `git-deps update` (fetch and
fast-forward to the latest branch commit) or `git-deps pull` (git pull per
dependency). These succeed unless a dependency has uncommitted or unpushed
changes, in which case it is skipped with a warning:

```
$ git-deps pull
 ✓ [deps/appenv] Updated on master: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 (2026-01-21 10:04:12) → b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0 (2026-01-23 17:12:44)
```

To push changes, `cd` into your dependency directory and use standard git
commands (`commit`, `push`). `git-deps push` is not yet implemented.

Whenever you want to save the current state of your dependencies, run
`git-deps save`.

# Commands

- `git-deps add [-f|--force] <path> <url> [branch] [commit]` - Add a new dependency (clone it and record it in `.gitdeps`)
- `git-deps remove [-f|--force] <path>...` (`rm`) - Remove one or more dependencies from `.gitdeps` (does not delete directories)
- `git-deps list [glob]` (`ls`) - List registered dependencies, optionally filtered by a glob
- `git-deps status [--offline] [--timeout=SECONDS] [--parallel=N] [--no-parallel] [PATH...]` (`st`) - Show the status of dependencies
- `git-deps checkout [-f|--force] [-m|--missing] [PATH...]` (`so`) - Check out dependencies to their saved state (local-only; `--missing` clones only absent ones and never discards uncommitted changes)
- `git-deps update [--pinned] [-t|--at [DATETIME]] [-f|--force] [PATH...]` (`up`) - Update dependencies to the latest from remote, or to their state at a date
- `git-deps pull [-f|--force] [PATH...]` (`pl`) - Pull updates for dependencies
- `git-deps push [PATH...]` (`ph`) - Push changes in dependencies (not yet implemented)
- `git-deps save [-s|--safe]` (`s`) - Save the current commit hashes of dependencies to `.gitdeps` (`--safe` saves the nearest cached remote ancestor)
- `git-deps fix [-n|--dry-run] [-b|--branch NAME]` (`fx`) - Repair `.gitdeps` (strip extra fields, drop unusable lines, deduplicate paths)
- `git-deps import [-r|--recursive] [PATH...]` (`im`) - Import existing repositories (defaults to `deps/`)
- `git-deps state` - Print the machine-readable state (`PATH URL BRANCH COMMIT`) of each dependency
- `git-deps help` - Show available commands and usage

Run any command with `--help` for its full options, or see
[`docs/manual.md`](docs/manual.md) for the complete reference.

# Format

The `.gitdeps` file format is a list of tab or space separated fields:

- Dependency local path, e.g. `deps/repo`
- Repository URL, e.g. `git@github.com:user/repo.git`
- Repository branch/tag/commit `main`
- Optional: specific commit that overrides the previous, e.g. `5fc4a3412`

Blank lines and lines starting with `#` are ignored.

```
deps/appenv git@github.com:sebastien/appenv.git master  fcbd00e34ba2ba0232f446e8f37ab287426d1094
```

# Development

```bash
make test    # Run the test suite
make lint    # shellcheck
make fmt     # shfmt
make shell   # Interactive shell with git-deps in PATH
make install # Symlink the tools into ~/.local/bin
```
