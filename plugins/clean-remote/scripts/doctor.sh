#!/bin/sh
# clean-remote doctor — report whether the workflow is correctly set up and safe to publish.
#
# Per-branch model: shared plumbing (hook, baseRef) is reported once; then each dev branch is
# reported against ITS OWN public branch. By default that's the current branch; pass --all to
# scan every managed dev branch (one with a publish override, a committed REMOTE_EXCLUDE.md,
# or an existing remote counterpart).
#
# Usage: doctor.sh [--all]
set -u
. "$(dirname "$0")/lib.sh"
cr_in_repo

remote="$(cr_remote)"; template="$(cr_publish_template)"
OK="[ ok ]"; BAD="[FAIL]"; WARN="[warn]"

all=no
case "${1:-}" in --all|-a) all=yes ;; esac

printf 'clean-remote: doctor\n'
printf '  config : remote=%s  publishBranchTemplate=%s\n' "$remote" "$template"

# --- shared plumbing -------------------------------------------------------------------
# pre-push hook
hookdir="$(git rev-parse --git-path hooks)"
if [ -x "$hookdir/pre-push" ] && grep -q "clean-remote" "$hookdir/pre-push" 2>/dev/null; then
  printf '  %s pre-push guard installed\n' "$OK"
else
  printf '  %s pre-push guard missing — run the setup skill\n' "$BAD"
fi

# settings.local.json
baseref="$(python3 -c 'import json,sys
try: print(json.load(open(".claude/settings.local.json")).get("worktree",{}).get("baseRef",""))
except Exception: print("")' 2>/dev/null)"
if [ "$baseref" = head ]; then
  printf '  %s worktree.baseRef=head\n' "$OK"
else
  printf '  %s worktree.baseRef not "head" (got: %s)\n' "$WARN" "${baseref:-unset}"
fi

# One fetch refreshes every remote-tracking ref the per-branch checks below read.
git fetch "$remote" >/dev/null 2>&1 || true

# --- per-branch report -----------------------------------------------------------------
report_branch() {  # $1 = local dev branch
  src="$1"
  pub="$(cr_publish_branch_for "$src")"
  base="refs/remotes/$remote/$pub"
  printf '\n  branch "%s"  ->  %s/%s\n' "$src" "$remote" "$pub"

  # REMOTE_EXCLUDE present + self-listed (read from THIS branch's committed copy)
  excl="$(cr_exclude_paths "refs/heads/$src")"
  if [ -n "$excl" ]; then
    if printf '%s\n' "$excl" | grep -qx "REMOTE_EXCLUDE.md"; then
      printf '    %s REMOTE_EXCLUDE.md lists itself\n' "$OK"
    else
      printf '    %s REMOTE_EXCLUDE.md does not list itself (it would leak to the remote)\n' "$WARN"
    fi
    printf '    private paths : %s\n' "$(printf '%s' "$excl" | tr '\n' ' ')"

    # Overlap check — a path in BOTH REMOTE_EXCLUDE.md and .gitignore is contradictory:
    # gitignored paths are never committed, so they carry no local history for `publish`
    # to strip. Each path belongs in exactly ONE list.
    overlap="$(printf '%s\n' "$excl" | while IFS= read -r p; do
      [ -n "$p" ] || continue
      git check-ignore --no-index -q -- "${p%/}" 2>/dev/null && printf '%s\n' "$p"
    done)"
    if [ -z "$overlap" ]; then
      printf '    %s no REMOTE_EXCLUDE path is also gitignored\n' "$OK"
    else
      printf '    %s paths in BOTH REMOTE_EXCLUDE.md and .gitignore (contradictory — gitignored\n' "$WARN"
      printf '           paths are never committed, so publish has no local history to strip):\n'
      printf '%s\n' "$overlap" | sed 's/^/          /'
      printf '           fix: keep each path in ONE list — remove from .gitignore to track it\n'
      printf '           locally, or drop it from REMOTE_EXCLUDE.md if it is just scratch.\n'
    fi
  else
    printf '    %s no REMOTE_EXCLUDE.md on "%s" — nothing is marked private\n' "$WARN" "$src"
  fi

  # publishability + leak check against the remote tip
  if git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
    # Last-published source point: publish forward-ports only the work since this commit.
    lp="$(cr_last_published "$base")"
    if [ -n "$lp" ] && git rev-parse --verify --quiet "$lp^{commit}" >/dev/null 2>&1; then
      printf '    %s next publish is incremental — forward-ports work since source %s\n' \
        "$OK" "$(git rev-parse --short "$lp")"
    elif [ -n "$lp" ]; then
      printf '    %s recorded source %s is gone (private history rewritten?) — next publish resyncs as a snapshot\n' \
        "$WARN" "$lp"
    else
      printf '    %s no prior publish recorded on %s/%s — next publish resyncs "%s" minus excludes as a snapshot\n' \
        "$WARN" "$remote" "$pub" "$src"
      if ! git merge-base "$base" "refs/heads/$src" >/dev/null 2>&1; then
        printf '    %s "%s" has NO common history with %s/%s — that snapshot would replace the remote tree wholesale; check the remote\n' \
          "$WARN" "$src" "$remote" "$pub"
      fi
    fi
    if [ -n "$excl" ]; then
      leaked="$(git ls-tree -r --name-only "$base" -- $excl 2>/dev/null)"
      if [ -z "$leaked" ]; then
        printf '    %s no private paths present on %s/%s\n' "$OK" "$remote" "$pub"
      else
        printf '    %s private paths ALREADY on %s/%s:\n' "$BAD" "$remote" "$pub"
        printf '%s\n' "$leaked" | sed 's/^/          /'
      fi
    fi

    # External public work (e.g. a merged contributor PR) not yet in the private branch.
    # (grep -c prints "0" and exits 1 on no matches, so capture directly — no `|| echo 0`,
    # which would append a second "0" and make the count non-numeric.)
    ext="$(cr_external_commits "$base" "refs/heads/$src" 2>/dev/null | grep -c .)"
    if [ "${ext:-0}" -gt 0 ]; then
      printf '    %s %s external commit(s) on %s/%s not yet in "%s" — run the sync skill to integrate\n' \
        "$WARN" "$ext" "$remote" "$pub" "$src"
    else
      printf '    %s "%s" has every public commit (nothing to sync)\n' "$OK" "$src"
    fi
  else
    printf '    %s %s/%s does not exist yet — the first publish of "%s" will CREATE it (clean snapshot)\n' \
      "$WARN" "$remote" "$pub" "$src"
  fi
}

# A dev branch is "managed" if it has a publish override, a committed REMOTE_EXCLUDE.md, or
# an existing remote counterpart. (clean-remote/* helper branches are never managed.)
is_managed() {  # $1 = local branch
  case "$1" in clean-remote/*) return 1 ;; esac
  [ -n "$(git config "branch.$1.cleanRemotePublish" 2>/dev/null)" ] && return 0
  git cat-file -e "refs/heads/$1:REMOTE_EXCLUDE.md" 2>/dev/null && return 0
  git rev-parse --verify --quiet "refs/remotes/$remote/$(cr_publish_branch_for "$1")^{commit}" >/dev/null 2>&1 && return 0
  return 1
}

if [ "$all" = yes ]; then
  found=0
  for b in $(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null); do
    if is_managed "$b"; then
      report_branch "$b"
      found=1
    fi
  done
  [ "$found" = 1 ] || printf '\n  %s no managed dev branches found — run setup on a branch and commit REMOTE_EXCLUDE.md\n' "$WARN"
else
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ -z "$cur" ] || [ "$cur" = HEAD ]; then
    printf '\n  %s detached HEAD — check out a dev branch, or run "doctor --all"\n' "$WARN"
  else
    report_branch "$cur"
    printf '\n  (reporting the current branch only — run "doctor --all" to scan every managed dev branch)\n'
  fi
fi
