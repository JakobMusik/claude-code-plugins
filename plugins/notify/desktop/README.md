# claude-code-ntfy — native macOS desktop notifications

The `notify` plugin is the **sender**: Claude Code → your ntfy topic → your phone. This is the
optional **receiver** for the *same* topic: it subscribes to one or more ntfy topics and turns
each incoming message into a native **macOS notification banner** (same title + message). Use it
when you want the pings on your Mac's desktop, not (or in addition to) the phone.

It's a single self-contained script — it is **not** wired into any hook and nothing runs it
automatically. You install it as a command and run it yourself in a terminal.

```
ntfy topic  ──▶  ntfy sub (this script)  ──▶  parse JSON  ──▶  macOS banner
```

## Get your own copy

Nothing is installed for you. Copy the script out of the plugin folder into a location you own,
then edit it however you like. This matters because the plugin folder is **version-stamped** and
replaced on every update — edits made in place would be lost. (*Running* it in place is fine — and
has a perk: it finds your configured topic by itself, see [Usage](#usage) — just don't *edit* it
there.) On macOS, `/notify` (optional step 6) just hands you this same command.

```bash
# from an installed plugin, $CLAUDE_PLUGIN_ROOT points at the current version dir
cp "${CLAUDE_PLUGIN_ROOT:-.}/desktop/claude-code-ntfy.sh" ~/claude-code-ntfy.sh
chmod +x ~/claude-code-ntfy.sh
```

Run it directly whenever you want:

```bash
~/claude-code-ntfy.sh
```

Re-copy after a plugin update to pick up upstream script changes (you'll re-apply your edits).

## Optional: run it as a bare command

If you'd rather type `claude-code-ntfy` from anywhere, put your copy on your `PATH` — drop it in a
PATH dir you own, or symlink it there:

```bash
# e.g. Homebrew's bin (Apple Silicon) or ~/.local/bin
ln -sf ~/claude-code-ntfy.sh /opt/homebrew/bin/claude-code-ntfy
#   …or:  mkdir -p ~/.local/bin && ln -sf ~/claude-code-ntfy.sh ~/.local/bin/claude-code-ntfy
```

A symlink to *your* copy is fine (it's a stable path you control) — just don't symlink into the
version-stamped plugin cache, which moves on every update.

## Usage

Run it, type an ntfy **topic** (bare name ⇒ `https://ntfy.sh/<topic>`) or a full URL, and press
Enter — it spawns a background listener and adds it to a live list. Add as many as you like.

| At the `ntfy>` prompt | Does |
|-----------------------|------|
| `<topic \| url>`       | start listening (e.g. the `/notify` topic, if it wasn't auto-loaded) |
| `list` (or blank Enter) | show the numbered list with `live` / `DEAD` status |
| `rm <n>`              | stop and remove link *n* |
| `help`                | command reference |
| `quit` / Ctrl-C / Ctrl-D | stop **all** listeners and exit |

Preload links as arguments too: `claude-code-ntfy my-topic another-topic`.

**The `/notify` topic loads itself when the script runs from inside the plugin folder.** On start
the script looks for the sender's topic file at `../.config/topic` *relative to its own location*
(symlinks resolved, so any `$PWD` works) and auto-subscribes to it — the same file `/notify`
writes, which sits next to `desktop/` in the plugin root:

```bash
"${CLAUDE_PLUGIN_ROOT:-.}/desktop/claude-code-ntfy.sh"   # auto-subscribes to the /notify topic
```

`$NTFY_TOPIC` or `$NTFY_TOPIC_FILE` override that lookup — the same resolution order the sender
uses. A personal copy lives outside the plugin folder, so it finds no config and starts empty;
point it at the same channel by passing the topic (look it up any time with the sender's
`ntfy-notify.sh show-topic`) or by exporting one of those variables:

```bash
claude-code-ntfy your-topic                     # e.g. claude-code-xxxxxxxx
NTFY_TOPIC_FILE=~/my/topicfile claude-code-ntfy # or keep your own topic file
```

## How it works

- On start it resolves the notify plugin's configured topic — `$NTFY_TOPIC`, else the file named
  by `$NTFY_TOPIC_FILE`, else `../.config/topic` relative to the script's real (symlink-resolved)
  location — and auto-subscribes when one is found. The file's content is validated (topic charset
  or an `http(s)://` URL), so an unrelated file that happens to sit at that path is ignored.
- Each link runs `ntfy sub <url> | parse` in **its own process group**, so the `ntfy` process and
  its JSON parser are torn down together. A `trap` on `INT`/`TERM`/`EXIT` kills every listener's
  group on quit, Ctrl-C, Ctrl-D, or `kill` — no orphaned `ntfy sub` processes. (A `kill -9` of the
  manager can't run the trap, so that one case can orphan them — same as any program.)
- The parser filters ntfy's stream to real `message` events and fires a banner per message via
  `terminal-notifier` if installed, else `osascript`.
- The whole UI is width-aware: rules, the banner, the link list, and paths truncate to the
  terminal width, so it stays readable in a narrow pane.

## Requirements

- **`ntfy` CLI** — `brew install ntfy`. **Required** — this receiver *subscribes* with `ntfy sub`,
  so the CLI must be installed. (The `notify` plugin's phone hooks only use `curl`, so having those
  working does **not** mean `ntfy` is present — install it.)
- **`jq`** — `brew install jq` (parses the message stream)
- A notifier: **`terminal-notifier`** (`brew install terminal-notifier`, preferred — nicer banner,
  no permission gate) **or** the built-in **`osascript`**. With osascript, if banners don't
  appear, enable **System Settings ▸ Notifications ▸ Script Editor**.
- macOS (the notification backends are macOS-only).

## Note

`ntfy sub` only delivers messages published **while it's subscribed** — it never replays history.
Keep the listener running to catch pings as they happen; anything sent before you connect is
missed.
