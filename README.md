# jakobmusik — Claude Code plugins

A small **marketplace** of [Claude Code](https://code.claude.com) plugins, in one repo. Each
plugin is self-contained under [`plugins/`](./plugins); the catalog at
[`.claude-plugin/marketplace.json`](./.claude-plugin/marketplace.json) lists them all. Adding a
plugin is just a new folder plus one catalog entry — see [Add a plugin](#add-a-plugin).

## Plugins

| Plugin | What it does | Docs |
|--------|--------------|------|
| **notify** | Phone push notifications (via [ntfy.sh](https://ntfy.sh)) when a session stops and awaits you, asks a multiple-choice question, or hits a permission prompt. The notification body is the session name. | [plugins/notify](./plugins/notify) |
| **clean-remote** | Keep planning/agent-helper files tracked locally with full history while publishing one clean, scrubbed commit to a public remote; a pre-push hook enforces it. | [plugins/clean-remote](./plugins/clean-remote) |

## Install

Add this repo as a marketplace once, then install any plugin from it. Replace
`<your-github-user>` with wherever you host this repo (the repo doubles as its own marketplace).

```
/plugin marketplace add <your-github-user>/claude-code-plugins
/plugin install notify@jakobmusik
/plugin install clean-remote@jakobmusik
```

Or add it straight from a local clone:

```
/plugin marketplace add /path/to/claude-code-plugins
/plugin install notify@jakobmusik
```

`jakobmusik` is the **marketplace name** (from `marketplace.json`); the part before `@` is the
plugin name. Each plugin installs and updates independently.

## Repository layout

```
claude-code-plugins/
├── .claude-plugin/
│   └── marketplace.json          # the catalog: one entry per plugin
├── plugins/
│   ├── notify/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── SKILL.md              # the /notify skill
│   │   ├── hooks/hooks.json      # Stop / AskUserQuestion / PermissionRequest
│   │   ├── scripts/
│   │   └── README.md
│   ├── clean-remote/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── skills/<skill>/SKILL.md   # setup, publish, sync, doctor, …
│   │   ├── scripts/
│   │   └── README.md
│   └── README.md                 # index of the plugins
├── LICENSE
└── README.md
```

Inside each plugin, the component folders (`skills/`, `hooks/`, `commands/`, `agents/`,
`scripts/`) live at the **plugin root** — only `plugin.json` goes in `.claude-plugin/`. This
mirrors the layout used by [`anthropics/claude-code`](https://github.com/anthropics/claude-code/tree/main/plugins).

## Add a plugin

1. Create `plugins/<your-plugin>/.claude-plugin/plugin.json` with at least `name` and
   `description` (add `version`, `author` as you like — each plugin versions independently).
2. Add whatever the plugin ships alongside it: `skills/<name>/SKILL.md`, `hooks/hooks.json`,
   `commands/*.md`, `agents/*.md`, `scripts/`. Reference bundled files with
   `${CLAUDE_PLUGIN_ROOT}` so paths resolve under the plugin loader.
3. Append one entry to `.claude-plugin/marketplace.json`:

   ```json
   {
     "name": "<your-plugin>",
     "source": "./plugins/<your-plugin>",
     "description": "One line on what it does."
   }
   ```
4. Add a row to the table above and a `plugins/<your-plugin>/README.md`.
5. Validate locally: `/plugin marketplace add /path/to/claude-code-plugins` then
   `/plugin install <your-plugin>@jakobmusik`.

## License

See [LICENSE](./LICENSE). Individual plugins may carry their own notices in their folders.
