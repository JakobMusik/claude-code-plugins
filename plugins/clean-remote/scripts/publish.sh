#!/bin/sh
# clean-remote publish — build ONE clean commit for THIS dev branch's public remote branch,
# carrying ONLY the new work since the last publish, with REMOTE_EXCLUDE paths stripped,
# ready to push.
#
# Per-branch model: the branch you publish is the current branch (or --branch <name>), and
# it has its OWN public counterpart — branch.<name>.cleanRemotePublish, else the template
# clean-remote.publishBranchTemplate applied to the branch name ('%s' = same name). All the
# incremental tracking below is keyed off THAT public branch, so different dev branches
# publish to different remote branches without interfering. The first publish to a public
# branch that doesn't exist yet CREATES it (a clean orphan snapshot of source minus excludes).
#
# Why incremental, not `merge --squash`:
#   The published commit is deliberately NOT a descendant of the private branch (recording
#   it as a parent would leak private history and files). So the private and public branches
#   permanently fork at their first shared commit. A plain `git merge`/`merge --squash`
#   therefore re-merges against that frozen fork point on every publish and conflicts the
#   moment an already-published file changes again — its public version looks like a rival
#   concurrent edit. Instead we forward-port only the delta since the LAST published source
#   commit. We recorded that commit as a `clean-remote-source:` trailer on the public commit,
#   so the delta's non-excluded paths already match the current public tip and apply straight
#   onto it: the base advances correctly, and commits made directly on the public branch
#   (e.g. a merged community PR) survive untouched.
#
# It NEVER pushes and NEVER touches your working tree: it works in an ephemeral worktree,
# leaves a branch holding the clean commit, and prints the exact review / push / cleanup
# commands. You push when you're ready.
#
# Usage: publish.sh [--branch <dev-branch>] ["commit message"]
set -u
. "$(dirname "$0")/lib.sh"
cr_in_repo

# Parse [--branch <name>] and an optional commit message (in any order).
branch=""
msg=""
while [ $# -gt 0 ]; do
  case "$1" in
    -b|--branch) shift; branch="${1:-}" ;;
    -b=*) branch="${1#-b=}" ;;
    --branch=*) branch="${1#--branch=}" ;;
    --) shift; [ $# -gt 0 ] && msg="$1" ;;
    *) msg="$1" ;;
  esac
  shift
done

remote="$(cr_remote)"
src="$(cr_target_branch "$branch")"
pub="$(cr_publish_branch_for "$src")"

git rev-parse --verify --quiet "refs/heads/$src" >/dev/null 2>&1 \
  || cr_die "branch '$src' not found — check it out (or pass --branch) and run setup first"
srcsha="$(git rev-parse "refs/heads/$src")"

# Refresh the remote tip we publish onto (may not exist yet — that's the fresh-publish case).
git fetch "$remote" "$pub" >/dev/null 2>&1 || git fetch "$remote" >/dev/null 2>&1 || true
base="refs/remotes/$remote/$pub"
base_exists=0
git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 && base_exists=1

excl="$(cr_exclude_paths "$src")"

patch=""
tmp=""
# Sanitise '/' in the branch name so the helper ref is a single path segment.
safe_src="$(printf '%s' "$src" | tr '/' '-')"
br="clean-remote/publish-$safe_src-$$"
made_branch=0   # set once we own the worktree+branch, so cleanup never nukes a pre-existing branch
keep_branch=0   # set on success: keep the publish branch (it holds the clean commit)

# Cleanup runs on ANY exit — normal, cr_die, or an interrupt (Ctrl-C / SIGTERM / SIGHUP) —
# so a killed or failed run never leaves a dangling worktree, branch, or temp file behind.
cleanup() {
  [ -n "$patch" ] && rm -f "$patch" >/dev/null 2>&1
  if [ -n "$tmp" ]; then
    git worktree remove --force "$tmp" >/dev/null 2>&1 || true
    rm -rf "$tmp" >/dev/null 2>&1 || true        # covers the case where the worktree was never added
  fi
  git worktree prune >/dev/null 2>&1 || true     # drop any dangling worktree admin entry
  [ "$made_branch" = 1 ] && [ "$keep_branch" = 0 ] && git branch -D "$br" >/dev/null 2>&1
  true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Strip the REMOTE_EXCLUDE paths from the worktree's index (and tree). Used by both paths so
# the published commit is clean even if the source / public tip carries a private path.
strip_excludes() {  # $1 = worktree dir
  [ -n "$excl" ] || return 0
  printf '%s\n' "$excl" | while IFS= read -r p; do
    [ -n "$p" ] && git -C "$1" rm -rf -q --ignore-unmatch -- "$p" >/dev/null 2>&1
    true
  done
}

if [ "$base_exists" = 1 ]; then
  # ---- incremental publish: forward-port the delta onto an existing public branch --------
  #
  # Choose the point we diff the source FROM. It must be a private commit whose non-excluded
  # tree matches the current public tip, so the delta `from..src` is a clean forward patch.
  # Two candidates can play that role; we take whichever is FURTHER along the source branch:
  #   - the trailer point: the source commit recorded by the last publish (read off THIS dev
  #     branch's public tip — self-healing across unpushed builds, fresh clones, externals).
  #   - the syncpoint: the commit `sync` produced when it cherry-picked external public work
  #     back into this branch (branch.<src>.cleanRemoteSyncpoint). After a sync it's newer
  #     than the trailer point, and skipping to it stops an edit to a synced file from
  #     3-way-merging against a stale base (a spurious "public diverged" conflict).
  # Each candidate counts only if it's an ANCESTOR of the current source — that quietly
  # discards a stale syncpoint or a trailer point left by a private-history rewrite.
  #
  # Fallback (neither candidate is valid): diff from the public tip itself, resyncing
  # "<source> minus excludes" onto it in one clean step. We must NOT fall back to the fork
  # point / merge-base: the published commit is not in the source's ancestry, so diffing from
  # the frozen fork point resurrects the very conflict this design avoids.
  from=""
  lp="$(cr_last_published "$base")"
  if [ -n "$lp" ] && git rev-parse --verify --quiet "$lp^{commit}" >/dev/null 2>&1 \
     && git merge-base --is-ancestor "$lp" "$srcsha" 2>/dev/null; then
    from="$lp"
  fi
  sp="$(cr_syncpoint_for "$src")"
  if [ -n "$sp" ] && git rev-parse --verify --quiet "$sp^{commit}" >/dev/null 2>&1 \
     && git merge-base --is-ancestor "$sp" "$srcsha" 2>/dev/null; then
    if [ -z "$from" ] || git merge-base --is-ancestor "$from" "$sp" 2>/dev/null; then
      from="$sp"
    fi
  fi
  [ -n "$from" ] || from="$base"

  # Build the REMOTE_EXCLUDE pathspecs into the positional params, so the delta never
  # contains a private path in the first place.
  set --
  if [ -n "$excl" ]; then
    oldifs="$IFS"
    IFS='
'
    for p in $excl; do
      [ -n "$p" ] && set -- "$@" ":(exclude)$p"
    done
    IFS="$oldifs"
  fi

  # The exclude-filtered delta from..src. --binary so binary changes carry their blobs;
  # the index lines let `git apply --3way` find the pre/post images by OID.
  patch="$(mktemp)"
  git diff --binary "$from..$srcsha" -- . "$@" > "$patch" 2>/dev/null
  if [ ! -s "$patch" ]; then
    printf 'clean-remote: nothing to publish — "%s" is already in sync with %s/%s.\n' "$src" "$remote" "$pub"
    exit 0
  fi

  tmp="$(mktemp -d)"
  git worktree add -q -b "$br" "$tmp" "$base" 2>/dev/null \
    || cr_die "could not create the publish worktree (does branch '$br' already exist?)"
  made_branch=1

  # Forward-port the delta onto the public tip. --3way uses the recorded blob versions as the
  # merge base, so a hunk an external public commit already applied is reconciled rather than
  # blindly rejected; a genuine overlap (the public branch changed the same lines) leaves
  # conflicts in the index, which we surface instead of forcing.
  if ! git -C "$tmp" apply --index --3way --whitespace=nowarn "$patch" >/dev/null 2>&1; then
    if git -C "$tmp" ls-files -u | grep -q .; then
      cr_die "conflict applying new work onto $remote/$pub — the public branch changed the same lines; reconcile manually"
    fi
    cr_die "could not apply the update onto $remote/$pub — reconcile manually"
  fi
  strip_excludes "$tmp"
else
  # ---- fresh publish: create the public branch as a clean orphan snapshot ----------------
  # The public branch doesn't exist yet (first publish for this dev branch). Materialise
  # "source minus excludes" as a single root commit; the push below creates the branch.
  tmp="$(mktemp -d)"
  git worktree add -q --detach "$tmp" "$srcsha" 2>/dev/null \
    || cr_die "could not create the publish worktree"
  # Orphan branch: index/worktree = source tree, but no parent → no private history leaks.
  git -C "$tmp" checkout -q --orphan "$br" 2>/dev/null \
    || cr_die "could not start a fresh public branch"
  made_branch=1
  strip_excludes "$tmp"
fi

# Net-zero (e.g. the public branch already contained this work, or source is only private
# files) → nothing public-visible to publish.
if git -C "$tmp" diff --cached --quiet 2>/dev/null; then
  printf 'clean-remote: nothing to publish — "%s" is already in sync with %s/%s.\n' "$src" "$remote" "$pub"
  exit 0
fi

[ -n "$msg" ] || msg="Publish update from $src"
# Record the exact source commit as a trailer so the NEXT publish knows where to diff from.
if ! printf '%s\n\n%s: %s\n' "$msg" "$(cr_trailer_key)" "$srcsha" \
     | git -C "$tmp" commit -q -F - >/dev/null 2>&1; then
  printf 'clean-remote: nothing to publish — "%s" is already in sync with %s/%s.\n' "$src" "$remote" "$pub"
  exit 0
fi

newsha="$(git -C "$tmp" rev-parse --short HEAD)"
keep_branch=1   # success → the EXIT trap removes only the worktree; branch '$br' survives, holding the clean commit

if [ "$base_exists" = 1 ]; then
  printf 'clean-remote: built clean commit %s on branch "%s" (%s -> %s/%s).\n' "$newsha" "$br" "$src" "$remote" "$pub"
  printf '  review : git show %s   |   git diff %s/%s..%s\n' "$br" "$remote" "$pub" "$br"
else
  printf 'clean-remote: built clean commit %s on branch "%s" (%s -> NEW %s/%s).\n' "$newsha" "$br" "$src" "$remote" "$pub"
  printf '  review : git show %s\n' "$br"
fi

# Reference warn-gate (read-only, advisory — never edits, never blocks). We stripped the private
# paths from this commit's tree, but references TO them left inside the files we DID publish are
# now dead links on the public remote. We only DETECT here and point at the fix: the scrub-refs
# skill resolves each (rewrite/strip/leave) and amends into THIS commit, keeping it one commit.
refhits="$(cr_scan_refs "refs/heads/$src" "$br" 2>/dev/null || true)"
if [ -n "$refhits" ]; then
  refn="$(printf '%s\n' "$refhits" | grep -c . || true)"
  printf '  refs   : %s reference(s) to stripped private paths are now DEAD in this commit.\n' "$refn"
  printf '           Resolve before pushing with the scrub-refs skill — it rewrites/strips each\n'
  printf '           and amends into THIS commit (still one commit). Review the hits (read-only):\n'
  printf '             sh "%s/scrub-refs.sh" --branch %s --ref %s\n' "$(dirname "$0")" "$src" "$br"
fi

printf '  push   : git push %s %s:%s\n' "$remote" "$br" "$pub"
printf '  tidy   : git branch -D %s\n' "$br"
