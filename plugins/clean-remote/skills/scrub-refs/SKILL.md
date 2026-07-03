---
name: scrub-refs
description: Find and clean up dead references — links, imports, or mentions — that the to-be-published files make to REMOTE_EXCLUDE (local-only) paths, then rewrite or strip them so the public remote has no dangling pointers. `publish` removes the private files/folders themselves but leaves references to them in the files it DOES publish, so those go dead publicly. Use this when the user wants to "clean up references to excluded files", "fix dead links to private files", "find dangling references before publishing", "scrub mentions of .planning/ (or AGENTS.md / CLAUDE.md) from the public files", or to lint a repo set up with clean-remote for references to local-only paths.
version: 0.1.0
---

# clean-remote: scrub-refs

`publish` strips the `REMOTE_EXCLUDE.md` paths (the private files/folders) from the published
tree — but it leaves **references to them** untouched in the files it *does* publish. A published
`README.md` that links to `.planning/roadmap.md`, a source file that imports from an excluded
`agents/` dir, a doc that says "see `CLAUDE.md`" — each becomes a **dead** link/import/mention on
the public remote, where the target no longer exists. This skill finds those references and helps
rewrite or strip them.

The private branch is the source of truth and stays intact — there the references are *valid*
(the targets exist locally). So the default and recommended fix scrubs the **public artifact**,
not your source. The detector itself is **read-only**, like `doctor`.

## When to use
The user wants to remove or fix references to local-only paths from what gets published — before
pushing, or as a lint of the repo. Triggers: "clean up references to excluded files", "dead links
to private files", "scrub mentions of `.planning/` before publishing". The repo must already be set
up (`setup`) with a committed `REMOTE_EXCLUDE.md`.

## Find the references
Read-only. The private-path list is read from a dev branch's `REMOTE_EXCLUDE.md` (default: the
current branch); the tree searched defaults to that same dev branch — a preview of "if I publish
now, what would be dead?":

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/scrub-refs.sh"                 # preview the current dev branch
sh "${CLAUDE_PLUGIN_ROOT}/scripts/scrub-refs.sh" --branch <dev>  # a specific dev branch
sh "${CLAUDE_PLUGIN_ROOT}/scripts/scrub-refs.sh" --ref <ref>     # search another tree (see below)
sh "${CLAUDE_PLUGIN_ROOT}/scripts/scrub-refs.sh" --since <ref>   # only files changed since <ref>
```

It prints each hit as `path:line: <content>` plus a count. If it reports `[ ok ]`, nothing in the
to-be-published files mentions a private path — say so and stop.

`publish` runs this same detector on the commit it builds and, when dead references remain, offers
to chain straight into this skill — so you often arrive here *from* publish. When invoked that way,
scan the **built publish branch** (`--ref clean-remote/publish-<dev>-NNN`) and apply the fixes by
**amending that commit** (see "Where to apply the fixes" below), so the public branch stays one
commit and your source is untouched. Running it by hand is for previewing before you publish, or
auditing a tree publish didn't build.

**Doing less on repeat runs — `--since`.** A whole-tree scan re-examines every file each time. A
new dead reference can only appear in a file that *changed*, so `--since <ref>` restricts the scan
to the files changed between `<ref>` and the scanned tree — the delta a publish would carry. Pass
the last-published source commit (the `clean-remote-source:` trailer on the public tip) to
re-check only new work. It's an optimisation, not a correctness change: a periodic full scan
(no `--since`) still catches references in files that went dead for other reasons.

## Fix each reference: rewrite or strip
For every hit, read the file and decide — this needs judgement, which is why a script can't do it:
- **Rewrite** when the reference should point somewhere public instead — e.g. a link to
  `.planning/api.md` whose content now lives at `docs/api.md`, or a sentence that should name the
  public doc. Repoint it.
- **Strip** when there is no public equivalent — remove the dead markdown link (keeping the
  surrounding sentence sensible), delete the dangling list item / `import` line, or drop the
  parenthetical mention.
- **Leave it** when the hit is intentional and *correct* publicly — e.g. a `.gitignore` entry that
  legitimately lists `.planning/`, or code/docs that name the path on purpose. The detector uses
  fixed-string matching, so it can over-match; don't strip blindly.

## Where to apply the fixes
**Recommended — scrub the published artifact, leave your source untouched.** Run `publish` first;
it builds a `clean-remote/publish-<dev>-NNN` branch holding the clean commit. Then point the
scanner at that branch and amend it in a throwaway worktree:

```bash
# 1) publish builds the clean commit on a branch (note the printed name)
sh "${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh" "<message>"

# 2) find dead refs in THAT artifact (its REMOTE_EXCLUDE paths are already stripped,
#    so the exclude list still comes from your dev branch via --branch)
sh "${CLAUDE_PLUGIN_ROOT}/scripts/scrub-refs.sh" --branch <dev> --ref clean-remote/publish-<dev>-NNN

# 3) edit in an isolated worktree on that branch, then amend the clean commit (keeps the
#    clean-remote-source trailer) and remove the worktree
git worktree add /tmp/cr-scrub clean-remote/publish-<dev>-NNN
#    ... rewrite/strip the references in /tmp/cr-scrub/<file> ...
git -C /tmp/cr-scrub commit -a --amend --no-edit
git worktree remove /tmp/cr-scrub
```

Then push as `publish` instructed (`git push <remote> clean-remote/publish-<dev>-NNN:<public>`).
Your dev branch — and its valid references to the private files — is never touched.

**Alternative — fix in source.** If a reference is genuinely wrong everywhere (a stale link that's
broken privately too, or one you want repointed in both places), edit the working tree, commit to
your dev branch, and re-publish. Don't strip a reference from source merely because it's dead
*publicly* — that loses a link that's still valid on your private branch.

You can also scan what's already on the remote with `--ref <remote>/<public-branch>` (fetch first)
to audit a branch you published before this skill existed.
