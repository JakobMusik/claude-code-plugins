# claude-notify

Phone push notifications for [Claude Code](https://code.claude.com), delivered through
[ntfy.sh](https://ntfy.sh). Get pinged when a session needs you — **the notification text is
the session name**, so you know *which* session at a glance.

Three moments are wired as **session-wide hooks**:

| Event | Fires when | Notification |
|-------|-----------|--------------|
| `Stop` | Claude finished its turn and is awaiting you | ✅ **Done - awaiting you** (high) |
| `PreToolUse` (`AskUserQuestion`) | Claude is asking you a multiple-choice question | ❓ **Question for you** (max) |
| `PermissionRequest` | Claude is blocked, needing you to approve a tool | 🔒 **Permission needed** (max) |

The message **body is the session name** — the title you set with `/rename` (e.g.
`fix-auth-bug`), shown in the session list. If a session was never named, it falls back to the
working-directory name. It's read from the session transcript, so a mid-session `/rename` is
reflected.

## Install (as a plugin marketplace)

`notify` ships in the **`jakobmusik`** marketplace (this
[`claude-code-plugins`](../../) repo). Add the marketplace once, then install this plugin:

1. Push the marketplace repo to GitHub (see [Publish](#publish-your-copy)), then in Claude Code:

   ```
   /plugin marketplace add JakobMusik/claude-code-plugins
   /plugin install notify@jakobmusik
   ```

   Or add the marketplace straight from a local clone:

   ```
   /plugin marketplace add /path/to/claude-code-plugins
   /plugin install notify@jakobmusik
   ```

2. **Configure your private topic** — run the skill once:

   ```
   /notify
   ```

   It generates a private ntfy topic, sends a test notification, and prints a
   `https://ntfy.sh/<topic>` URL.

3. **Subscribe** to that URL in the [ntfy app](https://ntfy.sh) (iOS / Android) or the web
   client. That's what delivers pushes to your phone.

That's it. From then on, every Stop / AskUserQuestion / permission event in any session pings you.

## How it works

- The plugin ships `hooks/hooks.json`, which wires the three events to
  `scripts/ntfy-notify.sh` via `${CLAUDE_PLUGIN_ROOT}`. These are **plugin hooks**, so they
  fire session-wide and in every session — unlike skill *frontmatter* hooks, which the Claude
  Code docs scope to a single turn ("cleaned up when it finishes") and would not work here.
- `ntfy-notify.sh` reads the hook JSON on stdin, derives the session name from the transcript,
  and POSTs it to `https://ntfy.sh/<your-topic>` with a title/emoji/priority per event. The
  curl is detached with tight timeouts, so it never delays Claude's turn.
- Your topic is stored at `${XDG_CONFIG_HOME:-~/.config}/claude-code-notify/topic` — a stable
  path outside the plugin dir, so it survives plugin updates and is identical whether the
  script runs as a hook or a plain command. It is **never** committed.

## Privacy

ntfy topics are **world-readable** — the topic name is the *only* thing keeping your messages
private. `/notify` generates a random `claude-code-xxxxxxxx` topic by default; keep it secret
and don't reuse a guessable/shared name. The script refuses to POST until a real topic is set,
so the hooks are harmless no-ops before setup.

## Requirements

- `curl` and `jq` on `PATH` (standard on macOS/Linux).
- Claude Code with plugin support.

## Managing it

```bash
# from an installed plugin, the script lives in the plugin cache; these also work standalone:
notify/scripts/ntfy-notify.sh show-topic        # print current topic + subscribe URL
notify/scripts/ntfy-notify.sh set-topic [NAME]  # set a topic (random if NAME omitted)
notify/scripts/ntfy-notify.sh test              # send a test notification
```

- **Override the topic without editing config:** set `NTFY_TOPIC=<topic>` in the environment.
- **Turn it off:** `/plugin` → disable `notify`, or `claude plugin disable notify@claude-notify`.
- **Reload after editing hooks:** `/reload-plugins`.

> **Avoid double notifications:** if you also set this up as a manual skills-dir plugin
> (`~/.claude/skills/notify/`), disable or remove one copy — otherwise both register hooks and
> you'll get each ping twice.

## Repo layout

```
claude-code-notify/
├── .claude-plugin/marketplace.json   # the marketplace catalog (lists the notify plugin)
├── plugins/notify/                   # the plugin itself
│   ├── .claude-plugin/plugin.json
│   ├── hooks/hooks.json              # Stop / PreToolUse(AskUserQuestion) / PermissionRequest
│   ├── scripts/ntfy-notify.sh        # posts to ntfy; body = session name
│   └── SKILL.md                      # /notify: configure topic, test, guide
├── README.md
└── LICENSE
```

## Publish your copy

1. Edit `.claude-plugin/marketplace.json` (`owner.name`) and `LICENSE` (copyright) to your name.
2. Create a GitHub repo and push:

   ```bash
   git remote add origin git@github.com:<your-user>/claude-code-notify.git
   git push -u origin main
   ```

3. Share the install commands above (with your GitHub user) so others can add the marketplace.

## License

MIT — see [LICENSE](LICENSE).
