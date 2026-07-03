#!/bin/sh
# clean-remote sync — pull EXTERNAL public work (e.g. a merged contributor PR, made
# directly on the clean public branch) back into the matching private dev branch, so the
# private branch stays a superset of its public counterpart.
#
# Per-branch model: syncs the current branch (or --branch <name>) against ITS OWN public
# branch — branch.<name>.cleanRemotePublish, else the template applied. The recorded
# syncpoint is per-branch (branch.<name>.cleanRemoteSyncpoint), so syncing one dev branch
# never disturbs another's publish bookkeeping.
#
# It is the reverse of `publish` (private -> public). Like `publish`, it NEVER mutates your
# working tree or branches in place: it cherry-picks the external commits onto an ephemeral
# `clean-remote/sync-*` branch and prints the exact review / apply / cleanup commands. You
# fast-forward your source branch onto it when you're ready.
#
# How it cooperates with publish's tracking:
#   The external commits carry no `clean-remote-source` trailer, so publish's trailer-based
#   "last published" point would sit BEFORE them and a later edit to a synced file would
#   3-way-merge against a stale base (a spurious conflict). To prevent that, sync records the
#   resulting private commit in branch.<src>.cleanRemoteSyncpoint; publish diffs from there
#   once you apply the sync. The pointer is honoured only while it's an ancestor of the source
#   branch, so an un-applied or rewound sync is ignored automatically.
#
# Usage: sync.sh [--branch <dev-branch>]
set -u
. "$(dirname "$0")/lib.sh"
cr_in_repo

# Parse [--branch <name>].
branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    -b|--branch) shift; branch="${1:-}" ;;
    -b=*) branch="${1#-b=}" ;;
    --branch=*) branch="${1#--branch=}" ;;
    *) ;;  # ignore anything else
  esac
  shift
done

remote="$(cr_remote)"
src="$(cr_target_branch "$branch")"
pub="$(cr_publish_branch_for "$src")"

git rev-parse --verify --quiet "refs/heads/$src" >/dev/null 2>&1 \
  || cr_die "branch '$src' not found — check it out (or pass --branch) and run setup first"

# Refresh the public branch we integrate from.
git fetch "$remote" "$pub" >/dev/null 2>&1 || git fetch "$remote" >/dev/null 2>&1 || true
base="refs/remotes/$remote/$pub"
git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 \
  || cr_die "remote base '$remote/$pub' not found — nothing to sync from"

# External public commits not yet in the source branch (oldest first).
externals="$(cr_external_commits "$base" "refs/heads/$src")"
if [ -z "$externals" ]; then
  printf 'clean-remote: nothing to sync — "%s" already has every public commit on %s/%s.\n' "$src" "$remote" "$pub"
  exit 0
fi

count="$(printf '%s\n' "$externals" | grep -c .)"

tmp=""
safe_src="$(printf '%s' "$src" | tr '/' '-')"
br="clean-remote/sync-$safe_src-$$"
made_branch=0
keep_branch=0

# Cleanup on ANY exit so a killed/failed run leaves no dangling worktree or branch behind.
cleanup() {
  if [ -n "$tmp" ]; then
    git worktree remove --force "$tmp" >/dev/null 2>&1 || true
    rm -rf "$tmp" >/dev/null 2>&1 || true
  fi
  git worktree prune >/dev/null 2>&1 || true
  [ "$made_branch" = 1 ] && [ "$keep_branch" = 0 ] && git branch -D "$br" >/dev/null 2>&1
  true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

tmp="$(mktemp -d)"
git worktree add -q -b "$br" "$tmp" "refs/heads/$src" 2>/dev/null \
  || cr_die "could not create the sync worktree (does branch '$br' already exist?)"
made_branch=1

# Cherry-pick each external commit onto the source tip, in order. -x records the public
# provenance ("cherry picked from commit <sha>") in the message. The loop runs in THIS
# shell (a for-loop over the newline-split list, not a pipe), so a conflict is recoverable.
conflict_sha=""
oldifs="$IFS"
IFS='
'
for sha in $externals; do
  IFS="$oldifs"
  [ -n "$sha" ] || { IFS='
'; continue; }
  if ! git -C "$tmp" cherry-pick -x "$sha" >/dev/null 2>&1; then
    conflict_sha="$sha"
    git -C "$tmp" cherry-pick --abort >/dev/null 2>&1 || true
    break
  fi
  IFS='
'
done
IFS="$oldifs"

# A conflict means this public commit changes something your private branch also changed.
# Roll back the whole sync (keep_branch stays 0 → cleanup deletes the branch) and hand it
# to the user: automated resolution here would be guessing.
if [ -n "$conflict_sha" ]; then
  cr_die "cherry-pick of $(git rev-parse --short "$conflict_sha") ('$(git show -s --format='%s' "$conflict_sha" 2>/dev/null)') conflicts with '$src' — integrate it by hand (git cherry-pick -x $conflict_sha, resolve), then re-run sync for the rest"
fi

newtip="$(git -C "$tmp" rev-parse HEAD)"
# Record where the source branch will be once you apply this sync, so publish diffs from
# AFTER the integrated work (honoured only while it's an ancestor of the source — see header).
git config "branch.$src.cleanRemoteSyncpoint" "$newtip"
keep_branch=1

short="$(git -C "$tmp" rev-parse --short HEAD)"
printf 'clean-remote: integrated %s external commit(s) from %s/%s onto branch "%s" (tip %s).\n' \
  "$count" "$remote" "$pub" "$br" "$short"
printf '  review : git log --oneline %s..%s   |   git diff %s..%s\n' "$src" "$br" "$src" "$br"
printf '  apply  : git switch %s && git merge --ff-only %s\n' "$src" "$br"
printf '  tidy   : git branch -D %s\n' "$br"
printf 'After applying, the next publish treats this work as already public (no duplicate commit).\n'
