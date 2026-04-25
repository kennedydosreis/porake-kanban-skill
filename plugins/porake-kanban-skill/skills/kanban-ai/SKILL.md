---
name: kanban-ai
description: Manage a Markdown-based Kanban board using card files in a kanban/ directory (including kanban/archived/ for completed cards). Use when the user asks to create, claim, review, move, view, list, or manage tasks or cards on a kanban board, or when tracking work items across statuses like backlog, todo, doing, review, done, or archive.
---

# Kanban AI Skill

Manage a Kanban board as Markdown files in the `kanban/` directory. Each file is a card. The board state is derived by reading all card files and grouping by `status`.

## Narrative Record (Required)

Treat cards as durable source material for future review. Do not rewrite or delete prior narrative content unless explicitly asked. When updating a card, append a brief narrative note to a `## Narrative` section at the end of the file. Focus on reasons, discoveries, insights, and decisions. Avoid transactional status-change logs unless they matter to the story. Use ISO dates.

Narrative entry format:

```markdown
## Narrative
- 2026-02-05: Discovered the auth flow must support device-based MFA; shifted approach to use WebAuthn. (by @assistant)
```

If the card has no `## Narrative` section, add it. If a change is minor (e.g., typo), skip the narrative note unless it carries meaningful insight.

When a card is moved to `done`, add enough narrative detail that a future reader can understand the card’s story and outcome. Keep it coherent and complete without being verbose.

## Card Fields

Each card's frontmatter supports the following fields:

- `id` — Unique numeric identifier. Scan existing cards in `kanban/` (including `kanban/archived/`), take max + 1. Start at `1` if empty. Reference cards by this number.
- `status` — Column: `backlog`, `todo`, `doing`, `review`, `done`, or `archive`.
- `priority` — `High` or `Normal`. Defaults to `Normal` if omitted.
- `blocked_by` — List of card IDs that must be `done` before this card moves to `doing`. Example: `[3, 7]`. Omit or set to `[]` if unblocked.
- `assignee` — (optional) Owner of the card.
- `due_date` — (optional) Target date.
- `tags` — (optional) List of labels.

## Creating a Card

Create a new `.md` file in `kanban/`. Filename should be kebab-case.

If possible, include a Job Story using the structure “When [situation], I want to [motivation], so I can [expected outcome].” Do not force it; only add when it fits. If you add one, share it with the requester to confirm.

```markdown
---
id: 1
status: todo
priority: Normal
blocked_by: []
assignee: "@claude"
due_date: 2026-02-28
tags: [auth, backend]
---

# Implement User Authentication

Set up user authentication using JWTs.

## Acceptance Criteria
- Users can register for a new account.
- Users can log in with their credentials.
- Authenticated users receive a JWT.
```

## Moving a Card

Update the `status` field in frontmatter.

Before moving to `doing`, verify all IDs in `blocked_by` have status `done`. If any are not `done`, the card stays put.

Use `review` when implementation is complete but must be checked by the other provider before finalizing. Do not move a card directly from `doing` to `done` when another agent/provider is available to review it.

Cards with `status: done` may be moved into `kanban/archived/` to keep the main board tidy. This is a file-location move only; the card should remain a normal card with `status: done` unless explicitly changed.
If `kanban/archived/` does not exist, create it under the active cards folder (`kanban/`) before moving the card.

## Claiming Work for Parallel Agents

When multiple agents may work in parallel, claim a card before implementing it. A claim means:
- `status` is changed to `doing`
- `assignee` is set to the claiming agent, for example `codex` or `claude`
- a narrative entry is appended

Use `claim_next.sh` to pick the next unassigned, unblocked card. By default, it checks `todo` first, then `backlog`, prioritizes `High` cards, and uses the lowest card ID as the tie-breaker.

```bash
bash <SCRIPTS_DIR>/claim_next.sh kanban/ codex
bash <SCRIPTS_DIR>/claim_next.sh kanban/ claude
bash <SCRIPTS_DIR>/claim_next.sh kanban/ codex --from todo --wip-limit 3
bash <SCRIPTS_DIR>/claim_next.sh kanban/ codex --dry-run
```

Parallel-work rules:
- Before choosing work, reread the board or run `claim_next.sh --dry-run`.
- Never work on a card assigned to another agent.
- Prefer `claim_next.sh` over manually editing `status` and `assignee`.
- If agents are in separate clones, commit and push the claim before implementation; if push fails, pull and choose another card.
- If a card already has `assignee: codex` or `assignee: claude`, only that agent should continue it unless the user explicitly reassigns it.

## Cross-Provider Review

When one provider finishes implementation, send the card to the other provider for review instead of marking it `done` directly.

```bash
bash <SCRIPTS_DIR>/submit_for_review.sh kanban/ 3 claude
bash <SCRIPTS_DIR>/submit_for_review.sh kanban/ 3 codex
```

The card moves to `review` and `assignee` becomes the reviewer.

If the review is OK, finalize the card:

```bash
bash <SCRIPTS_DIR>/review_card.sh kanban/ 3 approve claude
```

If the review finds issues, the reviewer pulls it back into development:

```bash
bash <SCRIPTS_DIR>/review_card.sh kanban/ 3 changes claude
bash <SCRIPTS_DIR>/review_card.sh kanban/ 3 changes claude codex
```

Changes requested move the card back to `doing`, set `priority: High`, and assign it to the reviewer by default. Pass a fifth argument to assign the fix to a different provider.

Review rules:
- A provider should not review its own assigned card.
- `done` means implementation and review are complete.
- If review is rejected, treat the card as urgent until the requested changes are resolved.
- In separate clones, commit and push the review result before starting another card.

## Viewing the Board

Helper scripts are bundled in the `scripts/` directory alongside this skill file. To locate them, find this skill's directory within the installed plugin (e.g., using `glob` for `**/kanban-ai/scripts/view_board.sh`).

Run the board view script:

```bash
bash <SCRIPTS_DIR>/view_board.sh kanban/
```

Outputs cards grouped by status column, with priority and blocked_by flags inline.

## Searching and Filtering

### Search by Tag
```bash
bash <SCRIPTS_DIR>/search_by_tag.sh kanban/ <tag>
```
Output: Cards with that tag (ID, status, title)

### Search Content
```bash
bash <SCRIPTS_DIR>/search_content.sh kanban/ "<search term>"
```
Output: Cards matching the search term with context lines

### Show Blocked Cards
```bash
bash <SCRIPTS_DIR>/show_blocked.sh kanban/
```
Output: Cards with non-empty `blocked_by` field and what's blocking them

### List All Tags
```bash
bash <SCRIPTS_DIR>/list_tags.sh kanban/
```
Output: All tags sorted by usage count (most used first)

### List All Cards
```bash
bash <SCRIPTS_DIR>/list_all_cards.sh kanban/
```
Output: All cards in pipe-delimited format (id|status|blocked_by|title), sorted by ID. Useful for parsing, debugging dependencies, or exporting board state.

**Note:** `<SCRIPTS_DIR>` refers to the `scripts/` directory next to this SKILL.md file. All scripts take the kanban directory as the first argument. If omitted, they default to the current directory.

## Automation & Workflow

### Card Templates

Create cards from predefined templates. Available types: `feature`, `bug`, `spike`, `chore`. Each template includes the appropriate structure (Job Story for features, Steps to Reproduce for bugs, Time Box for spikes, etc.). The script auto-assigns the next ID.

```bash
bash <SCRIPTS_DIR>/create_from_template.sh kanban/ feature "Add OAuth support" "@claude" "2026-03-15"
bash <SCRIPTS_DIR>/create_from_template.sh kanban/ bug "Login form crashes on empty email"
bash <SCRIPTS_DIR>/create_from_template.sh kanban/ spike "Evaluate WebSocket vs SSE"
bash <SCRIPTS_DIR>/create_from_template.sh kanban/ chore "Update dependencies"
```

Templates are in `<SCRIPTS_DIR>/templates/`. Placeholders (`__TITLE__`, `__ID__`, etc.) are filled automatically. The created file still needs its body sections completed.

### Validated Transitions

Move cards between statuses with automatic rule enforcement. The script checks blocked_by dependencies, optional WIP limits, and appends a narrative entry on every transition.

```bash
bash <SCRIPTS_DIR>/transition.sh kanban/ 3 doing
bash <SCRIPTS_DIR>/transition.sh kanban/ 3 doing --wip-limit 3
bash <SCRIPTS_DIR>/transition.sh kanban/ 5 review
```

Rules enforced:
- Cards cannot move to `doing` if any `blocked_by` card is not `done`.
- If `--wip-limit N` is set, rejects the transition when `doing` already has N cards.
- A narrative line is auto-appended on every status change.
- Prefer `submit_for_review.sh` and `review_card.sh` over direct `done` transitions when another provider is available.

Prefer `transition.sh` over manual `sed` edits when moving cards. It ensures consistency.

### Auto-Archive

Move completed cards to `kanban/archived/` based on age. Useful for keeping the board clean.

```bash
bash <SCRIPTS_DIR>/auto_archive.sh kanban/ --days 7
bash <SCRIPTS_DIR>/auto_archive.sh kanban/ --days 3 --dry-run
```

Default threshold is 3 days. Use `--dry-run` to preview which cards would be archived.

### Daily Standup

Generate a standup summary: what's in progress, what's blocked, what was recently done, and what's next.

```bash
bash <SCRIPTS_DIR>/standup.sh kanban/
bash <SCRIPTS_DIR>/standup.sh kanban/ --days 2
```

The "Up Next" section ranks `todo` cards by priority (High first) and blocked status (unblocked first), showing the top 5 candidates.

### Board Report

Generate a metrics report: card distribution with visual bars, priority breakdown, overdue cards, aging cards (in `doing` > 7 days), throughput (last 7/30 days), and dependency chains.

```bash
bash <SCRIPTS_DIR>/report.sh kanban/
```

### Board Validation

Check board health for common problems: duplicate IDs, orphan dependency references, missing required fields, invalid statuses, and missing Narrative sections.

```bash
bash <SCRIPTS_DIR>/validate_board.sh kanban/
```

Returns exit code 0 if clean, or the number of errors found. Run this after bulk edits or imports.

## Multi-Agent Repository Analysis

For analyzing large repositories where a single context window is not enough, this skill bundles a separate workflow that breaks an architectural review into specialist-assigned kanban cards. The workflow lives in the `analysis/` directory next to this SKILL.md.

Use when the user asks to:
- analyze, review, or audit a repository's architecture
- identify risks, technical debt, or improvement opportunities across a whole codebase
- produce an action plan from a code review

Do NOT use this workflow for small single-file questions — it is intentionally heavyweight.

### How it works

The `analysis/analyze.sh` orchestrator runs four phases: profile the repo, decompose analysis into scoped cards, execute one specialist per card in a fresh subprocess, then synthesize a consolidated action board. Each specialist reads only the files its card scopes — context never bleeds between cards. Findings are written to each card's `## Narrative` section with `file:line` citations. The final output is an executive summary (`ARCHITECTURE-REVIEW.md`) plus a new kanban board of action cards ready for implementation.

```bash
bash <SCRIPTS_DIR>/../analysis/analyze.sh /path/to/target/repo
```

For full usage, customization (adding specialists, changing decomposition rules), and the design rationale, read `analysis/ANALYSIS.md` — it is the authoritative reference for this workflow.

### When working inside an analysis run

If invoked as a specialist on an analysis card (tag `analysis`, with a `specialist` and `scope` field):
- Read only files within the card's declared `scope`.
- Cite `file:line` on every finding. No citation means do not write the finding.
- Tag findings as `OBSERVATION`, `RISK`, or `RECOMMENDATION`.
- Use `transition.sh` to move the card to `done` when finished.
- Do not create new cards or modify other cards.

Full specialist rules are in `analysis/prompts/specialist.md`.
