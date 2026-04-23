# Session Handoff

Last updated: 2026-04-23

## Project
- Repo: `porake-kanban-skill`
- Purpose: Markdown-based Kanban skill/plugin for Claude Code.
- Main data model: cards live as `.md` files inside a project's `kanban/` directory.

## Current State
- Shared parsing helpers were added in `skills/kanban-ai/scripts/card_utils.sh`.
- Board scripts now tolerate card files with `CRLF` line endings.
- `create_from_template.sh` now creates the target kanban directory if it does not exist.
- Blocked-card reporting now shows only unresolved blockers.
- `standup.sh`, `report.sh`, and `auto_archive.sh` use status dates from `## Narrative` when available instead of relying only on file mtime.

## Key Files
- `skills/kanban-ai/SKILL.md`: main skill behavior and workflow rules.
- `skills/kanban-ai/scripts/`: board operations and reporting scripts.
- `skills/kanban-ai/analysis/analyze.sh`: repository analysis workflow entrypoint.
- `.gitattributes`: shell scripts should stay LF-only.

## Useful Commands
```bash
# Run the quick local smoke test
bash ./smoke_test_quick.sh

# Run the local smoke test
bash ./smoke_test.sh

# Load the plugin in Claude Code
claude --plugin-dir .
```

## Next Good Steps
- Run one manual smoke test inside Claude Code with `/help` and a couple of card operations.
- Keep card narratives short and meaningful so context stays cheap for the model.

## Session Start Checklist
- Read this file.
- Read `skills/kanban-ai/SKILL.md` if changing skill behavior.
- Run syntax checks if shell scripts were edited.
- Use a temp board in `/tmp` for safe script testing.

## Session End Checklist
- Update this file with decisions, risks, and next steps.
- Mention any changed commands or workflows.
- Record unfinished work in `kanban/` cards when the change is substantial.

## Notes
- Cards are project-local. Different projects keep separate `kanban/` folders.
- The model does not keep these cards as permanent memory; it reads them on demand.
- Temp test boards created with `mktemp -d` usually live under `/tmp`.
