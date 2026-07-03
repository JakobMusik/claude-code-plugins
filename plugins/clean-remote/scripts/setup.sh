#!/bin/sh
# clean-remote setup — stamp this repo for the local-overlay / clean-remote workflow.
# Idempotent: safe to re-run. Records config, creates REMOTE_EXCLUDE.md (self-listed),
# installs the pre-push guard, and sets worktree.baseRef=head in project-local settings.
#
# Per-branch model: EACH local dev branch publishes to its OWN public squashed branch.
# The public name comes from clean-remote.publishBranchTemplate ('%s' = same name) or a
# per-branch override in branch.<name>.cleanRemotePublish. There is no single global source.
#
# Overridable via env:
#   CR_REMOTE   (default origin) — the remote you publish to / the guard protects
#   CR_TEMPLATE (default '%s')   — maps a local branch name to its public branch name
#   CR_PUBLISH  (optional)       — set the CURRENT branch's public-branch override explicitly
set -u
. "$(dirname "$0")/lib.sh"
cr_in_repo
root="$(git rev-parse --show-toplevel)"
cd "$root" || cr_die "could not cd to repo root"

# Precedence for the repo-wide keys: explicit env override > existing config > default.
# Consulting the existing value means a bare re-run PRESERVES a customised remote/template
# instead of resetting it — pass CR_REMOTE / CR_TEMPLATE only when you mean to change it.
remote="${CR_REMOTE:-$(git config clean-remote.remote 2>/dev/null || echo origin)}"
template="${CR_TEMPLATE:-$(git config clean-remote.publishBranchTemplate 2>/dev/null || echo '%s')}"

git config clean-remote.remote "$remote"
git config clean-remote.publishBranchTemplate "$template"

# --- migrate the old single-branch config, if present -----------------------------------
# Old scheme: clean-remote.source / clean-remote.publishBranch / clean-remote.syncpoint.
# New scheme: branch.<source>.cleanRemotePublish / branch.<source>.cleanRemoteSyncpoint.
# Only migrate when the new per-branch key is absent, so re-running is idempotent.
migrated=no
old_src="$(git config clean-remote.source 2>/dev/null || true)"
old_pub="$(git config clean-remote.publishBranch 2>/dev/null || true)"
if [ -n "$old_src" ] && [ -n "$old_pub" ]; then
  if [ -z "$(git config "branch.$old_src.cleanRemotePublish" 2>/dev/null || true)" ]; then
    git config "branch.$old_src.cleanRemotePublish" "$old_pub"
  fi
  old_sp="$(git config clean-remote.syncpoint 2>/dev/null || true)"
  if [ -n "$old_sp" ] \
     && [ -z "$(git config "branch.$old_src.cleanRemoteSyncpoint" 2>/dev/null || true)" ]; then
    git config "branch.$old_src.cleanRemoteSyncpoint" "$old_sp"
  fi
  git config --unset clean-remote.source 2>/dev/null || true
  git config --unset clean-remote.publishBranch 2>/dev/null || true
  git config --unset clean-remote.syncpoint 2>/dev/null || true
  migrated=yes
fi

# Current branch + the public branch it resolves to (for the summary and optional override).
cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ "$cur" != "HEAD" ] || cur=""
if [ -n "${CR_PUBLISH:-}" ]; then
  [ -n "$cur" ] || cr_die "CR_PUBLISH given but HEAD is detached — check out the dev branch first"
  git config "branch.$cur.cleanRemotePublish" "$CR_PUBLISH"
fi

# REMOTE_EXCLUDE.md — the single policy file (lists itself), created only if absent.
created_excl=no
if [ ! -f REMOTE_EXCLUDE.md ]; then
  cat > REMOTE_EXCLUDE.md <<'EOF'
# REMOTE_EXCLUDE — paths kept LOCAL, stripped from the public remote by the `publish` skill.
# One git pathspec per line (repo-relative). '#' comments and blank lines are ignored.
# This file lists ITSELF, so the policy is tracked locally (with history) but never published.
#
# Add the planning / agent-helper paths you want kept off the remote. Junk that needs no
# history belongs in .gitignore instead.
#
# This list is read from EACH branch's own committed copy, so a dev branch can declare its
# own private paths — they apply only to that branch's public counterpart.
#
# ONE path, ONE list: do NOT also put these paths in .gitignore. A gitignored path is never
# committed, so it has no local history for `publish` to strip — the two lists are mutually
# exclusive. (Tracked-locally-but-off-remote -> here; pure scratch/artifacts -> .gitignore.)
# `doctor` flags any path that ends up in both.
#
# Note: .claude/settings.local.json is intentionally NOT listed here — it's machine-local
# config (Claude Code gitignores it by default), so it belongs to the .gitignore world.
# baseRef=head lives there; re-run `setup` after a fresh clone to recreate it.
REMOTE_EXCLUDE.md
.planning/
EOF
  created_excl=yes
fi

# pre-push guard — installed into the shared hooks dir (covers all worktrees).
hookdir="$(git rev-parse --git-path hooks)"
mkdir -p "$hookdir"
cp "$(dirname "$0")/pre-push" "$hookdir/pre-push"
chmod +x "$hookdir/pre-push"

# .claude/settings.local.json — merge ONLY worktree.baseRef=head (preserve other keys).
python3 - "$root" <<'PY' || cr_die "could not update .claude/settings.local.json"
import json, os, sys
root = sys.argv[1]
d = os.path.join(root, ".claude")
p = os.path.join(d, "settings.local.json")
os.makedirs(d, exist_ok=True)
cfg = {}
if os.path.exists(p):
    try:
        with open(p) as f:
            cfg = json.load(f)
        if not isinstance(cfg, dict):
            cfg = {}
    except json.JSONDecodeError:
        sys.exit("settings.local.json is not valid JSON")
wt = cfg.get("worktree")
if not isinstance(wt, dict):
    wt = {}
wt["baseRef"] = "head"
cfg["worktree"] = wt
with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY

printf 'clean-remote: setup complete.\n'
printf '  public remote               : %s\n' "$remote"
printf '  publish branch template     : %s  (each dev branch -> its own public branch)\n' "$template"
if [ -n "$cur" ]; then
  printf '  current branch              : %s  ->  %s/%s\n' "$cur" "$remote" "$(cr_publish_branch_for "$cur")"
else
  printf '  current branch              : (detached HEAD — check out a dev branch to publish)\n'
fi
if [ "$migrated" = yes ]; then
  printf '  migrated old config         : clean-remote.{source,publishBranch,syncpoint} -> branch.%s.*\n' "$old_src"
fi
if [ "$created_excl" = yes ]; then
  printf '  REMOTE_EXCLUDE.md           : created — edit it to add your private paths\n'
else
  printf '  REMOTE_EXCLUDE.md           : kept existing\n'
fi
printf '  pre-push hook               : installed (%s/pre-push)\n' "$hookdir"
printf '  .claude/settings.local.json : worktree.baseRef=head\n'
printf 'Next: commit REMOTE_EXCLUDE.md on your dev branch, then run the publish skill.\n'
printf 'A branch can target a different public name: git config branch.<branch>.cleanRemotePublish <name>\n'
