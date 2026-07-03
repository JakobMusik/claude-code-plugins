---
name: notify
description: >-
  Set up phone push notifications (via ntfy.sh) for Claude Code on this machine, so the user
  gets pinged when Claude stops and is awaiting them, asks them a multiple-choice question, or
  hits a permission prompt — with the session name as the notification text. Use when the user wants to
  "set up notifications", "notify me when Claude finishes / asks me something / needs permission",
  mentions "ntfy" or "push notifications", "alert me when the agent is done", or wants to
  (re)configure, change, or test the notification topic. The Stop / AskUserQuestion /
  PermissionRequest hooks ship with this skill as a skills-dir plugin and fire session-wide;
  invoking this skill configures the private ntfy topic and verifies delivery.
allowed-tools: Bash
---

# notify — ntfy push notifications for Claude Code

Ping the user's phone when a Claude Code session needs them. Three moments are wired, as
**session-wide hooks bundled with this skill** (the `notify@skills-dir` plugin's
`hooks/hooks.json`):

| Event | Fires when | ntfy title / emoji / priority |
|-------|-----------|-------------------------------|
| `Stop` | Claude finished its turn and is awaiting the user | "Done - awaiting you" ✅ high |
| `PreToolUse` (matcher `AskUserQuestion`) | Claude is asking the user a multiple-choice question | "Question for you" ❓ max |
| `PermissionRequest` | Claude is blocked needing a tool approved | "Permission needed" 🔒 max |

The notification **body is the session name** — the title set with `/rename` (e.g.
`notify-skill-creation`), shown in the session list. If the session was never named, it falls
back to the working-directory basename. The script reads it from the session transcript, so a
mid-session `/rename` is reflected.

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
SCRIPT="$HOME/.claude/skills/notify/scripts/ntfy-notify.sh"   # this skill's bundled script
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

5. **Activate the hooks.** The bundled hooks load when the `notify@skills-dir` plugin loads —
   on a fresh session, or after **`/reload-plugins`** in the current one. Tell the user to run
   `/reload-plugins` (or restart Claude Code) so the Stop / AskUserQuestion / PermissionRequest
   hooks take effect now. (Editing `hooks/hooks.json` later also requires `/reload-plugins`.)

Finish by summarizing: the topic + subscribe URL, that a test was sent, the three wired events,
and that the message body is the session name.

## Prerequisites

- `curl` and `jq` on `PATH` (both standard on macOS/Linux). The hook fails silent if missing.
- The topic must be set — the script refuses to POST without a real topic, so the hooks are
  harmless no-ops until `/notify` configures one.

## Managing it later

- **See / change the topic:** `"$SCRIPT" show-topic` · `"$SCRIPT" set-topic [TOPIC]`
- **Re-test:** `"$SCRIPT" test`
- **Override without touching the file:** set `NTFY_TOPIC=<topic>` in the environment; it wins
  over the stored topic.
- **Turn it off:** `claude plugin disable notify@skills-dir`, or delete
  `~/.claude/skills/notify/`. Re-enable with `claude plugin enable notify@skills-dir`.
- **Manual test wiring:** the hooks call `ntfy-notify.sh stop|askuserquestion|permission_request`
  with the hook JSON on stdin.
