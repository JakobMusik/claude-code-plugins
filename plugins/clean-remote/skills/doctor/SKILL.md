---
name: doctor
description: Check that the clean-remote workflow is correctly set up and safe to publish — verifies the pre-push guard is installed, worktree.baseRef=head, REMOTE_EXCLUDE.md lists itself, the private branch shares history with the remote, no private paths have already leaked onto the public remote, and no REMOTE_EXCLUDE path is also gitignored. Use this when the user asks to "check clean-remote", "verify the setup", "is it safe to publish", "did anything leak to the remote", or wants to diagnose the local-overlay / clean-remote configuration.
version: 0.1.0
---

# clean-remote: doctor

Report whether the clean-remote workflow is correctly configured and safe to publish.

## When to use
The user wants to verify the setup, check before publishing, or confirm nothing private has
already reached the public remote.

## Do it
Read-only — it changes nothing. It reports shared plumbing once, then the **current branch**
against its own public branch. Add `--all` to scan every managed dev branch (one with a publish
override, a committed `REMOTE_EXCLUDE.md`, or an existing remote counterpart):

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"        # current branch
sh "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh" --all  # every managed branch
```

Then interpret the output for the user. The lines that matter most (now reported per branch):
- **pre-push guard installed** — without it, the exclusion is only a habit, not enforced.
- **`"<branch>" has NO common history with <remote>/<branch>`** — publishing would conflict;
  the branch diverged. This is the failure mode to flag loudly.
- **private paths ALREADY on `<remote>/<branch>`** — something leaked previously; the listed
  paths are public and need scrubbing from history (a separate, deliberate cleanup).
- **paths in BOTH REMOTE_EXCLUDE.md and .gitignore** — contradictory: a gitignored path is
  never committed, so it has no local history for `publish` to strip. Tell the user to keep
  each path in one list — drop it from `.gitignore` to track it locally, or from
  `REMOTE_EXCLUDE.md` if it's just scratch.

If anything reads `[FAIL]`, point the user at `setup` (to install/repair) or explain the
divergence/leak. If it's all `[ ok ]`, say it's safe to publish.
