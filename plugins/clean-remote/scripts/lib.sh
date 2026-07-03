# clean-remote shared helpers (POSIX sh). Source with: . "$(dirname "$0")/lib.sh"
# Config lives in git config (per-repo, local, never pushed). Two scopes:
#   - repo-wide keys under the [clean-remote] section (remote, publishBranchTemplate)
#   - per-branch keys under branch.<name>.* — git's own idiom, alongside
#     branch.<name>.remote / branch.<name>.merge:
#       branch.<name>.cleanRemotePublish    public branch this dev branch publishes to
#       branch.<name>.cleanRemoteSyncpoint  last commit `sync` integrated for this branch
#
# Per-branch model: EACH local dev branch maps to its OWN public squashed branch. There is
# no single global "source" anymore — commands act on the current branch (or an explicit one).

cr_die() { printf 'clean-remote: %s\n' "$*" >&2; exit 1; }

cr_in_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || cr_die "not inside a git repository"
}

cr_remote() { git config clean-remote.remote 2>/dev/null || echo origin; }

# The local dev branch a command operates on: explicit $1 if non-empty, else current HEAD.
# Errors on a detached HEAD — you must name (or be on) the branch you want to publish.
cr_target_branch() {  # $1 = optional explicit branch name
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
    return
  fi
  b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -n "$b" ] && [ "$b" != "HEAD" ] \
    || cr_die "detached HEAD — check out the dev branch you want, or pass --branch <name>"
  printf '%s\n' "$b"
}

# Template mapping a local branch name to its public branch name. '%s' = same name (default).
cr_publish_template() {
  t=$(git config clean-remote.publishBranchTemplate 2>/dev/null) \
    && [ -n "$t" ] && { printf '%s\n' "$t"; return; }
  printf '%s\n' '%s'
}

# The public branch for local branch $1: per-branch override wins, else the template applied.
# The branch name is passed as a printf ARGUMENT (not the format), so '%' in a branch name is
# safe; the template is the format and is expected to contain exactly one '%s'.
cr_publish_branch_for() {  # $1 = local branch
  o=$(git config "branch.$1.cleanRemotePublish" 2>/dev/null) \
    && [ -n "$o" ] && { printf '%s\n' "$o"; return; }
  # shellcheck disable=SC2059
  printf "$(cr_publish_template)\n" "$1"
}

# Per-branch syncpoint (replaces the old global clean-remote.syncpoint). `sync` writes it;
# `publish` reads it (honoured only while it's an ancestor of the branch).
cr_syncpoint_for() {  # $1 = local branch
  git config "branch.$1.cleanRemoteSyncpoint" 2>/dev/null || true
}

# Reverse map: given a PUBLIC branch name, print the local dev branch that publishes to it
# (the first local head whose cr_publish_branch_for matches). Used by the pre-push guard to
# pick the right private-path list for an outgoing ref. Empty if none maps.
# (Git ref names cannot contain spaces, so word-splitting the head list is safe.)
cr_devbranch_for_public() {  # $1 = public branch name
  for b in $(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null); do
    [ "$(cr_publish_branch_for "$b")" = "$1" ] && { printf '%s\n' "$b"; return; }
  done
}

cr_exclude_file() { echo "REMOTE_EXCLUDE.md"; }

# Print the excluded pathspecs (one per line) read from <ref>'s REMOTE_EXCLUDE.md.
# '#' comments and blank lines are ignored. <ref> is a branch or commit.
cr_exclude_paths() {  # $1 = ref
  git show "$1:$(cr_exclude_file)" 2>/dev/null \
    | sed 's/#.*//' \
    | sed 's/[[:space:]]*$//' \
    | grep -v '^[[:space:]]*$' || true
}

# List references, in <scan-ref>'s tree, to the REMOTE_EXCLUDE paths declared on <dev-ref>.
# `publish` strips those paths, so each such reference is a DEAD link/import/mention on the
# public remote. Optional trailing include-pathspecs restrict the search set (default: the
# whole tree) — pass only the files a publish would change to re-examine just the new work.
# The private paths themselves are always excluded from the search set: we want references
# FROM the published files, not matches inside the private files. Prints one
# "path:line:content" per hit with the <scan-ref> prefix stripped; empty output = no hits.
# READ-ONLY. Shared by scrub-refs (full report) and publish (post-build warn-gate); its
# positional-param juggling is function-local, so it never disturbs the caller's "$@".
cr_scan_refs() {  # $1 = dev-ref (exclude list), $2 = scan-ref (tree), $3.. = include pathspecs
  _csr_dev="$1"; _csr_scan="$2"; shift 2
  _csr_excl="$(cr_exclude_paths "$_csr_dev")"
  [ -n "$_csr_excl" ] || return 0
  # Tokens from each private path: for ".planning/" search ".planning" (matches the bare dir
  # and any subpath) plus "./.planning" (explicit relative form). Fixed-string, deduped.
  _csr_toks="$(printf '%s\n' "$_csr_excl" | while IFS= read -r e; do
    e="${e#./}"; e="${e%/}"
    [ -n "$e" ] && printf '%s\n./%s\n' "$e" "$e"
  done | sort -u | grep -v '^$' || true)"
  [ -n "$_csr_toks" ] || return 0

  # Default the search set to the whole tree, then stash the includes (newline-delimited).
  [ "$#" -gt 0 ] || set -- .
  _csr_inc="$(printf '%s\n' "$@")"

  # Build: git grep -n -I -F  -e tok...  <scan>  --  <include...>  :(exclude)<priv>...
  set -- -n -I -F
  _csr_oldifs="$IFS"; IFS='
'
  for _csr_t in $_csr_toks; do [ -n "$_csr_t" ] && set -- "$@" -e "$_csr_t"; done
  set -- "$@" "$_csr_scan" --
  for _csr_i in $_csr_inc; do [ -n "$_csr_i" ] && set -- "$@" "$_csr_i"; done
  for _csr_p in $_csr_excl; do [ -n "$_csr_p" ] && set -- "$@" ":(exclude)$_csr_p"; done
  IFS="$_csr_oldifs"

  _csr_hits="$(git grep "$@" 2>/dev/null || true)"
  [ -n "$_csr_hits" ] || return 0
  # Strip git-grep's leading "<scan>:" tree prefix so each line reads "<path>:<line>:<content>".
  printf '%s\n' "$_csr_hits" | while IFS= read -r _csr_line; do
    [ -n "$_csr_line" ] && printf '%s\n' "${_csr_line#"$_csr_scan":}"
  done
}

# The commit-message trailer that records which private source commit a published
# commit was built from. `publish` writes it; the next publish reads it back to know
# where to diff from. (Mirrors the `(cherry picked from commit <sha>)` convention.)
cr_trailer_key() { echo "clean-remote-source"; }

# Print the source SHA recorded by the most recent publish reachable from <ref>, or
# nothing if none carries the trailer. Walking from the tip means an external commit
# made directly on the public branch (which has no trailer) is skipped over to the
# last real publish underneath it — so the incremental delta is computed correctly
# even when the public branch advanced on its own.
cr_last_published() {  # $1 = ref (e.g. the remote tip)
  git log "$1" --format="%(trailers:key=$(cr_trailer_key),valueonly)" 2>/dev/null \
    | awk 'NF{gsub(/[[:space:]]/,""); if($0!=""){print; exit}}'
}

# Print the EXTERNAL commits on <base> that aren't yet in <src> — i.e. work pushed
# directly to the public branch (e.g. a merged contributor PR) that the private branch
# hasn't integrated. Oldest first, so the list can be cherry-picked in order.
#
# Two filters make this exact and idempotent:
#   - patch-id (`git cherry`): a commit already present in <src> (e.g. one a previous
#     sync cherry-picked) is marked '-' and skipped — so re-running never re-integrates.
#   - trailer: our own publish commits carry `clean-remote-source`; their content came
#     FROM <src>, so they're not external work and are skipped.
cr_external_commits() {  # $1 = base ref, $2 = source ref
  git cherry "$2" "$1" 2>/dev/null | while read -r sign sha; do
    [ "$sign" = "+" ] || continue
    t="$(git show -s --format="%(trailers:key=$(cr_trailer_key),valueonly)" "$sha" 2>/dev/null \
         | tr -d '[:space:]')"
    [ -n "$t" ] && continue
    printf '%s\n' "$sha"
  done
}
