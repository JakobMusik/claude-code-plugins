#!/bin/sh
# clean-remote uninstall — remove the plumbing, keep your data.
# Removes the pre-push hook, the worktree.baseRef override, the [clean-remote] git config,
# and the per-branch clean-remote keys (branch.<name>.cleanRemotePublish / .cleanRemoteSyncpoint).
# Leaves REMOTE_EXCLUDE.md, your branches, and any published commits alone.
set -u
. "$(dirname "$0")/lib.sh"
cr_in_repo

hookdir="$(git rev-parse --git-path hooks)"
removed_hook=no
if [ -f "$hookdir/pre-push" ] && grep -q "clean-remote" "$hookdir/pre-push" 2>/dev/null; then
  rm -f "$hookdir/pre-push"
  removed_hook=yes
fi

# Remove ONLY worktree.baseRef from settings.local.json (preserve everything else).
python3 - <<'PY' 2>/dev/null || true
import json, os
p = ".claude/settings.local.json"
if os.path.exists(p):
    try:
        with open(p) as f:
            cfg = json.load(f)
    except Exception:
        cfg = None
    if isinstance(cfg, dict) and isinstance(cfg.get("worktree"), dict):
        cfg["worktree"].pop("baseRef", None)
        if not cfg["worktree"]:
            cfg.pop("worktree")
        with open(p, "w") as f:
            json.dump(cfg, f, indent=2)
            f.write("\n")
PY

# Repo-wide config (remote, publishBranchTemplate, plus any legacy source/publishBranch/syncpoint).
git config --remove-section clean-remote 2>/dev/null || true

# Per-branch keys — unset ONLY our two subkeys so git's own branch.<name>.remote/merge survive.
removed_branch=no
for b in $(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null); do
  if [ -n "$(git config "branch.$b.cleanRemotePublish" 2>/dev/null || true)" ]; then
    git config --unset "branch.$b.cleanRemotePublish" 2>/dev/null || true
    removed_branch=yes
  fi
  if [ -n "$(git config "branch.$b.cleanRemoteSyncpoint" 2>/dev/null || true)" ]; then
    git config --unset "branch.$b.cleanRemoteSyncpoint" 2>/dev/null || true
    removed_branch=yes
  fi
done

printf 'clean-remote: uninstalled.\n'
printf '  pre-push hook        : %s\n' "$([ "$removed_hook" = yes ] && echo removed || echo 'not found (nothing to remove)')"
printf '  worktree.baseRef     : removed from .claude/settings.local.json\n'
printf '  [clean-remote] config: cleared\n'
printf '  per-branch keys      : %s\n' "$([ "$removed_branch" = yes ] && echo 'cleared (cleanRemotePublish / cleanRemoteSyncpoint)' || echo 'none found')"
printf '  LEFT IN PLACE        : REMOTE_EXCLUDE.md, your branches, and any published commits.\n'
