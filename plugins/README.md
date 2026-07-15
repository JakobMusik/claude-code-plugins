# Plugins

Each subdirectory is a self-contained Claude Code plugin, catalogued in the repo-root
[`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json). Install any of them
with `/plugin install <name>@jakobmusik` (see the [top-level README](../README.md#install)).

| Plugin | Description | Ships |
|--------|-------------|-------|
| [notify](./notify) | Phone push notifications (via ntfy.sh) when Claude Code stops and awaits you, asks a multiple-choice question, or hits a permission prompt — titled `<session name>@<cwd>@<user>`, with your last message as the body. | 1 skill + session-wide hooks (Stop / AskUserQuestion / PermissionRequest) |
| [clean-remote](./clean-remote) | Local-overlay / clean-remote workflow: keep planning & agent-helper files tracked locally with full history while the public remote stays clean, scrubbed, and enforced by a pre-push hook. | 7 skills (setup, target, publish, scrub-refs, sync, doctor, uninstall) + scripts |

To add a new plugin, see [Add a plugin](../README.md#add-a-plugin) in the root README.
