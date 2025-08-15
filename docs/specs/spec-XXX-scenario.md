# Git Deps Scenario

This is a typical scenario to illustrate Git deps.

Step 1: Create a repository (say `hello-git-deps)

```
mkdir hello-git-deps
cd hello-git-deps
git init
```

Step 2: Add your dependencies

```
git-deps add git@github.com:sebastien/git-kv.git deps/git-kv
git-deps add git@github.com:sebastien/appenv.git deps/appenv
```

Step 3:
