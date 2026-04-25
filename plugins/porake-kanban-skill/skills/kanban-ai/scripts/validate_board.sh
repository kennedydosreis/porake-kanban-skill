#!/usr/bin/env bash
# Validate kanban board health.
# Checks: duplicate IDs, orphan dependencies, missing required fields, invalid statuses.
# Usage: bash validate_board.sh <kanban_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

# Requires Bash 4+ for associative arrays (declare -A).
# macOS ships Bash 3.2 by default — users there need `brew install bash` or similar.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "Error: validate_board.sh requires Bash 4+ (you have ${BASH_VERSION:-unknown})." >&2
    echo "  On macOS, install a newer bash: brew install bash" >&2
    exit 1
fi

KANBAN_DIR="${1:?Usage: $0 <kanban_dir>}"
ERRORS=0
WARNINGS=0

echo "=== BOARD VALIDATION ==="
echo

# Collect all IDs
declare -A id_map
all_ids=""

for dir in "$KANBAN_DIR" "$KANBAN_DIR/archived"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        id=$(field "$f" id)
        fname=$(basename "$f")

        # Check: missing ID
        if [ -z "$id" ]; then
            echo "ERROR: $fname has no 'id' field"
            ERRORS=$((ERRORS + 1))
            continue
        fi

        # Check: duplicate ID
        if [ -n "${id_map[$id]:-}" ]; then
            echo "ERROR: Duplicate ID #$id in '$fname' and '${id_map[$id]}'"
            ERRORS=$((ERRORS + 1))
        fi
        id_map[$id]="$fname"
        all_ids="$all_ids $id"

        # Check: missing status
        status=$(field "$f" status)
        if [ -z "$status" ]; then
            echo "ERROR: $fname (#$id) has no 'status' field"
            ERRORS=$((ERRORS + 1))
        elif ! echo "backlog todo doing review done archive" | grep -qw "$status"; then
            echo "ERROR: $fname (#$id) has invalid status '$status'"
            ERRORS=$((ERRORS + 1))
        fi

        # Check: priority value
        priority=$(field "$f" priority)
        if [ -n "$priority" ] && [ "$priority" != "High" ] && [ "$priority" != "Normal" ]; then
            echo "WARNING: $fname (#$id) has unusual priority '$priority' (expected: High or Normal)"
            WARNINGS=$((WARNINGS + 1))
        fi

        # Check: orphan blocked_by references
        blocked_raw=$(field "$f" blocked_by)
        if [ -n "$blocked_raw" ] && [ "$blocked_raw" != "[]" ]; then
            while IFS= read -r bid; do
                # We'll check these after collecting all IDs
                :
            done < <(list_values "$blocked_raw")
        fi

        # Check: missing Narrative section
        if ! grep -q "^## Narrative" "$f"; then
            echo "WARNING: $fname (#$id) has no '## Narrative' section"
            WARNINGS=$((WARNINGS + 1))
        fi
    done
done

# Second pass: check orphan dependencies
for dir in "$KANBAN_DIR" "$KANBAN_DIR/archived"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        id=$(field "$f" id)
        [ -z "$id" ] && continue
        blocked_raw=$(field "$f" blocked_by)
        if [ -z "$blocked_raw" ] || [ "$blocked_raw" = "[]" ]; then
            continue
        fi

        while IFS= read -r bid; do
            if [ -z "${id_map[$bid]:-}" ]; then
                echo "ERROR: #$id references non-existent blocker #$bid"
                ERRORS=$((ERRORS + 1))
            fi
        done < <(list_values "$blocked_raw")
    done
done

# Summary
echo
echo "--- RESULT ---"
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "Board is healthy. No issues found."
else
    echo "Errors:   $ERRORS"
    echo "Warnings: $WARNINGS"
fi

exit "$ERRORS"
