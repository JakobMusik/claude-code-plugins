---
name: publish
description: Publish a clean commit to the public remote — apply the private working branch's new work onto the remote tip and strip the REMOTE_EXCLUDE (local-only) paths, leaving the planning/agent files behind. Use this when the user wants to "publish", "push a clean version", "update the remote without the private files", "release this phase", or "make a clean commit for the remote" in a repo set up with clean-remote. Never pushes on its own and never touches your working tree; it hands back the exact push command.
version: 0.1.0
---

# clean-remote: publish

Build **one clean commit** for the current dev branch's public counterpart — carrying only the
new work since that branch's last publish, with the local-only (`REMOTE_EXCLUDE.md`) paths
stripped — ready for you to push.

Each dev branch publishes to its **own** public branch (`branch.<name>.cleanRemotePublish`, else
the `clean-remote.publishBranchTemplate` applied — `%s` = same name). Publish acts on the
**current branch** by default; pass `--branch <name>` to target another.

## When to use
The user wants to update the public remote from their dev branch without the planning/agent-helper
files — "publish", "release this phase", "push a clean version". The repo must already be set up
(the `setup` skill); if config is missing, run `setup` first.

## What it guarantees
- **Never pushes** — it leaves a branch holding the clean commit and prints the push command.
- **Never touches your working tree** — all work happens in an ephemeral worktree. On an existing
  public branch the clean commit's parent IS its tip, so your push fast-forwards and history stays
  linear; the **first** publish creates the public branch as a clean orphan snapshot.
- The commit's tree has **no `REMOTE_EXCLUDE` paths** — the pre-push guard is the backstop.

## Do it
Be on the dev branch you want to publish (or pass `--branch`). Pick a clear commit message (read
the branch's recent commits to summarize the work, and match the remote's commit style). Then:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh" "<commit message>"
# or target a specific branch:
sh "${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh" --branch <dev-branch> "<commit message>"
```

The script prints three commands — **review**, **push**, **tidy**. Relay them to the user
and recommend they review the diff (`git diff <remote>/<branch>..<the printed branch>`)
before pushing. Do **not** run the push yourself unless the user explicitly asks.

**Dead-reference warning → offer to chain `scrub-refs`.** After building the commit, publish runs
a read-only check for references — links, imports, mentions — that the *published* files still
make to the private paths it just stripped (those go dead on the public remote). If any exist it
prints a fourth **`refs`** line with a count. The script itself only *detects* — it never edits or
blocks. When that line appears, **offer to run the `scrub-refs` skill** on the built branch
(`--ref clean-remote/publish-<dev>-NNN`): that skill decides each hit (rewrite / strip / leave),
applies the edits, and **amends** them into this same commit — so the public branch still gets
exactly one commit and your source stays untouched. Don't push until the refs are resolved that
way or the user declines. No `refs` line means nothing published points at a private path — go
ahead and relay the push command.

If it reports "nothing to publish", the remote is already in sync — say so. If it reports a
conflict, the public branch changed the same lines as your new work; surface it and let the
user reconcile rather than forcing it.
