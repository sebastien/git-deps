# Git Deps Add

We introduce the new command  `git-deps add REPO_PATH REPO_URL [BRANCH] [COMMIT]` that:

- Command fails if `REPO_PATH` already exists or is already registered
- Adds a new entry in `.gitdeps` (or `.jjdeps`) for `REPO_PATH` using `REPO_URL` and
  optional `BRANCH` and `COMMIT`
- Clones and checks out the entry at the correct branch and revision.
- Will show warning if the branch and revision don't exist

## Implementation

In `src/sh/git-deps.sh`:

- Add a new `git-deps-add` entry
- Register the command in `git-deps`
