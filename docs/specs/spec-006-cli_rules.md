# Git-Deps CLI rules

## Purpose

Output should answer three questions: **what changed, what went wrong, and what
should I do next?** Successful routine work should not obscure those answers.
These rules apply equally to `git-deps`, `jj-deps`, and their command aliases.

## Core rules

- Only output something if there is a change; otherwise output nothing.
- When outputting a commit ID, include a datetime `YYYY-MM-DD HH:MM:SS` in local time.
- When displaying an error, show where it happened (dependency, repository, or configuration) and why.
- When there is an error, offer a tip for the next action to take.
- Represent the same thing the same way across commands.
- Keep style and formatting consistent.

## Silence and exceptions

### Commands that change state

Successful no-op `checkout`, `update`, `pull`, `save`, `import`, and `fix`
operations must produce **zero output on both stdout and stderr**. This includes:

- Already being on the requested branch or commit.
- Already being up to date with the remote.
- Skipping an existing dependency with `checkout --missing`.
- Saving or importing an unchanged dependency configuration.
- Fixing an already-clean configuration file.
- Processing an empty, valid dependency configuration.

A change means an effective change to a dependency checkout or configuration,
not merely fetching, consulting cached refs, or refreshing cache timestamps.
Configuration no-ops should not rewrite files just to normalize incidental
formatting; `fix` is the explicit command for formatting repairs.

Do not print operation headings, progress chatter, unchanged/skipped results,
timings, blank separator lines, or routine completion summaries. In a batch,
report only dependencies that changed or encountered a problem.

### Requested data and diagnostics

Silence must not hide information the user explicitly requested or needs to act on:

- Help, `list`, `state`, and `status` still return their requested information,
  even when nothing changed. They must not add incidental progress chatter.
- Explicit dry runs return the proposed result without claiming it was applied.
- Errors and safety warnings remain visible, even if the operation changed nothing.
- Necessary confirmation prompts remain visible and identify the affected dependency.

An intentional skip such as `checkout --missing` is not a warning. A blocked
operation, failed network request, or invalid configuration is not a successful
no-op. Do not turn an existing-path conflict into silent success.

## Successful changes

Report a successful change **after it succeeds**, not as a prediction. Use one
concise result line per changed dependency; configuration-wide repairs may use
one line identifying the configuration file.

- Identify the dependency by its configured workspace path, including symlink spelling.
- Describe the outcome: added, removed, cloned, checked out, updated, or saved.
- Include the branch when it clarifies the operation.
- For commit transitions, show the old and new commits with `→` between them.
- Do not repeat the same result in a helper message, per-dependency result, and footer.
- If one dependency fails, do not describe the whole batch as successful; preserve
  visibility of any changes that did succeed.

## Commit representation

Use the same human-readable representation everywhere:

```text
<full-commit-id> (YYYY-MM-DD HH:MM:SS)
```

The datetime is the commit's **committer date**, converted to the user's local
timezone (respecting `TZ` when set). It is not the command execution time or the
commit's original timezone offset. Do not use ISO `T` separators, `Z` suffixes,
or timezone offsets in this representation.

If the commit cannot be resolved locally, use:

```text
<requested-commit-id> (date unavailable)
```

Do not invent a date, use today's date, or perform a network operation solely to
decorate an error message. A branch name and `unknown` are not commit IDs.

This rule applies to human-readable diagnostics, including errors. It does not
change `.gitdeps` fields, internal result records, or the machine-readable
`state` output (`PATH URL BRANCH COMMIT`).

## Errors and safety warnings

Every problem report must include:

1. **Where:** the dependency path, repository URL/remote when relevant, or
   configuration file and line number for a malformed entry.
2. **What and why:** the operation that failed and its concrete cause. Preserve
   useful Git/Jujutsu diagnostics rather than replacing them with only “failed”.
3. **Next action:** a specific, safe tip related to that cause.

Examples of useful tips include checking a remote URL or repository access,
inspecting available branches, correcting a saved pin, or committing/stashing
local changes. Usage errors should identify the invalid command, option, or
missing argument and direct the user to the relevant help.

- Use `Tip:` consistently; do not expose internal codes such as `err-fetch-failed`.
- Avoid duplicate reports of the same failure at helper and command levels.
- Keep useful multiline details readable rather than dumping an operation transcript.
- Do not expose credentials embedded in repository URLs or diagnostics.
- Do not suggest deleting a dependency directory as routine recovery.
- Do not suggest `--force` for failures it cannot resolve, or imply that it can
  safely discard uncommitted work.
- Do not promise that `checkout` will ignore a saved pin or fetch unavailable commits.
- Output suppression must not alter command exit codes or existing safety behavior.

## Streams and formatting

- **stdout:** requested data, such as help, lists, state records, or dry-run results.
- **stderr:** change notifications, warnings, errors, tips, and confirmation prompts.
- Use `✓` for successful changes, `⚠` for warnings, and `✗` for errors.
- Use `[dependency/path]` as the common dependency context; use `[.gitdeps:LINE]`
  for configuration-entry problems.
- Omit batch counters such as `1/1` and leading or trailing semicolons.
- Use consistent capitalization, spacing, commit formatting, and outcome wording.
- Keep ANSI color optional. Respect `NO_COLOR`; redirected/non-interactive output
  should not contain terminal control sequences. Meaning must not depend on color.
- Quote paths safely in suggested shell commands, especially paths containing spaces.

## Examples

Successful no-op:

```text
$ git-deps update
$
```

Changed dependency (hashes shown as placeholders):

```text
 ✓ [deps/select.js] Updated on main: <old-id> (2026-10-07 09:12:03) → <new-id> (2026-10-08 10:25:41)
```

Failed fetch:

```text
 ✗ [deps/select.js] Fetch failed from origin (https://example.com/select.git): Could not resolve host: example.com
   Tip: check network connectivity and `git -C 'deps/select.js' remote -v`.
```

Blocked checkout:

```text
 ⚠ [deps/select.js] Cannot checkout: has uncommitted changes
   Tip: inspect `git -C 'deps/select.js' status`, then commit or stash changes before retrying.
```

Invalid configuration:

```text
 ⚠ [.gitdeps:4] Incomplete entry for deps/select.js: expected path, URL, and branch
   Tip: correct the entry, or review `git-deps fix --dry-run` before applying repairs.
```

## Acceptance checks

- Run each no-op mutation twice against local test repositories; assert empty
  stdout and stderr, success status, and unchanged checkout/configuration state.
- Test a batch containing changed and unchanged dependencies; only changed
  dependencies receive success lines, with no heading or footer.
- Check changed results are emitted only after success, and failures do not
  receive success notifications.
- Test normal, pinned, date-selected, and missing-only checkout/update paths.
- Test local-time formatting with a non-UTC `TZ`, and unresolved commit dates.
- Test clone/fetch/checkout failures, malformed entries, invalid arguments, and
  safety blocks for context, underlying reason, actionable tip, and exit status.
- Verify help, list, state, status, and dry-run output remain usable; machine-readable
  records must not acquire colors, dates, or diagnostic text.
- Verify `NO_COLOR`, redirected output, safe command quoting, and credential redaction.
