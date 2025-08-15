# Status Command

We want to update the status command so that for each repository to shows:

```
 ✱ PATH
 … │ dep      [BRANCH] COMMIT STATUS DATE
 … │ local    [BRANCH] COMMIT (+N) STATUS DATE
 … │ remote   [BRANCH] COMMIT (+N) STATUS DATE
```

Where `DATE` is the date of the `BRANCH|COMMIT` available.

Where status is a combination for `dep` is, coloring in `[]`
- `behind[yellow]` when dep is behind local or remote
- `ahead[orange]` when dep is ahead of local
- `unavailable[red]` when the repo is not available
- `missing[red]` when the given BRANCH/COMMIT is not available in the remote
- `synced[green]` exactly as local, no uncommited changes
- `outdated[orange]` when the local is different from `dep`

For `local`:
- `missing[gray]` when the local is not there
- `behind[yellow]` when local is behind remote
- `ahead` when local has changes not available in remote
- `conflict[red]` when there is a conflict between local and remote
- `uncommited[gold]` when local has uncommited changes
- `synced[green]` exactly as dep, no uncommited changes

Where status is a combination for `remote` is:
- `unavailable[gray]` when the repo is not available
- `missing[red]` when the given BRANCH/COMMIT is not available in the remote
- `behind[yellow]` when remote is behind local
- `ahead` when remote has changes not available in local
- `synced[green]` when exactly as dep or local

This affects the logic for `git-deps update` (implement
in `git_deps_update` and `git-deps-update`):
- An update can only be performed is there is no `uncommited` local changes
- An update would ask for confirmation and warn if changing the local branch
  or commit if the local branch or commit is not available in the remote.

## Implementation

In `src/sh/git-deps.sh` add:
- `git_deps_status_dep PATH REPO BRANCH COMMIT?`
- `git_deps_status_local PATH REPO BRANCH COMMIT?`
- `git_deps_status_remote REPO BRANCH COMMIT?`

Then:
- Remove `git_deps_status` in favor of the specific `git_deps_status_*`
- Update `git-deps-status` to reflect that.
- Update `git_deps_update` to support the new format
- Write a test case `tests/cli-status.sh` using `tests/lib-testing.sh` to exercise the above. Use an standard Github test repo as an example.

## Corrections

### Round 1

First the local changes number should be the number of commits not in remote,

```
 … │ local    [main] eb5d41a57f3d44c46333ce7904304d5157e10fea (+65) uncommited 2025-08-11
```

Here remote should be `behind` as it's behind `local`:

```
 ✱ REPO
 … │ dep      [main] 1bfe7006065a4eda07dda04b7fdf215cc6a49f2b behind 2025-01-03
 … │ local    [main] eb5d41a57f3d44c46333ce7904304d5157e10fea (+65) uncommited 2025-08-11
 … │ remote   [main] 32068a15c02f3ccb20cce3ac173214e8e672a3fc ahead 2025-07-20
 ```

Here local should be `behind` and `changed` at the same time:

```
  ✱ deps/ldk
 … │ dep      [main] aa9a5f2a4369f92f8ce04bbe6c51eaa64d7a2fc2 behind 2024-10-12
 … │ local    [main] a8aceabf5a88d4379f3d4464e458d125c9e3df3e (+6) behind 2025-04-12
 … │ remote   [main] 5167400c81e3f5d6c3719691f05b2bb55cecec05 (+1) ahead 2025-07-18
 ```


Here `local` should be `ahead changed` at the same time:

```
 ✱ deps/extra
 … │ dep      [main] ada851ca94f1abc50b7682d98bc505c9e0777161 behind 2024-11-17
 … │ local    [main] 83b248c39896868b5903b6ddce1bf973b214c35b (+30) changed 2025-08-16
 … │ remote   [main] 118cdfe672eee771887e98f3b44939d0e553340c ahead 2025-08-16

```

Here remote should be `synced` as exactly as `dep`.

```
 ✱ deps/storage
 … │ dep      [main] fd7194b682f81ff536df607f8a4793f142bc80bd synced 2023-06-26
 … │ local    [main] fd7194b682f81ff536df607f8a4793f142bc80bd synced 2023-06-26
 … │ remote   [main] fd7194b682f81ff536df607f8a4793f142bc80bd ahead 2023-06-26
```

Lastly, can you move the (+N) at the end after the date.

### Round 2

We introduce the following change:

- `synced[green]` when exactly **as dep or local**

Now here `local` should be `ahead uncommited` as it has two commits ahead of remote:

```
 ✱ deps/lui
 … │ dep      [main] 1bfe7006065a4eda07dda04b7fdf215cc6a49f2b behind 2025-01-03
 … │ local    [main] eb5d41a57f3d44c46333ce7904304d5157e10fea uncommited 2025-08-11 (+2)
 … │ remote   [main] 32068a15c02f3ccb20cce3ac173214e8e672a3fc behind 2025-07-20
```

Here `remote` should be `synced` as it's the same as `local`

```
 ✱ deps/ltjs
 … │ dep      [main] 1d1ad3811e33903dca68e7782040f0fb94515078 behind 2025-02-18
 … │ local    [main] a0092d67677e06325179b7a0b2a8f6c015d39f97 uncommited 2025-04-12
 … │ remote   [main] a0092d67677e06325179b7a0b2a8f6c015d39f97 behind 2025-04-12
 ```

Here `remote` should be synced

```
✱ deps/storage
 … │ dep      [main] fd7194b682f81ff536df607f8a4793f142bc80bd synced 2023-06-26
 … │ local    [main] fd7194b682f81ff536df607f8a4793f142bc80bd synced 2023-06-26
 … │ remote   [main] fd7194b682f81ff536df607f8a4793f142bc80bd behind 2023-06-26
 ```

Further changes:
- Make the status `behind` `YELLOW` for all (include dep)
- Dep `behind[yellow]` when dep is **behind local or remote**
- Remove `changed[orange]` status from local
- Add dep `outdated[orange]` when the local is different from `dep`

