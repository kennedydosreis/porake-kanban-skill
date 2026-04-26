# Multi-Agent Architectural Analysis

A Claude Code workflow for analyzing large repositories without burning through a single context window. Built on top of the `kanban-ai` skill, with Bash and PowerShell entrypoints.

## The problem

You point Claude at a large repo and ask for an architectural analysis. One of three things happens:

1. Context fills up before Claude finishes reading.
2. Claude skims everything superficially to fit in context.
3. Claude produces a generic report that doesn't reference specific files.

## The approach

Break the analysis into a kanban board of small, scoped cards. Each card has one objective, a bounded file scope, and an assigned specialist role. A fresh Claude subprocess handles each card — no shared context, no memory bleed. Findings accumulate in each card's `## Narrative` section with `file:line` citations. A final synthesis pass consolidates everything into an action board.

## Pipeline

```
  Repo ──► Profiler ──► Decomposer ──► Specialists ──► Synthesizer ──► Action board
   │         │            │              │                │               │
   │       profile.md    N cards      N Narratives     review.md       M action cards
   │                     in kanban/   filled in        + cards         ready for work
   │
   └── Each phase is a separate Claude invocation; context is never reused.
```

## Requirements

- Claude Code CLI (`claude`) installed and authenticated — this is how specialists are invoked.
- The `kanban-ai` skill loaded in Claude Code.
- A target repository accessible on disk.

## Quick start

From your working directory (not the target repo — the analysis lives outside):

```bash
bash analyze.sh /path/to/target/repo
```

```powershell
& .\analyze.ps1 /path/to/target/repo
```

This creates:
- `kanban/analysis/.project-profile.md` — repository inventory
- `kanban/analysis/*.md` — one card per analysis task
- `kanban/actions/ARCHITECTURE-REVIEW.md` — executive summary
- `kanban/actions/*.md` — action cards ready for implementation

## Customizing

### Adding a specialist

Create `specialists/<name>.md` with these sections: Role, Focus areas, What you look for, Calibration, Output style. Look at `architect.md` as the template. The decomposer will auto-discover it on the next run.

### Changing the board location

```bash
bash analyze.sh /path/to/repo --kanban-dir my-boards/analysis --action-dir my-boards/actions
```

```powershell
& .\analyze.ps1 /path/to/repo -KanbanDir my-boards/analysis -ActionDir my-boards/actions
```

### Skipping the profiler (if you've already run it)

```bash
bash analyze.sh /path/to/repo --skip-profile
```

```powershell
& .\analyze.ps1 /path/to/repo -SkipProfile
```

### Adjusting decomposition behavior

Edit `prompts/decomposer.md`. The rules of decomposition (cards per analysis, scope granularity, specialist assignment logic) live there. Changes take effect on the next run.

## Understanding the output

### Analysis cards

Each card in `kanban/analysis/` follows this structure:

```markdown
---
id: 3
status: done
specialist: security-reviewer
scope: src/auth/
tags: [analysis]
---

# Review authentication flow

## Analysis Objective
...

## Narrative
- 2026-04-23: RISK — `src/auth/login.py:42` — ...
- 2026-04-23: OBSERVATION — `src/auth/session.py:15` — ...
```

The Narrative is the source of truth. Every finding cites a file and line.

### Action cards

Each card in `kanban/actions/` is a concrete piece of work, traceable back to the analysis cards that surfaced it. Priority is set based on the severity of the source finding. Size (`S`/`M`/`L`) is in tags.

### Executive summary

`ARCHITECTURE-REVIEW.md` is the human-readable overview — the TL;DR, strengths, risks, and strategic recommendations. It indexes the detailed findings by card ID so you can always drill down.

## Resuming an interrupted run

The analysis is naturally idempotent:

- If cards exist in the kanban directory, decomposition is skipped.
- Specialists process cards one at a time; cards in `doing` state are detected on resume.
- You can re-run `analyze.sh` with the same arguments to pick up where it stopped.

To force a fresh decomposition, delete `kanban/analysis/*.md` (keeping `.project-profile.md` if you want to skip re-profiling).

## What this MVP does not do (yet)

- **Multi-model routing.** Every call goes to Claude. Future: LiteLLM-based routing so specialists can use different backends (Anthropic, OpenAI, Ollama, llama.cpp).
- **Parallel specialist execution.** Cards are processed sequentially. Future: claims-based locking so multiple specialists run concurrently.
- **Cross-specialist deliberation.** Each specialist works independently, then synthesis consolidates. Future: a review round where specialists comment on each other's findings before synthesis.
- **Budget caps.** There is no cost ceiling. For a large repo with 12 cards, expect the same token cost as 12 medium Claude conversations.

These are on the roadmap for onda 2 and onda 3. The MVP is useful today without them.

## Directory layout

```
skills/kanban-ai/
├── SKILL.md
├── scripts/                 # Existing kanban operations
│   ├── view_board.sh
│   ├── transition.sh
│   ├── create_from_template.sh
│   └── templates/
│       ├── analysis.md      # NEW — template for analysis cards
│       ├── feature.md
│       ├── bug.md
│       └── ...
└── analysis/                # NEW — multi-agent analysis workflow
    ├── analyze.sh           # Bash orchestrator
    ├── analyze.ps1          # PowerShell orchestrator
    ├── profiler.sh          # Bash repo inventory
    ├── profiler.ps1         # PowerShell repo inventory
    ├── ANALYSIS.md          # This file
    ├── prompts/
    │   ├── decomposer.md
    │   ├── specialist.md
    │   └── synthesizer.md
    └── specialists/
        ├── architect.md
        ├── security.md
        └── code-quality.md
```
