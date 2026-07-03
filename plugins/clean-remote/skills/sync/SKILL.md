---
name: sync
description: Pull external public commits — e.g. a contributor PR merged onto the clean public branch — back into your private source branch, so the private branch stays a superset of the public one. Use this when the user wants to "sync from the remote", "pull the merged PR back", "integrate contributor changes", "bring public commits into my private branch", or after a PR lands on the public remote in a repo set up with clean-remote. The reverse of publish. Never mutates your branch in place; it hands back the exact apply command.
version: 0.1.0
---

# clean-remote: sync

Integrate work that landed **directly on a public branch** (most often a merged contributor
PR, based on the clean published branch) back into the matching **dev branch** — the reverse
of `publish`. Keeps each dev branch a superset of its public counterpart, so future publishes
stay clean. Acts on the **current branch** by default; pass `--branch <name>` to target another.

## When to use
A PR (or any commit) was merged onto a public remote branch without going through your dev
branch, and you want that work in your source of truth. Symptoms: `doctor` reports "external
commit(s) … not yet in <branch>", or the user says "pull the PR back" / "sync from public".

## What it does / guarantees
- **Selects only external, un-integrated work** — commits on the public branch that aren't your
  own publishes (those carry a `clean-remote-source` trailer) and aren't already in your branch
  (matched by patch-id). Re-running never double-integrates.
- **Never mutates your working tree or branch in place** — it cherry-picks (`-x`, preserving
  provenance) onto an ephemeral `clean-remote/sync-*` branch and prints the apply command.
- **Keeps publish correct** — records the per-branch `branch.<name>.cleanRemoteSyncpoint` so the
  next publish of that branch diffs from *after* the integrated work instead of conflicting
  against a stale base. (Honoured only once you apply the sync, so building it and not applying
  is harmless. Syncing one branch never touches another's bookkeeping.)

## Do it
```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh"
# or target a specific branch:
sh "${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh" --branch <dev-branch>
```

The script prints three commands — **review**, **apply**, **tidy**. Relay them and recommend the
user review the integrated commits (`git log --oneline <source>..<the printed branch>`) before
applying. The **apply** step is a `git merge --ff-only`, so it just fast-forwards your source
branch onto the cherry-picked commits — keep it `--ff-only` so the recorded `syncpoint` stays an
ancestor of your branch (that's what publish relies on). Do **not** apply it yourself unless the
user asks.

If it reports "nothing to sync", the private branch already has every public commit — say so. If
it reports a cherry-pick **conflict**, a public commit touches something your private branch also
changed; surface the named commit and let the user integrate it by hand (`git cherry-pick -x
<sha>`, resolve) and re-run sync for the rest, rather than forcing it.
