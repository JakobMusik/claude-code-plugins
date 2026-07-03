# notify

Phone push notifications for [Claude Code](https://code.claude.com), delivered through
[ntfy.sh](https://ntfy.sh). Get pinged the moment a session needs you — the notification is
titled **`<session name>@<project>`** and its body is **Claude's latest reply**, so you know
*which* session and *what it said* without opening your laptop.

## What it does
Three moments are wired as **session-wide hooks** that ship with the plugin. Every one sends the
same shape; the emoji and priority tell them apart:

| Event | Fires when | Emoji / priority |
|-------|-----------|------------------|
| `Stop` | Claude finished its turn and is awaiting you | ✅ high |
| `PreToolUse` (`AskUserQuestion`) | Claude is asking you a multiple-choice question | ❓ max |
| `PermissionRequest` | Claude is blocked, needing you to approve a tool | 🔒 max |

**Title — `<session name>@<cwd>`.** The session name is read from the transcript by precedence:

1. the title you set with `/rename` (e.g. `fix-auth-bug`),
2. else the auto-generated summary title shown in the session list,
3. else the early auto agent-name.

`<cwd>` is the working-directory basename, so the title reads e.g. `fix-auth-bug@myapp`. A
mid-session `/rename` is reflected, and an explicit rename always wins over an auto name.

**Body — Claude's latest reply.** The first few lines of the last assistant message (long
replies are truncated with an `…`). If that turn was a bare tool call with no prose, the body
falls back to the title.

`AskUserQuestion` is wired on `PreToolUse` (not `PermissionRequest`, which never fires for it),
so the ping goes out the instant Claude poses the question — while it's still waiting on you.

## Install
`notify` is a Claude Code plugin shipped in the **`jakobmusik`** marketplace — the
[`claude-code-plugins`](../../) repo, whose root `.claude-plugin/marketplace.json` catalogs it.
Add the marketplace once, then install this plugin.

**From the hosted repo:**

    /plugin marketplace add JakobMusik/claude-code-plugins
    /plugin install notify@jakobmusik

**From a local clone** — add the marketplace repo, then install:

    /plugin marketplace add /path/to/claude-code-plugins
    /plugin install notify@jakobmusik

**For development** — load the working copy without installing (use `/reload-plugins` to pick up
edits live):

    claude --plugin-dir /path/to/claude-code-plugins/plugins/notify

## Basic usage
The plugin ships the hooks already declared; the only per-user setup is your **private ntfy
topic** — the channel your phone subscribes to.

**1. Configure the topic.** Run the skill once:

    /notify

It generates a private `claude-code-xxxxxxxx` topic (or accepts one you name), sends a test
notification, and prints a `https://ntfy.sh/<topic>` subscribe URL. The topic is saved **inside
the plugin** at `<plugin>/.config/topic`, so it's self-contained: uninstalling the plugin (or a
reinstall/update that replaces the plugin folder) removes it too — just re-run `/notify` to set
it again.

**2. Subscribe on your phone.** Open that URL in the [ntfy app](https://ntfy.sh) (iOS / Android)
or the web client and subscribe. This is what actually delivers pushes — without it, nothing
reaches your phone.

**3. Activate the hooks.** They load when the plugin loads: run **`/reload-plugins`** (or start a
fresh session). From then on, every Stop / AskUserQuestion / permission event in any session
pings you.

That's the whole setup. Re-run `/notify` anytime to see, change, or re-test the topic.

## How it works
- The plugin's `hooks/hooks.json` wires the three events to `scripts/ntfy-notify.sh` via
  `${CLAUDE_PLUGIN_ROOT}`. These are **plugin** hooks, so they fire session-wide and in every
  future session — unlike skill *frontmatter* hooks, which Claude Code scopes to a single turn.
- `ntfy-notify.sh` reads the hook JSON on stdin, finds the transcript, and from it composes the
  title (`<session name>@<cwd>`) and body (Claude's latest reply), then POSTs to
  `https://ntfy.sh/<your-topic>` with the event's emoji and priority. The curl is detached with
  tight timeouts, so it never delays Claude's turn.

## Desktop notifications on macOS (optional)
The hooks above push to your **phone**. If you also — or instead — want the pings as native
**macOS desktop banners**, the plugin bundles a companion receiver, `claude-code-ntfy`, in
[`desktop/`](desktop/). It subscribes to your ntfy topic(s) and turns each incoming message into a
macOS notification (same title + body).

It's a standalone script, not a hook, and nothing is installed for you. On macOS, `/notify` (its
optional step 6) just hands you the command to **copy the script out of the plugin folder** so you
own an editable copy — the plugin folder is version-stamped and replaced on every update, so copy
it out rather than editing in place:

    # copy it somewhere you control, then make it executable
    cp "${CLAUDE_PLUGIN_ROOT}/desktop/claude-code-ntfy.sh" ~/claude-code-ntfy.sh
    chmod +x ~/claude-code-ntfy.sh

    # run it directly (pass the topic /notify configured — see: ntfy-notify.sh show-topic),
    # or put it on your PATH to use as a bare command (see desktop/README.md)
    ~/claude-code-ntfy.sh your-topic

Run it **in place** instead — straight out of the plugin folder — and it needs no arguments: on
start it reads the `/notify` topic from `../.config/topic` *relative to itself* and auto-subscribes
(a copy sits outside the plugin folder, so it can't see that file — pass the topic, or set
`NTFY_TOPIC` / `NTFY_TOPIC_FILE`, the same overrides the sender honors):

    "${CLAUDE_PLUGIN_ROOT}/desktop/claude-code-ntfy.sh"   # auto-subscribes to the /notify topic

Type more topics at its prompt to add listeners; `quit` / Ctrl-C tears them all down cleanly.

**Dependencies (different from the sender):** the phone hooks send with plain `curl`, but the
desktop receiver *subscribes* via `ntfy sub`, so it needs the **[`ntfy` CLI](https://docs.ntfy.sh/install/)
installed** — `brew install ntfy`. It also needs `jq`, plus `terminal-notifier` (`brew install
terminal-notifier`, preferred) or the built-in `osascript`. Full details in
[`desktop/README.md`](desktop/README.md).

> Copy it again after a plugin update — the plugin's cache path is version-stamped, so don't
> symlink into it.

## Privacy
ntfy topics are **world-readable** — the topic name is the *only* thing keeping your messages
private. `/notify` generates a random `claude-code-xxxxxxxx` topic by default; keep it secret and
don't reuse a guessable or shared name. The script refuses to POST until a real topic is set, so
the hooks are harmless no-ops before setup. The topic file is never committed.

## Requirements
- `curl` on `PATH` to send (standard on macOS/Linux). Without it the hook fails silently.
- `jq` on `PATH` to read the session name from the transcript — without it the body falls back to
  the working-directory name.
- Claude Code with plugin support.

These cover the phone hooks. The optional **macOS desktop receiver** has *additional* deps — most
notably the **`ntfy` CLI** (`brew install ntfy`), since it subscribes with `ntfy sub` rather than
sending with `curl` — see [Desktop notifications on macOS](#desktop-notifications-on-macos-optional).

## Managing it
The script also runs standalone for topic management (`$SCRIPT` is
`${CLAUDE_PLUGIN_ROOT}/scripts/ntfy-notify.sh` from an installed plugin):

    "$SCRIPT" show-topic        # print the current topic + subscribe URL
    "$SCRIPT" set-topic [NAME]  # set a topic (random if NAME omitted)
    "$SCRIPT" test              # send a test notification

- **Override the topic without editing config:** set `NTFY_TOPIC=<topic>` in the environment;
  it wins over the stored file.
- **Turn it off:** disable via the `/plugin` menu, or `claude plugin disable notify@jakobmusik`.
- **Reload after editing `hooks/hooks.json`:** `/reload-plugins`.

> **Avoid double notifications:** if you *also* drop this in as a bare skills-dir install
> (`~/.claude/skills/notify/`) alongside the marketplace plugin, both register hooks and you'll
> get every ping twice. Keep one copy.

## Layout
```
plugins/notify/
├── .claude-plugin/plugin.json
├── hooks/hooks.json               # Stop / PreToolUse(AskUserQuestion) / PermissionRequest
├── scripts/ntfy-notify.sh         # sender: posts to ntfy; title=session, body=latest reply
├── desktop/                       # optional macOS receiver (subscribes → native banners)
│   ├── claude-code-ntfy.sh        #   the standalone command
│   └── README.md
├── SKILL.md                       # the /notify skill: configure topic, test, guide
└── README.md
```

## License
MIT — see the repo-root [LICENSE](../../LICENSE).
