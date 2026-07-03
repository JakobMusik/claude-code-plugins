---
name: uninstall
description: Remove the clean-remote workflow plumbing from a repository — deletes the pre-push guard, removes the worktree.baseRef override, and clears the [clean-remote] git config, while LEAVING your REMOTE_EXCLUDE.md, branches, and any published commits intact. Use this when the user wants to "remove clean-remote", "undo the setup", "uninstall the clean-remote workflow", or "stop scrubbing the remote".
version: 0.1.0
---

# clean-remote: uninstall

Remove the clean-remote plumbing while keeping the user's data.

## When to use
The user wants to undo `setup` / stop using the workflow.

## Do it
```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall.sh"
```

It removes the pre-push hook, the `worktree.baseRef` override, the `[clean-remote]` git config,
and the per-branch keys (`branch.<name>.cleanRemotePublish` / `.cleanRemoteSyncpoint`) — while
leaving git's own `branch.<name>.remote`/`.merge` tracking keys untouched. It deliberately
**does not** delete `REMOTE_EXCLUDE.md`, any branches, or commits already published — those are
the user's data. Report what was removed and remind the user that `REMOTE_EXCLUDE.md` and their
branches are still there to delete by hand if they want a full teardown.
