#!/bin/sh
# clean-remote target — show or change which PUBLIC branch a local dev branch publishes to.
#
# The mapping is: the per-branch override branch.<name>.cleanRemotePublish if set, else the
# repo template clean-remote.publishBranchTemplate applied to the branch name ('%s' = same
# name). This command is a safe, discoverable front-end over that git config — it has no
# plumbing of its own. It NEVER pushes and NEVER touches your working tree; a change just
# takes effect on the next `publish`.
#
# Usage:
#   target.sh                          list every local branch -> its public branch
#   target.sh [--branch <b>] <name>    set branch <b> (default: current) to publish to <name>
#   target.sh [--branch <b>] --unset   drop the override -> fall back to the template
set -u
. "$(dirname "$0")/lib.sh"
cr_in_repo

usage() {
  sed -n '11,14p' "$0" | sed 's/^# \{0,1\}//'
}

remote="$(cr_remote)"

branch=""
newname=""
unset_it=no
have_action=no
while [ $# -gt 0 ]; do
  case "$1" in
    -b|--branch) shift; branch="${1:-}" ;;
    --branch=*)  branch="${1#--branch=}" ;;
    --unset)     unset_it=yes; have_action=yes ;;
    -l|--list)   : ;;                      # explicit list (the default with no action)
    -h|--help)   usage; exit 0 ;;
    -*)          cr_die "unknown option: $1 (try --help)" ;;
    *)           newname="$1"; have_action=yes ;;
  esac
  shift
done

# --- no action: list every local branch and the public branch it resolves to ------------
if [ "$have_action" = no ]; then
  printf 'clean-remote: publish-branch map  (remote: %s, template: %s)\n' \
    "$remote" "$(cr_publish_template)"
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  for b in $(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null); do
    pub="$(cr_publish_branch_for "$b")"
    if [ -n "$(git config "branch.$b.cleanRemotePublish" 2>/dev/null)" ]; then
      tag=override
    else
      tag=template
    fi
    mark=' '; [ "$b" = "$cur" ] && mark='*'
    printf '  %s %-22s -> %s/%-22s [%s]\n' "$mark" "$b" "$remote" "$pub" "$tag"
  done
  printf 'Change: target.sh [--branch <b>] <public-name>   |   --unset to revert to the template\n'
  exit 0
fi

# --- an action (set or unset): resolve the dev branch -----------------------------------
src="$(cr_target_branch "$branch")"
git rev-parse --verify --quiet "refs/heads/$src" >/dev/null 2>&1 \
  || cr_die "branch '$src' not found — check it out, or pass --branch <name>"
oldpub="$(cr_publish_branch_for "$src")"

if [ "$unset_it" = yes ]; then
  git config --unset "branch.$src.cleanRemotePublish" 2>/dev/null || true
  printf 'clean-remote: "%s" override removed — now uses the template: %s/%s\n' \
    "$src" "$remote" "$(cr_publish_branch_for "$src")"
  exit 0
fi

[ -n "$newname" ] || cr_die "no public-branch name given (try --help)"
case "$newname" in
  *' '*) cr_die "a branch name cannot contain spaces" ;;
  /*|*/) cr_die "invalid public branch name: '$newname'" ;;
esac

if [ "$newname" = "$oldpub" ]; then
  printf 'clean-remote: "%s" already publishes to %s/%s — no change.\n' "$src" "$remote" "$newname"
  exit 0
fi

git config "branch.$src.cleanRemotePublish" "$newname"
printf 'clean-remote: "%s"  ->  %s/%s   (was %s/%s)\n' "$src" "$remote" "$newname" "$remote" "$oldpub"

# --- caveats raw `git config` won't tell you (remote-tracking refs may be stale) ---------
if git rev-parse --verify --quiet "refs/remotes/$remote/$oldpub^{commit}" >/dev/null 2>&1; then
  printf '  note: %s/%s already exists and is no longer updated by "%s" — its history stays put.\n' \
    "$remote" "$oldpub" "$src"
fi
if git rev-parse --verify --quiet "refs/remotes/$remote/$newname^{commit}" >/dev/null 2>&1; then
  printf '  note: %s/%s already exists — the next publish forward-ports onto it (needs shared history; run doctor).\n' \
    "$remote" "$newname"
else
  printf '  note: %s/%s does not exist yet — the first publish will CREATE it as a clean snapshot.\n' \
    "$remote" "$newname"
fi
printf 'Takes effect on the next publish. Nothing was pushed.\n'
