# clean-remote

A Claude Code plugin for the **local-overlay / clean-remote** workflow: keep planning and
agent-helper files tracked locally with full history, while the public remote stays clean.

## Why
Some files you want versioned locally — planning notes, agent instructions, design drafts —
but never on a public remote. The fragile way is to remember to scrub before each push. This
plugin makes the clean remote a property of the setup, not a habit:

- **each local dev branch** carries its own local-only files (committed, with history) and
  maps to its **own public squashed branch** — `feat/login` → `origin/feat/login`,
  `spike/cache` → `origin/spike/cache`, and so on; nothing is shared between them;
- **`REMOTE_EXCLUDE.md`** declares those paths and lists itself — read from each branch's own
  committed copy, so a branch can keep its own paths private;
- **`publish`** builds one clean commit for the current branch's public counterpart — carrying
  only the new work since that branch's last publish, with those paths stripped — so each
  public history stays linear and every push fast-forwards (the first publish *creates* the
  public branch);
- a git **`pre-push` hook** blocks any push to the public remote that still contains a
  private path — so a stray `git push` can't leak.

Junk that needs no history isn't this plugin's job — that just goes in `.gitignore`. Keep the
two lists **disjoint**: tracked-but-off-remote → `REMOTE_EXCLUDE.md`, pure scratch → `.gitignore`,
never both (a gitignored path is never committed, so there's no history for `publish` to strip).
`doctor` flags any overlap.

## Installation
`clean-remote` is a Claude Code plugin shipped in the **`jakobmusik`** marketplace — the
[`claude-code-plugins`](../../) repo, whose root `.claude-plugin/marketplace.json` catalogs it.
Add the marketplace once, then install this plugin.

**From the hosted repo:**

    /plugin marketplace add JakobMusik/claude-code-plugins
    /plugin install clean-remote@jakobmusik

**From a local clone** — add the marketplace repo, then install:

    /plugin marketplace add /path/to/claude-code-plugins
    /plugin install clean-remote@jakobmusik

**For development** — load the working copy without installing (use `/reload-plugins` to pick
up edits live):

    claude --plugin-dir /path/to/claude-code-plugins/plugins/clean-remote

Verify with `/plugin` (Installed tab) or `/plugin list`. Skills under `skills/` are
auto-discovered — no registration needed — and appear namespaced as `clean-remote:setup`,
`clean-remote:target`, `clean-remote:publish`, `clean-remote:scrub-refs`, `clean-remote:sync`,
`clean-remote:doctor`, and `clean-remote:uninstall`.

### Manual installation (no plugin)
If you'd rather drop the skills straight into one project as a fixed copy — no marketplace, no
plugin machinery — use the bundled installer:

    sh /path/to/clean-remote/install.sh /path/to/your/project

It copies the skills into `<project>/.claude/skills/` and the scripts into
`<project>/.claude/clean-remote-scripts/`, then rewrites each skill's `${CLAUDE_PLUGIN_ROOT}`
reference to an absolute path. That variable is **only** set by the plugin loader, so without the
rewrite a non-plugin copy would try to run `sh "/scripts/setup.sh"` and fail — which is also why
simply copying the `skills/` folder by hand (or fetching it with a skills installer such as
`npx skills install`) isn't enough on its own.

Installed this way the skills are **un-namespaced** project skills — `setup`, `target`, `publish`,
`scrub-refs`, `sync`, `doctor`, `uninstall` (no `clean-remote:` prefix) — and travel with that one
repo. The rewritten
paths are absolute; if you relocate the project, re-run the installer. Everything else (the
`setup` → `publish` → `doctor` flow) works exactly as below.

## Skills
| Skill | What it does |
|-------|--------------|
| `setup` | Stamp the repo: record config (remote + publish-branch template), create `REMOTE_EXCLUDE.md`, install the pre-push guard, set `worktree.baseRef=head`. Idempotent; auto-migrates an old single-branch config. |
| `target` | Show or change which public branch a local dev branch publishes to — list the whole branch→public map, set a per-branch override, or revert to the template. Config-only; never pushes. |
| `publish` | Forward-port the current branch's new work onto its public branch tip (creating it on first publish), strip `REMOTE_EXCLUDE` paths, leave a clean commit ready to push. `--branch <name>` to target another. Never pushes; never touches your tree. |
| `scrub-refs` | Find references (links, imports, mentions) in the to-be-published files that point at `REMOTE_EXCLUDE` paths — dead on the public remote, since `publish` strips the targets — so you can rewrite or strip them. Read-only detector; `--ref` scans the publish artifact or a remote branch. |
| `sync` | The reverse of publish: cherry-pick external public commits (e.g. a merged contributor PR) back into the matching dev branch, so it stays a superset of its public branch. Never moves your branch; hands back the apply command. |
| `doctor` | Verify the guard, settings, and — per branch — exclude list (incl. no `.gitignore` overlap), history relationship, pending external commits, and that nothing private already leaked. `--all` scans every managed branch. |
| `uninstall` | Remove the hook, the `baseRef` override, the repo config, and the per-branch keys. Keeps your files, branches, and published commits. |

## Quick start
`setup`, `publish`, and `doctor` are **skills** — invoke them inside Claude Code (e.g. ask it
to "run clean-remote setup"). The `git` commands below run in your shell.

**1. One-time, per repo.** On your working branch, with the remote already configured, run the
**`setup`** skill. It stamps the repo (git config, pre-push hook, `worktree.baseRef=head` — see
[Configuration](#configuration)) and creates `REMOTE_EXCLUDE.md`. Idempotent, so re-running is safe.

**2. Declare your local-only paths.** Edit `REMOTE_EXCLUDE.md` to list the paths you want kept
local (one git pathspec per line, e.g. `.planning/`), then commit it on your branch:

    git add REMOTE_EXCLUDE.md && git commit -m "Track local-only paths"

**3. Work as usual.** Commit everything — public changes *and* the local-only files — to your
private branch. That's where they live, with full history, and they never get pushed:

    git add -A && git commit -m "your work"

**4. Publish when ready.** Run the **`publish`** skill with a one-line summary. It forward-ports
your branch's new work onto the remote tip, strips the `REMOTE_EXCLUDE` paths, and prints three commands —
**review**, **push**, **tidy**. Review the diff, then run the printed `push` yourself; `publish`
never pushes for you. `publish` removes the private *files*, but a published file may still *link to*
or *mention* one — run the **`scrub-refs`** skill to find those now-dead references and rewrite or
strip them before pushing.

**5. Pull contributions back (when a PR lands on the remote).** If someone merges a PR onto the
public branch, run the **`sync`** skill. It cherry-picks the external commit(s) onto a
`clean-remote/sync-*` branch and prints **review**, **apply**, **tidy** — apply it with the
printed `git merge --ff-only` to bring the work into your private branch. Publishing keeps the PR
either way, but syncing it back keeps your private branch the source of truth (and avoids a future
conflict if you later edit the same lines). See [Working with contributors](#working-with-contributors).

Run the **`doctor`** skill anytime to confirm the setup is healthy and nothing private has leaked.

## Configuration
clean-remote stores its settings in **git config** — the same mechanism as `user.name` or
`remote.origin.url`. `setup` writes them with `git config clean-remote.<key> <value>`, which
lands in the repo's local config file (`.git/config`). Git never tracks its own config, so these
settings are **per-repo, local, and never pushed** by construction — which is also why a fresh
clone starts without them (re-run `setup` there).

There is **no single `source` branch** — commands act on the current branch (or `--branch
<name>`), and each branch maps to its own public branch. Settings split into repo-wide keys and
per-branch keys (the latter under git's own `branch.<name>.*` namespace, alongside
`branch.<name>.remote`):

| key | scope | meaning | default |
|-----|-------|---------|---------|
| `clean-remote.remote` | repo | the remote you publish to — and the one the pre-push guard protects | `origin` |
| `clean-remote.publishBranchTemplate` | repo | maps a local branch name to its public branch name; `%s` is the branch name | `%s` (same name) |
| `branch.<B>.cleanRemotePublish` | branch | explicit public-branch name for local branch `B` (overrides the template) | unset → template |
| `branch.<B>.cleanRemoteSyncpoint` | branch | last commit `sync` integrated for `B` — lets the next publish diff from *after* integrated PR work (managed automatically; honoured only while it's an ancestor of `B`) | unset until first `sync` |

So with the default template, local `feat/x` publishes to `origin/feat/x`. To change where a
branch publishes, the easiest path is the **`target`** skill (it validates and warns about the
caveat below); under the hood it's plain git config you can also run yourself:

    # show the whole map (which branch -> which public branch, override vs template)
    git config --get-regexp 'cleanRemotePublish'          # just the overrides
    # point feat/x at a different public branch
    git config branch.feat/x.cleanRemotePublish public/feat-x
    # revert feat/x to the same-name template
    git config --unset branch.feat/x.cleanRemotePublish

A change takes effect on the **next publish**; nothing is pushed. One caveat: repointing a
branch that has *already published* re-baselines on the new target — the old public branch is
left as-is (not updated, not deleted), and if the new target doesn't exist yet the first
publish *creates* it. `doctor` shows the resulting mapping per branch.

Set the repo-wide keys at setup time with env vars — `CR_REMOTE`, `CR_TEMPLATE` — or
`CR_PUBLISH=<name>` to set the *current* branch's override. Change any key later with `git
config` — and re-running `setup` **preserves** whatever is already set (the env vars override an
existing value; a bare re-run never resets `remote`/`template` or any per-branch override back to
defaults). Inspect everything with `git config --get-regexp '^clean-remote\.'` and `git config
--get-regexp 'cleanRemote'`. The skills read these (falling back to the defaults above), so you
rarely pass anything by hand.

**Upgrading from the old single-branch config?** `setup` auto-migrates
`clean-remote.{source,publishBranch,syncpoint}` into the per-branch keys above
(`branch.<source>.cleanRemotePublish` / `cleanRemoteSyncpoint`) and removes the old globals.

`REMOTE_EXCLUDE.md` (repo root) is the path list — one git pathspec per line, `#` comments
allowed. Unlike the git-config settings above, it **is** tracked: committed on each dev branch
(with history) and listing itself, so the policy travels with the branch but never reaches the
remote. It's read from **each branch's own committed copy**, so different dev branches can
declare different private paths — the guard and `publish` apply the right list per branch.

## Notes & limits
- **Incremental, conflict-free re-publishes.** Each publish forward-ports only the new work
  since the last one — tracked by a `clean-remote-source` trailer on that branch's public commit
  — onto the current public tip. Re-editing an already-published file just works, and commits
  made directly on the public branch (e.g. a merged PR) survive. A genuine overlap (the public
  branch changed the same lines as your new work) is surfaced for you to reconcile by hand,
  not forced. The first publish *creates* the public branch as a clean orphan snapshot of the
  dev branch minus excludes; recovery after a private-history rewrite resyncs the same way.
  `doctor` reports the state per branch.
- **One clean commit per publish.** Each publish puts a single scrubbed commit on top of the
  remote tip; your commit-by-commit private history stays local. Great for a clean public log —
  not a mirror of your local commits.
- **The pre-push guard stops accidents, it is not a security boundary.** It's bypassable with
  `git push --no-verify`, and it only guards the **one** remote named in `clean-remote.remote` —
  pushes to any *other* remote (a second fork, say) aren't checked. Point that config at the
  remote you actually push to.
- **The setup is local and unversioned — re-run `setup` after a fresh clone.** The hook lives in
  `.git/hooks/` and `worktree.baseRef=head` lives in `.claude/settings.local.json` (which Claude
  Code gitignores by default); neither is committed. Until you re-run `setup`, the guard is absent
  and new worktrees branch from the remote instead of your local line.
- **Single-writer on each private line.** Your dev branches are yours; each public branch is a
  publish target that others can contribute to via PRs (see below). Heavy multi-writer
  collaboration on a *private* branch itself is out of scope.

## Working with contributors
The public branch is a normal branch — people can fork it, open PRs, and you can merge them on the
host (GitHub, etc.). clean-remote handles both directions:

- **Outbound (`publish`).** Each publish forward-ports your new private work *onto* the current
  remote tip, so a merged PR sitting on the public branch is **preserved**, never clobbered.
- **Inbound (`sync`).** A merged PR lives only on the public remote until you pull it back. Run
  **`sync`** to cherry-pick the external commits into your private branch (it skips your own
  publishes and anything already integrated, by patch-id). Apply the printed `git merge --ff-only`.

**Why sync back instead of just letting publish preserve it?** Your private branch is the source
of truth. If you *don't* integrate a PR, your branch silently lacks it — and the next time you
edit a line that PR also touched, publish hits a genuine "public changed the same lines" conflict.
Syncing keeps private ⊇ public, so that never happens. `sync` records a per-branch
`branch.<name>.cleanRemoteSyncpoint` so the next publish diffs from *after* the integrated work;
without it, publish's "last published" marker would sit before the PR and conflict against a
stale base.
