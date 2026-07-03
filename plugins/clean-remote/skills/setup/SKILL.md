---
name: setup
description: 'Set up a git repository so planning and agent-helper files (e.g. .planning/, AGENTS/CLAUDE notes, design docs) stay tracked locally with full history but are kept OFF the public remote. Use this when the user wants a "clean remote", to "keep files local but not push them", to "scrub before publishing", to establish the clean-remote / local-overlay workflow, or asks to configure private-files-local-public-remote-clean. Stamps the repo: records config, creates REMOTE_EXCLUDE.md, installs a pre-push guard, and sets worktree.baseRef=head.'
version: 0.1.0
---

# clean-remote: setup

Stamp the current repository for the **clean-remote** workflow — track everything you
want locally (with history), publish a clean public remote.

## The model (read once)
- **Each local dev branch** carries its own local-only files — planning, agent helpers —
  committed with full history, and maps to its **own public squashed branch**. With the
  default template that's the same name (`feat/x` → `origin/feat/x`); override per branch
  with `branch.<name>.cleanRemotePublish`. The dev branches are never pushed directly.
- **`REMOTE_EXCLUDE.md`** (created here) lists those paths, and **lists itself**, so the
  policy is tracked locally but never published. It's read from each branch's own committed
  copy, so different branches can keep different paths private.
- **Publishing** (the `publish` skill) builds one clean commit on the current branch's public
  counterpart — carrying only the new work since that branch's last publish with those paths
  stripped — so each public branch stays clean and linear. The first publish *creates* the
  public branch.
- A **git `pre-push` hook** makes the exclusion enforced, not habitual: it blocks any
  push to the public remote whose tree still contains a private path (checked per branch).
- **`worktree.baseRef=head`** (project-local Claude setting) makes new worktrees branch
  from your real local line, not the stale remote.

## Two lists, never overlapping (the rule for deciding where a path goes)
Every path belongs to exactly **one** list:
- **`REMOTE_EXCLUDE.md`** → files you want tracked locally **with history** but kept off the
  remote: planning notes, agent-helper/instruction files, design drafts, intermediary
  artifacts you want to version while iterating.
- **`.gitignore`** → pure scratch/artifacts that need **no history at all**: `build/`,
  `.claude/worktrees/`, caches, logs, machine-local config (`.claude/settings.local.json` is
  already gitignored by default).

Never put the same path in both. A gitignored path is never committed, so `publish` has no
local history to strip and listing it in `REMOTE_EXCLUDE.md` silently does nothing — you also
lose the very history that was the point. When an agent adds an intermediary/agent-helper path,
it picks the list by this test: *do I want this versioned locally?* yes → `REMOTE_EXCLUDE.md`,
no → `.gitignore`. The `doctor` skill flags any path that ends up in both.

## When to use
The user wants private-but-tracked files kept out of a public remote, or asks to set up /
configure this workflow on a repo. (For *where* a given path goes — `REMOTE_EXCLUDE.md` vs
`.gitignore` — see "Two lists, never overlapping" above.)

## Do it
This is idempotent and only touches local plumbing (config, a hook, a settings file, and
`REMOTE_EXCLUDE.md`). Briefly confirm the repo + private branch with the user if ambiguous,
then run:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
```

Override with env if needed: `CR_REMOTE=<remote>`, `CR_TEMPLATE=<template>` (how a local
branch name maps to its public name; `%s` = same name, e.g. `public/%s`), and
`CR_PUBLISH=<name>` to set the **current** branch's public-branch override explicitly. If the
repo still has the old single-branch config, setup **auto-migrates** it to the per-branch keys.
Re-running is safe and **non-destructive**: existing config is **preserved** (a bare re-run
keeps a customised `clean-remote.remote`/`publishBranchTemplate` and every per-branch override
— pass `CR_REMOTE`/`CR_TEMPLATE`/`CR_PUBLISH` only when you mean to *change* a value), an
existing `REMOTE_EXCLUDE.md` is **kept** (not clobbered), the hook is refreshed, and
`settings.local.json` is merged — so `setup` is the right tool both for first-time stamping and
for repairing a repo after a fresh clone.

**Surface the publish-branch mapping.** `setup.sh` prints the public branch the current branch
maps to (default: the **same name**). After it runs, state that mapping back to the user — and
if they have *not* already named a target (no `CR_PUBLISH`, no existing override) and the
session is interactive, ask whether this branch should publish under a **different** public
name. If so, set it and re-state the result:

```bash
git config branch.<branch>.cleanRemotePublish <public-name>
```

Keep same-name as the zero-friction default: don't ask on non-interactive/headless runs, and
don't re-ask on a re-run where a mapping already exists. To change or inspect the mapping later
— for any branch — use the **`target`** skill.

After it runs: tell the user to **edit `REMOTE_EXCLUDE.md`** to list the paths they want
kept local (it ships with sensible defaults), **commit it on the dev branch**, then use
the `publish` skill. Confirm the result with the `doctor` skill if they want a check.

> The first publish of a branch *creates* its public branch (a clean snapshot), so the public
> branch need not exist yet. If a public branch *does* already exist, a clean publish requires
> it to **share history** with the dev branch (it normally does). `doctor` verifies this and
> flags a no-common-ancestor divergence — setup won't rewrite history; that's a manual reconcile.
