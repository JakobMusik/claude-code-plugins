# claude-code-plugins

A personal **marketplace** of [Claude Code](https://code.claude.com) plugins, kept in one repo.
Add the marketplace once and install any plugin from it; new plugins are just a folder plus a
catalog entry.

| Plugin | What it does |
|--------|--------------|
| **[notify](./plugins/notify)** | Phone push notifications (via [ntfy.sh](https://ntfy.sh)) when a session stops and is awaiting you, asks you a multiple-choice question, or hits a permission prompt — titled **`<session name>@<project>@<user>`** with **your last message** as the body, so you know which session and what you asked it at a glance. |
| **[clean-remote](./plugins/clean-remote)** | Keep planning and agent-helper files tracked locally with full history while the **public remote stays clean** — one scrubbed commit per publish, enforced by a `pre-push` hook so a stray push can't leak. |

## Install

Add this repo as a marketplace, then install whichever plugins you want. Each installs and
updates independently.

```
/plugin marketplace add JakobMusik/claude-code-plugins
/plugin install notify@jakobmusik
/plugin install clean-remote@jakobmusik
```

`jakobmusik` is the **marketplace name** (from [`marketplace.json`](./.claude-plugin/marketplace.json));
the part before `@` is the plugin name. Prefer a local clone? Point the marketplace at the
directory instead:

```
/plugin marketplace add /path/to/claude-code-plugins
/plugin install notify@jakobmusik
```

Each plugin has its own setup — see its README: [notify](./plugins/notify/README.md) ·
[clean-remote](./plugins/clean-remote/README.md).

## Layout

```
claude-code-plugins/
├── .claude-plugin/
│   └── marketplace.json          # the catalog — one entry per plugin
├── plugins/
│   ├── notify/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── SKILL.md              # the /notify skill
│   │   ├── hooks/hooks.json      # Stop / AskUserQuestion / PermissionRequest
│   │   └── scripts/
│   └── clean-remote/
│       ├── .claude-plugin/plugin.json
│       ├── skills/<skill>/SKILL.md   # setup · target · publish · scrub-refs · sync · doctor · uninstall
│       └── scripts/
└── LICENSE
```

Inside a plugin, the component folders (`skills/`, `hooks/`, `commands/`, `agents/`,
`scripts/`) live at the **plugin root** — only `plugin.json` goes in `.claude-plugin/`. This
mirrors [`anthropics/claude-code`](https://github.com/anthropics/claude-code/tree/main/plugins),
the canonical multi-plugin layout.

## Add a plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json` with at least `name` and `description`
   (add `version` and `author` as you like — each plugin versions independently).
2. Add what it ships alongside: `skills/<name>/SKILL.md`, `hooks/hooks.json`, `commands/*.md`,
   `agents/*.md`, `scripts/`. Reference bundled files with `${CLAUDE_PLUGIN_ROOT}` so paths
   resolve under the plugin loader.
3. Append an entry to [`.claude-plugin/marketplace.json`](./.claude-plugin/marketplace.json):

   ```json
   {
     "name": "<name>",
     "source": "./plugins/<name>",
     "description": "One line on what it does."
   }
   ```
4. Add a row to the table above and a `plugins/<name>/README.md`.
5. Test before pushing: `/plugin marketplace add /path/to/claude-code-plugins`, then
   `/plugin install <name>@jakobmusik`.

## License

[MIT](./LICENSE). Individual plugins may carry their own notices in their folders.
