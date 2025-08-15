# Git State

The operation of getting updates from the git remote are quite long. We add
a `.git-deps-state` file in the local directory that has the following format

```
PATH REPO DATE
```

Keeping track of when the given `PATH` was pulled from remote. When a remote
has been queried/fetched, its entry is replaced.

## Implementation

In `src/sh/git-deps.sh`:
- Add `GIT_DEPS_FETCH_DELAY=3600` which by default sets the delay for refresh (in seconds)
- Add `git_deps_op_fetch PATH REPO` registers that `PATH` `REPO` was fetched now in `.git-deps-state`
- Add `git_deps_op_fetched PATH REPO DELAY?` tells if the given PATH REPO was fetched within DELAY=GIT_DEPS_FETCH_DELAY
- Update all functions that get data from the remote and kip the fetching if
  the fetch was registered within 3600s
- Add a flag to all commands `-r|--refresh` that sets the delay to 0, so that
  everything is refreshed.
- Keep track of fetched repo locally so that you don't need to refresh multiple
  times even when GIT_DEPS_FETCH_DELAY is 0. This could be done in
  `git_deps_op_fetched` (register) and `git_deps_op_fetched` (access from registerd).

