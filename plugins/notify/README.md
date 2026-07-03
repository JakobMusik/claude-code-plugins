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
notification, and prints a `https://ntfy.sh/<topic>` subscribe URL. The topic is saved to
`${XDG_CONFIG_HOME:-~/.config}/claude-code-notify/topic` — outside the plugin dir, so it
survives updates and reinstalls.

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
├── hooks/hooks.json          # Stop / PreToolUse(AskUserQuestion) / PermissionRequest
├── scripts/ntfy-notify.sh    # posts to ntfy; body = session name
├── SKILL.md                  # the /notify skill: configure topic, test, guide
└── README.md
```

## License
MIT — see the repo-root [LICENSE](../../LICENSE).
