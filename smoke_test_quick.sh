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
        echo "Quick smoke test failed: $label" >&2
        echo "Expected to find: $needle" >&2
        exit 1
    fi
}

trap cleanup EXIT

step "Syntax Checks"
run bash -n "$ROOT_DIR/smoke_test_quick.sh"
run bash -n "$SCRIPTS_DIR/card_utils.sh"
run bash -n "$SCRIPTS_DIR/create_from_template.sh"
run bash -n "$SCRIPTS_DIR/transition.sh"
run bash -n "$SCRIPTS_DIR/view_board.sh"
run bash -n "$SCRIPTS_DIR/validate_board.sh"

step "Create And Move Card"
WORK_DIR="$(mktemp -d "$TEMP_BASE/kanban-smoke-quick-XXXXXX")"
BOARD_DIR="$WORK_DIR/board"
printf 'Using board directory: %s\n' "$BOARD_DIR"

run bash "$SCRIPTS_DIR/create_from_template.sh" "$BOARD_DIR" chore "Quick Smoke Card"

cards_output="$(bash "$SCRIPTS_DIR/list_all_cards.sh" "$BOARD_DIR")"
printf '%s\n' "$cards_output"
assert_contains "$cards_output" "1|backlog||Quick Smoke Card" "new card should be listed in backlog"

run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 1 todo
run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 1 doing
run bash "$SCRIPTS_DIR/transition.sh" "$BOARD_DIR" 1 done

step "Board Validation"
board_output="$(bash "$SCRIPTS_DIR/view_board.sh" "$BOARD_DIR")"
printf '%s\n' "$board_output"
assert_contains "$board_output" "#1 Quick Smoke Card" "board should show the test card"

validation_output="$(bash "$SCRIPTS_DIR/validate_board.sh" "$BOARD_DIR")"
printf '%s\n' "$validation_output"
assert_contains "$validation_output" "Board is healthy. No issues found." "board should validate cleanly"

step "Done"
echo "Quick smoke test passed."
