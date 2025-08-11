# git-deps add

We introduce the `add` subcommand:

```
git-deps [-f|--force] add REPO PATH BRANCH? COMMIT?
```

The output of this command is

```
 → Adding $REPO to $PATH
 … Cloning $REPO
 … Checking out $BRANCH_OR_COMMIT
 ✱ $REPO[$BRANCH_OR_COMMIT] is now available in $PATH
```

The following errors can happen

```
!!! ERR Dependency already registered at '$PATH'
 ✱  Run git-deps add -f $REPO $PATH $BRANCH $COMMIT
!!! ERR Unable to clone repository: $REPO
!!! ERR Banch '$BRANCH' does not exist in repository: $REPO
!!! ERR Commit '$COMMIT' does not exist in repository: $REPO
```

This command will:

1) First check that the dependency does not already exist
2) Create the parent for the destination PATH if necessary
3) Try to clone the REPO at the given PATH
4) Validate that the BRANCH and or COMMIT exists
5) Checks out the given BRANCH or COMMIT

## Implementation

In `src/sh/git-deps`, add:

- Add `git_deps_has PATH` to test if a dependency is registered at the PATH
- Update `git_deps_op_clone` to do the above checks
- Update `git_deps_op_checkout` to do the above checks
- Add `git_deps_add REPO PATH BRANCH COMMIT` using the above
- Add a `git-deps-add` command and register it in the main
