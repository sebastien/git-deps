
## State

We should redesign the CLI experience to be much clearer, with a clear
internal model.

```
▷ git-deps state --table
deps/lui git@github.com:sebastien/littleui.js.git main 1bfe7006065a4eda07dda04b7fdf215cc6a49f2b d8c1ec606358a7000e0452f026051ce17873898d
deps/lcss git@github.com:sebastien/littlecss main 433dd0dce5d1032edadb03fbf8a96c17b16da550 433dd0dce5d1032edadb03fbf8a96c17b16da550
deps/ltjs git@github.com:sebastien/littletools.js main  1d1ad3811e33903dca68e7782040f0fb94515078
deps/ldk git@github.com:sebastien/littledevkit main aa9a5f2a4369f92f8ce04bbe6c51eaa64d7a2fc2 a82feba254810629c91776673d12c44b5be29169
deps/extra git@github.com:sebastien/extra main  ada851ca94f1abc50b7682d98bc505c9e0777161
```

```
▷ git-deps state
deps/lui
  source   git@github.com:sebastien/littleui.js.git
  branch   main
  current  1bfe7006065a4eda07dda04b7fdf215cc6a49f2b
  remote   d8c1ec606358a7000e0452f026051ce17873898d
```


### Status

The status of a repository has:

- `local`:
  - `synced`: same as `gitdeps`
  - `outdated`: remote branch commit has different commit than this branch
  - `changed`: has some local modifications, not in remote

```
▷ git-deps status --table
deps/lui  identical
deps/lcss local-changes
deps/ltjs remote-changes
```

```
▷ git-deps status
deps/lui: up to date
deps/lcss: outdated, remote changes available
deps/ltjs: needs merge, remote changes available, local changes
deps/extra: up to date, local changes
```

