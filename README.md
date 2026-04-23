# porake-kanban-skill

A Markdown-based Kanban board plugin for [Claude Code](https://claude.com/claude-code).

Cards live as `.md` files in a `kanban/` directory in your project. The board is derived at read-time — no database, no server. Status is tracked in YAML frontmatter.

## Install

Requires Claude Code **v1.0.33+** (`claude --version` to check).

### From a marketplace

If this plugin is available in a marketplace you've added:

```
/plugin install kanban@marketplace-name
```

### From a local clone

Clone the repo and load it directly during development or personal use:

```bash
git clone https://github.com/kennedydosreis/porake-kanban-skill.git
claude --plugin-dir ./porake-kanban-skill
```

You can also load multiple plugins at once:

```bash
claude --plugin-dir ./porake-kanban-skill --plugin-dir ./other-plugin
```

### Verify installation

First, validate the plugin manifest:

```bash
claude plugins validate .
```

Then start Claude Code with the plugin loaded:

```bash
claude --plugin-dir .
```

The most reliable check is a functional one. Inside Claude Code, try:

```text
> show me the kanban board
> create a new kanban card for smoke testing
> what cards are blocked?
```

If those prompts cause Claude Code to load the `porake-kanban-skill:kanban-ai` skill and operate on the `kanban/` directory, the plugin is working correctly. Depending on Claude Code version, `/help` may not list the skill explicitly even when the plugin is loaded.

## Usage

The skill is model-invoked — Claude will use it automatically when you ask about tasks, cards, or your kanban board. You can also trigger it explicitly:

```
> create a new kanban card for implementing user auth
> show me the board
> move card 3 to doing
> what cards are blocked?
```

The plugin stores cards in a `kanban/` directory in your project root. Create it if it doesn't exist — or Claude will create it for you.

## Card Fields

| Field        | Required | Description                                                                 |
|--------------|----------|-----------------------------------------------------------------------------|
| `id`         | Yes      | Auto-increment integer. Max existing + 1, start at 1.                       |
| `status`     | Yes      | `backlog` · `todo` · `doing` · `done` · `archive`                           |
| `priority`   | No       | `High` or `Normal` (default)                                                |
| `blocked_by` | No       | List of card IDs that must be `done` first. e.g. `[2, 5]`                   |
| `assignee`   | No       | Who owns the card                                                           |
| `due_date`   | No       | Target date (YYYY-MM-DD)                                                    |
| `tags`       | No       | List of labels                                                              |

## Example Card

`kanban/setup-ci.md`:

```markdown
---
id: 3
status: todo
priority: High
blocked_by: [1, 2]
tags: [devops]
---

# Set Up CI Pipeline

Configure GitHub Actions for automated testing.
```

## Rules

- A card cannot move to `doing` until all cards in its `blocked_by` list are `done`.
- IDs are assigned by scanning existing cards and incrementing the highest.
- Cards maintain a `## Narrative` section — a durable log of decisions, discoveries, and outcomes.

## Plugin Structure

```
porake-kanban-skill/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── skills/
│   └── kanban-ai/
│       ├── SKILL.md          # Skill definition and instructions
│       └── scripts/          # Board view and search utilities
├── kanban/                   # Example card storage (per-project)
├── README.md
└── LICENSE
```

## Bundled Scripts

The plugin includes helper scripts for board operations. Claude uses these automatically, but you can also run them directly:

| Script              | Purpose                               |
|---------------------|---------------------------------------|
| `view_board.sh`     | Display board grouped by status       |
| `search_by_tag.sh`  | Find cards by tag                     |
| `search_content.sh` | Full-text search across cards         |
| `show_blocked.sh`   | List blocked cards and their blockers |
| `list_tags.sh`      | Show tag usage with counts            |

Scripts are located at `skills/kanban-ai/scripts/` within the plugin directory.

## Local Testing

Quick smoke test:

```bash
bash ./smoke_test_quick.sh
```

Full local smoke test:

```bash
bash ./smoke_test.sh
```

## License

Apache-2.0

## Changelog
See [CHANGELOG.md](CHANGELOG.md).
