#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$ROOT_DIR/skills/kanban-ai/scripts"
TEMP_BASE="${TMPDIR:-/tmp}"
WORK_DIR=""
BOARD_DIR=""

cleanup() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

step() {
    printf '\n== %s ==\n' "$1"
}

run() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    "$@"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if ! printf '%s' "$haystack" | grep -Fq "$needle"; then
        echo "Smoke test failed: $label" >&2
        echo "Expected to find: $needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if printf '%s' "$haystack" | grep -Fq "$needle"; then
        echo "Smoke test failed: $label" >&2
        echo "Did not expect to find: $needle" >&2
        exit 1
    fi
}

trap cleanup EXIT

step "Syntax Checks"
run bash -n "$ROOT_DIR/smoke_test.sh"
while IFS= read -r -d '' file; do
    run bash -n "$file"
done < <(find "$ROOT_DIR/skills" -name '*.sh' -print0)

step "Create Temp Board"
WORK_DIR="$(mktemp -d "$TEMP_BASE/kanban-smoke-XXXXXX")"
BOARD_DIR="$WORK_DIR/board"
printf 'Using board directory: %s\n' "$BOARD_DIR"

run bash "$SCRIPTS_DIR/create_from_template.sh" "$BOARD_DIR" chore "Smoke Test Chore"
run bash "$SCRIPTS_DIR/create_from_template.sh" "$BOARD_DIR" feature "Smoke Test Feature"

cat <<EOF > "$BOARD_DIR/blocked-follow-up.md"
---
id: 3
status: todo
priority: Normal
blocked_by: [2]
tags: [smoke]
---

# Blocked Follow Up

## Description
Smoke test card with a dependency.

## Narrative
- $(date +%Y-%m-%d): Added as a dependent card for smoke testing.
EOF

cards_output="$(bash "$SCRIPTS_DIR/list_all_cards.sh" "$BOARD_DIR")"
assert_contains "$cards_output" "1|backlog||Smoke Test Chore" "template chore card should exist"
assert_contains "$cards_output" "2|backlog||Smoke Test Feature" "template feature card should exist"
assert_contains "$cards_output" "3|todo|2|Blocked Follow Up" "manual dependent card should exist"

step "Blocked Card Detection"
blocked_output="$(bash "$SCRIPTS_DIR/show_blocked.sh" "$BOARD_DIR")"
printf '%s\n' "$blocked_output"
assert_contains "$blocked_output" "#3" "dependent card should be listed as blocked"
assert_contains "$blocked_output" "#2(backlog)" "blocked output should show unresolved blocker status"

step "Transitions"
run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 1 todo
run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 1 doing
run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 1 done
run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 2 todo
run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 2 doing
run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 2 done

blocked_after_done="$(bash "$SCRIPTS_DIR/show_blocked.sh" "$BOARD_DIR")"
printf '%s\n' "$blocked_after_done"
assert_not_contains "$blocked_after_done" "#3" "resolved blockers should disappear from blocked view"

run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 3 doing

step "Board Views And Reports"
board_output="$(bash "$SCRIPTS_DIR/view_board.sh" "$BOARD_DIR")"
printf '%s\n' "$board_output"
assert_contains "$board_output" "#3 Blocked Follow Up" "dependent card should be visible on the board"
assert_not_contains "$board_output" "[blocked:" "resolved dependency should not render as blocked"

standup_output="$(bash "$SCRIPTS_DIR/standup.sh" "$BOARD_DIR" --days 1)"
printf '%s\n' "$standup_output"
assert_contains "$standup_output" "#1 Smoke Test Chore" "standup should include completed chore"
assert_contains "$standup_output" "#2 Smoke Test Feature" "standup should include completed feature"
assert_contains "$standup_output" "#3 Blocked Follow Up" "standup should include in-progress dependent card"

report_output="$(bash "$SCRIPTS_DIR/report.sh" "$BOARD_DIR")"
printf '%s\n' "$report_output"
assert_contains "$report_output" "CARD DISTRIBUTION:" "report should render distribution"
assert_contains "$report_output" "THROUGHPUT:" "report should render throughput"

step "Search And Validation"
tag_output="$(bash "$SCRIPTS_DIR/search_by_tag.sh" "$BOARD_DIR" smoke)"
printf '%s\n' "$tag_output"
assert_contains "$tag_output" "#3" "tag search should find smoke card"

search_output="$(bash "$SCRIPTS_DIR/search_content.sh" "$BOARD_DIR" "dependency")"
printf '%s\n' "$search_output"
assert_contains "$search_output" "Blocked Follow Up" "content search should find dependent card"

tags_output="$(bash "$SCRIPTS_DIR/list_tags.sh" "$BOARD_DIR")"
printf '%s\n' "$tags_output"
assert_contains "$tags_output" "chore" "tag list should include chore"
assert_contains "$tags_output" "feature" "tag list should include feature"
assert_contains "$tags_output" "smoke" "tag list should include smoke"

archive_output="$(bash "$SCRIPTS_DIR/auto_archive.sh" "$BOARD_DIR" --days 1 --dry-run)"
printf '%s\n' "$archive_output"
assert_contains "$archive_output" "No cards eligible for archiving" "freshly completed cards should not archive in dry run"

validation_output="$(bash "$SCRIPTS_DIR/validate_board.sh" "$BOARD_DIR")"
printf '%s\n' "$validation_output"
assert_contains "$validation_output" "Board is healthy. No issues found." "board should validate cleanly"

step "Done"
echo "Smoke test passed."
