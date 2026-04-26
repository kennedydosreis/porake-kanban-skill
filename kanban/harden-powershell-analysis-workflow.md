---
id: 1
status: done
priority: Normal
blocked_by: []
assignee: "codex"
due_date: 
tags: [chore]
---

# Harden PowerShell analysis workflow

## Description
Strengthen the PowerShell analysis pipeline so it behaves predictably when Claude does not create the expected artifacts, and document the cross-shell workflow clearly.

## Done When
- [x] `analysis/analyze.ps1` invokes Claude with explicit writable directories and permission mode.
- [x] The orchestrator fails when decomposition creates no analysis cards.
- [x] The orchestrator fails when synthesis does not create `ARCHITECTURE-REVIEW.md`.
- [x] Analysis prompts explicitly require creating files instead of only describing intended output.
- [x] The real Claude invocation was retried and the remaining blocker was identified as account usage limit, not shell incompatibility.

## Narrative
- 2026-04-26: Added native PowerShell analysis entrypoints plus stricter orchestration checks so the run now fails explicitly when Claude creates no cards or no executive summary. Verified the real run reaches Claude; the remaining blocker is Claude usage limit, not shell/runtime compatibility. (by @codex)
- 2026-04-26: Status changed from 'backlog' to 'done'. (by @assistant)
