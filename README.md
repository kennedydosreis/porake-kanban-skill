# porake-kanban-skill

A Markdown-based Kanban board plugin for Claude Code and Codex.

Cards live as `.md` files in a `kanban/` directory in your project. The board is derived at read-time — no database, no server. Status is tracked in YAML frontmatter.

## Install

Requires Claude Code **v1.0.33+** (`claude --version` to check).

## Shell Compatibility

The board utilities are available in both Bash and PowerShell:

- In Bash, run the `.sh` scripts with `bash`.
- In PowerShell, run the matching `.ps1` scripts directly with `&`.
- Prefer the native script for the current shell. Do not route PowerShell through Git Bash just to reach the Kanban scripts.

Examples:

```bash
bash plugins/porake-kanban-skill/skills/kanban-ai/scripts/view_board.sh kanban/
```

```powershell
& .\plugins\porake-kanban-skill\skills\kanban-ai\scripts\view_board.ps1 kanban\
```

### From a marketplace

If this plugin is available in a marketplace you've added:

```
/plugin install porake-kanban-skill@marketplace-name
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

The skill is model-invoked. Claude Code and Codex can use it automatically when you ask about tasks, cards, or your kanban board. You can also trigger it explicitly:

```
> create a new kanban card for implementing user auth
> show me the board
> move card 3 to doing
> what cards are blocked?
```

The plugin stores cards in a `kanban/` directory in your project root. Create it if it doesn't exist, or the agent can create it for you.

## Card Fields

| Field        | Required | Description                                                                 |
|--------------|----------|-----------------------------------------------------------------------------|
| `id`         | Yes      | Auto-increment integer. Max existing + 1, start at 1.                       |
| `status`     | Yes      | `backlog` · `todo` · `doing` · `review` · `done` · `archive`                |
| `priority`   | No       | `High` or `Normal` (default)                                                |
| `blocked_by` | No       | List of card IDs that must be `done` first. e.g. `[2, 5]`                   |
| `assignee`   | No       | Empty means available; `codex` or `claude` reserves/owns it                 |
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

## Parallel Agent Workflow

Codex and Claude can share the same board because the board is just `kanban/*.md` files in the target repository. The plugin uses `assignee` as a lightweight ownership marker.

Assignee convention:

- Empty `assignee` means the card is available for any provider to claim.
- `assignee: "codex"` means Codex owns or is responsible for the card.
- `assignee: "claude"` means Claude owns or is responsible for the card.
- Pre-filled assignees reserve work; `claim_next.sh` only claims unassigned cards by default.

Typical parallel flow:

```bash
# Provider claims the next unassigned, unblocked card.
bash <SCRIPTS_DIR>/claim_next.sh kanban/ codex

# Implementation is complete; send it to the other provider.
bash <SCRIPTS_DIR>/submit_for_review.sh kanban/ 3 claude

# Reviewer approves and finalizes.
bash <SCRIPTS_DIR>/review_card.sh kanban/ 3 approve claude

# Or reviewer requests changes and pulls it back as high priority.
bash <SCRIPTS_DIR>/review_card.sh kanban/ 3 changes claude
```

```powershell
# Provider claims the next unassigned, unblocked card.
& <SCRIPTS_DIR>/claim_next.ps1 kanban/ codex

# Implementation is complete; send it to the other provider.
& <SCRIPTS_DIR>/submit_for_review.ps1 kanban/ 3 claude

# Reviewer approves and finalizes.
& <SCRIPTS_DIR>/review_card.ps1 kanban/ 3 approve claude

# Or reviewer requests changes and pulls it back as high priority.
& <SCRIPTS_DIR>/review_card.ps1 kanban/ 3 changes claude
```

Status flow:

```text
backlog -> todo -> doing -> review -> done -> archive
```

If review requests changes, the card returns to `doing`, gets `priority: High`, and is assigned to the reviewer by default. Pass a fifth argument to assign the fix to another provider:

```bash
bash <SCRIPTS_DIR>/review_card.sh kanban/ 3 changes claude codex
```

When Codex and Claude run in separate clones, use Git as the cross-clone lock: pull before claiming, commit and push the claim/review result before starting implementation, and if push fails, pull again and choose another card.

## Plugin Structure

```
porake-kanban-skill/                 # Marketplace repo
├── .claude-plugin/
│   └── marketplace.json             # Marketplace manifest
├── plugins/
│   └── porake-kanban-skill/         # The plugin itself
│       ├── .claude-plugin/
│       │   └── plugin.json          # Plugin manifest
│       └── skills/
│           └── kanban-ai/
│               ├── SKILL.md         # Skill definition and instructions
│               └── scripts/         # Board view and search utilities
├── kanban/                          # Example card storage (per-project)
├── README.md
└── LICENSE
```

## Bundled Scripts

The plugin includes helper scripts for board operations. Claude Code and Codex use these automatically, but you can also run them directly:

| Script              | Purpose                               |
|---------------------|---------------------------------------|
| `view_board.(sh|ps1)`     | Display board grouped by status       |
| `search_by_tag.(sh|ps1)`  | Find cards by tag                     |
| `search_content.(sh|ps1)` | Full-text search across cards         |
| `show_blocked.(sh|ps1)`   | List blocked cards and their blockers |
| `list_tags.(sh|ps1)`      | Show tag usage with counts            |

Scripts are located at `plugins/porake-kanban-skill/skills/kanban-ai/scripts/` within the plugin directory.

## Local Testing

Quick smoke test:

```bash
bash ./smoke_test_quick.sh
```

```powershell
& .\smoke_test_quick.ps1
```

Full local smoke test:

```bash
bash ./smoke_test.sh
```

```powershell
& .\smoke_test.ps1
```

## License

Apache-2.0

## Changelog
See [CHANGELOG.md](CHANGELOG.md).
