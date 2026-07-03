#!/bin/sh
# clean-remote scrub-refs — find references, in the files that WILL be published, to paths
# that `publish` strips (the REMOTE_EXCLUDE list). Those targets vanish on the public remote,
# so every such reference becomes a DEAD link / mention publicly. This reports them so they can
# be rewritten (point at a public target) or stripped (drop the dead reference) before pushing.
#
# It is READ-ONLY — like `doctor`, it changes nothing. It locates the references; the human (with
# Claude, per the skill) decides rewrite-vs-strip per hit, because that needs judgement a script
# can't supply (a markdown link, a code import, and a prose mention each demand a different fix).
#
# Per-branch model: the private-path list is read from a DEV branch's committed REMOTE_EXCLUDE.md
# (default: the current branch). The tree SEARCHED defaults to that same dev branch — a preview of
# "if I publish now, what would be dead?" — but `--ref` can point it at the already-built publish
# branch, a remote public branch (e.g. origin/main), or any commit. Searching a publish branch is
# the post-publish flow: its REMOTE_EXCLUDE paths are already stripped, so the exclude list MUST
# come from the dev branch (--branch), which is why the two refs are separate.
#
# Usage: scrub-refs.sh [--branch <dev-branch>] [--ref <ref-to-scan>] [--since <ref>]
#   --branch <dev>   dev branch whose REMOTE_EXCLUDE.md defines the private paths (default: HEAD)
#   --ref <ref>      tree to search (default: the dev branch's tip). A branch, tag, or commit.
#   --since <ref>    scope the scan to only the files changed between <ref> and the scanned tree
#                    — the delta a publish would carry. Pass the last-published source commit to
#                    re-examine just the new work, so repeat previews do less each time.
set -u
. "$(dirname "$0")/lib.sh"
cr_in_repo
# Search from the repo root so pathspecs and reported paths are repo-relative regardless of cwd.
root="$(git rev-parse --show-toplevel)" && cd "$root" || cr_die "could not cd to repo root"

# --- parse [--branch <dev>] [--ref <ref>] [--since <ref>] (a bare positional is --ref) ----
dev=""
scan=""
since=""
while [ $# -gt 0 ]; do
  case "$1" in
    -b|--branch) shift; dev="${1:-}" ;;
    -b=*) dev="${1#-b=}" ;;
    --branch=*) dev="${1#--branch=}" ;;
    -r|--ref) shift; scan="${1:-}" ;;
    -r=*) scan="${1#-r=}" ;;
    --ref=*) scan="${1#--ref=}" ;;
    -s|--since) shift; since="${1:-}" ;;
    -s=*) since="${1#-s=}" ;;
    --since=*) since="${1#--since=}" ;;
    -h|--help) printf 'usage: scrub-refs.sh [--branch <dev-branch>] [--ref <ref-to-scan>] [--since <ref>]\n'; exit 0 ;;
    --) shift; [ $# -gt 0 ] && scan="$1" ;;
    *) scan="$1" ;;
  esac
  shift
done

dev="$(cr_target_branch "$dev")"
case "$dev" in
  clean-remote/*)
    cr_die "on helper branch '$dev' — pass --branch <your dev branch> (its REMOTE_EXCLUDE.md defines the private paths)" ;;
esac
git rev-parse --verify --quiet "refs/heads/$dev" >/dev/null 2>&1 \
  || cr_die "branch '$dev' not found — check it out (or pass --branch) and run setup first"

# Default the search target to the dev branch tip (the pre-publish preview).
[ -n "$scan" ] || scan="refs/heads/$dev"
git rev-parse --verify --quiet "$scan^{tree}" >/dev/null 2>&1 \
  || cr_die "cannot resolve --ref '$scan' to a tree (fetch it first, or check the name)"

excl="$(cr_exclude_paths "refs/heads/$dev")"
if [ -z "$excl" ]; then
  printf 'clean-remote: scrub-refs — no REMOTE_EXCLUDE paths declared on "%s"; nothing is private, so nothing to scan.\n' "$dev"
  exit 0
fi

# --since scopes the search set to only the files that changed between <since> and the scanned
# tree — the delta a publish would carry — so repeat previews re-examine just the new work.
# Without it we scan the whole tree. The changed files become include pathspecs for cr_scan_refs.
scan_desc="whole tree"
set --
if [ -n "$since" ]; then
  git rev-parse --verify --quiet "$since^{tree}" >/dev/null 2>&1 \
    || cr_die "cannot resolve --since '$since' to a tree (fetch it first, or check the name)"
  changed="$(git diff --name-only "$since" "$scan" 2>/dev/null || true)"
  if [ -z "$changed" ]; then
    printf 'clean-remote: scrub-refs — no files changed between %s and %s; nothing new to scan.\n' "$since" "$scan"
    exit 0
  fi
  oldifs="$IFS"; IFS='
'
  for f in $changed; do [ -n "$f" ] && set -- "$@" "$f"; done
  IFS="$oldifs"
  scan_desc="$(printf '%s\n' "$changed" | grep -c . || true) file(s) changed since $since"
fi

# Locate the references (read-only). "$@" is the changed-file include set, or empty (whole tree).
clean="$(cr_scan_refs "refs/heads/$dev" "$scan" "$@")"

privlist="$(printf '%s' "$excl" | tr '\n' ' ')"
printf 'clean-remote: scrub-refs\n'
printf '  scanning : %s  (%s)\n' "$scan" "$scan_desc"
printf '  excludes : %s  (REMOTE_EXCLUDE.md on "%s")\n' "$privlist" "$dev"

if [ -z "$clean" ]; then
  printf '  [ ok ] no references to private paths in the files that would be published.\n'
  exit 0
fi

nmatch="$(printf '%s\n' "$clean" | grep -c . || true)"
nfiles="$(printf '%s\n' "$clean" | cut -d: -f1 | sort -u | grep -c . || true)"
printf '\n'
printf '%s\n' "$clean" | sed 's/^/  /'
printf '\n'
printf '  %s reference(s) across %s file(s) point at private paths.\n' "$nmatch" "$nfiles"
printf '  Those targets are stripped from %s, so each reference is DEAD on the public remote.\n' "$scan"
printf '  Fix each: rewrite it to a public target, or strip the reference. (See the skill.)\n'
printf '  Some hits may be intentional (e.g. a .gitignore entry, or code that names the path on\n'
printf '  purpose) — review before changing.\n'
# Read-only: a clean exit even when references are found; the skill drives the fixes.
