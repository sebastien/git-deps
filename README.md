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

- Ensures that your clones always succeed, even if your dependencies are
  not available anymore: checking out a repository will never fail when the
  source repository has moved. This loose coupling makes working with
  `git-deps` more resilient than `git submodule`

- Works with both `git` and `jj`


# Quick start

In your repository create a `.gitdeps` (or `.jjdeps`) file keeps track of your dependencies:

```
# LOCAL PATH | GIT REPOSITORY | TRACKED_BRANCH_OR_COMMIT | SPECIFIC_COMMIT?
deps/appenv|git@github.com:sebastien/appenv.git|master
deps/git-kv|git@github.com:sebastien/git-kv.git|main
```

`git-deps status` will tell you the status of the dependencies, wether they're
checked out or not

```
$ git-deps status
deps/appenv master ok-same
deps/git-kv main ok-same new commits…
```

To bring your dependencies up to data, do `git-deps pull`, this will likely
succeed, unless you have local changes or have unsynced changes.

```
deps/appenv|git@github.com:sebastien/appenv.git|master
ok-same
 → [deps/appenv] Pulling master…
From github.com:sebastien/appenv
 * branch            master     -> FETCH_HEAD
Already up to date.
```

You can try a `git-deps push` to push your changes (in case you have no
local modifications), or alternatively `cd` into your dependency directory
and resolve the problem, typically using a `commit` of your local modifications
and a `merge` or `push`, so that a pull is successful.

Whenever you want to save the current state of your dependencies, do  `git-deps save`.

# Format


The `.git-deps` file format is a list of tab or space separated fields:

- Dependency local path, e.g. `deps/repo`
- Repository URL, e.g. `git@github.com:user/repo.git`
- Repository branch/tag/commit `main`
- Optional: specific commit that overrides the previous, eg `5fc4a3412`

```
deps/appenv git@github.com:sebastien/appenv.git master  fcbd00e34ba2ba0232f446e8f37ab287426d1094
```

# Roadmap

- Sync and import support
- Nicer colored terminal output
- Test suite covering all functions
