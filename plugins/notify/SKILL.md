---
name: notify
description: >-
  Set up phone push notifications (via ntfy.sh) for Claude Code on this machine, so the user
  gets pinged when Claude stops and is awaiting them, asks them a multiple-choice question, or
  hits a permission prompt — titled with the session name and directory, with Claude's latest
  reply as the message. Use when the user wants to
  "set up notifications", "notify me when Claude finishes / asks me something / needs permission",
  mentions "ntfy" or "push notifications", "alert me when the agent is done", or wants to
  (re)configure, change, or test the notification topic. The Stop / AskUserQuestion /
  PermissionRequest hooks ship with this skill as a bundled plugin and fire session-wide;
  invoking this skill configures the private ntfy topic and verifies delivery.
allowed-tools: Bash
---

# notify — ntfy push notifications for Claude Code

Ping the user's phone when a Claude Code session needs them. Three moments are wired, as
**session-wide hooks bundled with this skill** (the `notify` plugin's
`hooks/hooks.json`):

| Event | Fires when | emoji / priority |
|-------|-----------|------------------|
| `Stop` | Claude finished its turn and is awaiting the user | ✅ high |
| `PreToolUse` (matcher `AskUserQuestion`) | Claude is asking the user a multiple-choice question | ❓ max |
| `PermissionRequest` | Claude is blocked needing a tool approved | 🔒 max |

Every notification carries the same shape; the emoji (ntfy Tags) and priority above tell the
events apart:

- **Title = `<session name>@<cwd>`.** The session name is read from the transcript by precedence —
  the title you set with `/rename` (e.g. `notify-skill-creation`) wins, else the auto-generated
  summary title, else the early agent name; it never sends a stale auto name over one you set
  yourself, and a mid-session `/rename` is reflected. `<cwd>` is the working-directory basename,
  so the title reads e.g. `fix-auth-bug@myapp` — *which* task in *which* project at a glance.
- **Body = the first few lines of Claude's latest reply** (the last assistant message's text).
  If that turn carried no prose (a bare tool call), the body falls back to the title.

Because these are **plugin** hooks (not skill-frontmatter hooks, which would only live for one
turn), they fire on every Stop / AskUserQuestion / permission event for the whole session and in
every future session — once the plugin is loaded.

> `AskUserQuestion` is an ordinary tool call, so it's wired on `PreToolUse` (matcher
> `AskUserQuestion`) — that fires the instant Claude poses the question, *before* the dialog
> blocks, so you're alerted while it's still waiting for you. (It is not a `Notification` or a
> `PermissionRequest`; those never fire for AskUserQuestion.)

## What invoking `/notify` does

The hooks are already declared; the only per-user setup is the **ntfy topic** (the private
channel your phone subscribes to). Run these steps. The topic is stored in a stable user-config
path — `${XDG_CONFIG_HOME:-~/.config}/claude-code-notify/topic` — so it is shared across every
install method and survives plugin updates.

```bash
# ${CLAUDE_PLUGIN_ROOT} is set when this runs as a marketplace/`--plugin-dir` plugin;
# the fallback covers a bare skills-dir install (~/.claude/skills/notify/).
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/notify}/scripts/ntfy-notify.sh"
chmod +x "$SCRIPT"
```

1. **Check for an existing topic.** Run `"$SCRIPT" show-topic`.
   - If it prints a topic, a topic is already configured. Report it and its subscribe URL. Keep
     it unless the user explicitly wants a new one.
   - If it says none is configured, configure one in step 2.

2. **Configure the topic** (only if none exists, or the user wants to change it):
   - If the user named a specific topic, use it: `"$SCRIPT" set-topic "<their-topic>"`.
   - Otherwise generate a random private one: `"$SCRIPT" set-topic` (prints a
     `claude-code-xxxxxxxx` topic).

   > ntfy topics are **world-readable** — the topic name is the *only* thing keeping messages
   > private. Prefer the generated random topic; never reuse a guessable/shared name. Don't post
   > the topic anywhere public.

3. **Tell the user to subscribe.** Give them the `https://ntfy.sh/<topic>` URL and tell them to
   subscribe to that topic in the ntfy app (iOS / Android) or the web client at that URL. Without
   subscribing, nothing reaches their phone.

4. **Send a test.** Run `"$SCRIPT" test` and ask the user to confirm the "Test - notify skill"
   notification arrived. If it didn't, check `curl`/network and that they subscribed to the exact
   topic.

5. **Activate the hooks.** The bundled hooks load when the `notify` plugin loads —
   on a fresh session, or after **`/reload-plugins`** in the current one. Tell the user to run
   `/reload-plugins` (or restart Claude Code) so the Stop / AskUserQuestion / PermissionRequest
   hooks take effect now. (Editing `hooks/hooks.json` later also requires `/reload-plugins`.)

Finish by summarizing: the topic + subscribe URL, that a test was sent, the three wired events,
and the notification shape — title `<session name>@<cwd>`, body the first lines of Claude's
latest reply.

## Prerequisites

- `curl` is required to send; without it the hook just fails silently. `jq` reads the session
  name from the transcript — without it the body falls back to the working-directory name. Both
  are standard on macOS/Linux.
- The topic must be set — the script refuses to POST without a real topic, so the hooks are
  harmless no-ops until `/notify` configures one.

## Managing it later

- **See / change the topic:** `"$SCRIPT" show-topic` · `"$SCRIPT" set-topic [TOPIC]`
- **Re-test:** `"$SCRIPT" test`
- **Override without touching the file:** set `NTFY_TOPIC=<topic>` in the environment; it wins
  over the stored topic.
- **Turn it off:** `claude plugin disable notify@jakobmusik` (or via the `/plugin` menu).
  Re-enable with `claude plugin enable notify@jakobmusik`. For a bare skills-dir install,
  delete `~/.claude/skills/notify/` instead.
- **Manual test wiring:** the hooks call `ntfy-notify.sh stop|askuserquestion|permission_request`
  with the hook JSON on stdin.
