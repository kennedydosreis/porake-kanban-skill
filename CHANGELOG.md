# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-04-25

### Added
- Initial public release of the `porake-kanban-skill` plugin for Claude Code.
- Markdown-based Kanban board: cards as `.md` files in a `kanban/` directory.
- Bundled scripts: `view_board`, `transition`, `create_from_template`, `auto_archive`,
  `standup`, `report`, `validate_board`, `search_by_tag`, `search_content`,
  `show_blocked`, `list_tags`, `list_all_cards`.
- Card templates: `feature`, `bug`, `spike`, `chore`, `analysis`.
- Multi-agent repository analysis workflow under `skills/kanban-ai/analysis/`.
- Smoke tests (`smoke_test.sh`, `smoke_test_quick.sh`).
- Plugin marketplace manifest so the repo can be added via
  `/plugin marketplace add kennedydosreis/porake-kanban-skill`.
