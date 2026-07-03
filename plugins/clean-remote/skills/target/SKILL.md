---
name: target
description: Show or change which public remote branch a local dev branch publishes to under clean-remote. Use when the user wants to "change the publish branch", "publish this branch to a different remote branch", "rename/remap/retarget the public branch", "where does this branch publish", "see the branch -> public-branch mapping", or set/clear a per-branch public-branch override. A safe front-end over branch.<name>.cleanRemotePublish; config-only, never pushes.
version: 0.1.0
---

# clean-remote: target

Show or change the **public branch** a local dev branch publishes to. Each dev branch maps to
its own public branch: the per-branch override `branch.<name>.cleanRemotePublish` if set, else
the repo template `clean-remote.publishBranchTemplate` (`%s` = same name). This skill is a
discoverable, validated front-end over that git config — it is **config-only**: it never pushes
and never touches your working tree, and a change just takes effect on the next `publish`.

## When to use
The user asks where a branch publishes, wants the full branch → public-branch map, or wants to
point a branch at a differently-named public branch (e.g. `feat/login` → `release/login`). For
the overall model and one-time stamping, see the `setup` skill.

## Do it
```bash
# show every local branch -> its public branch (override vs template marked)
sh "${CLAUDE_PLUGIN_ROOT}/scripts/target.sh"

# point a branch at a different public name (default: the current branch)
sh "${CLAUDE_PLUGIN_ROOT}/scripts/target.sh" --branch <dev-branch> <public-name>

# drop the override -> fall back to the same-name template
sh "${CLAUDE_PLUGIN_ROOT}/scripts/target.sh" --branch <dev-branch> --unset
```

Re-runnable and idempotent — setting the same value twice is a no-op, and it prints the
before → after mapping.

> Heads-up the script surfaces: repointing a branch that has **already published** re-baselines
> on the new target — the old public branch is left as-is (not deleted, not updated), and if the
> new target doesn't exist yet the first publish *creates* it as a clean snapshot. Run the
> `doctor` skill afterwards to confirm the mapping and that the new target shares history.
