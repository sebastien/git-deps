```
  _____ _ _      ____
 |   __|_| |_   |    \ ___ ___ ___
 |  |  | |  _|  |  |  | -_| . |_ -|
 |_____|_|_|    |____/|___|  _|___|
                          |_|
```


`git-deps` (and `jj-deps`) is a Git submodule alternative with the following
features:

- Works with both `git` and `jj`
- Ensures that your clones always succeed, even if your dependencies are
  not available anymore.


# Quick start

In your repository create a `.gitdeps` file keeps track of your dependencies:

```
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


