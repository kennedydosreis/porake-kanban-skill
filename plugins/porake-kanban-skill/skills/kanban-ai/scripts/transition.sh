#!/usr/bin/env bash
# Transition a card to a new status with validation.
# Enforces: blocked_by checks, WIP limits, valid transitions.
# Usage: bash transition.sh <kanban_dir> <card_id> <new_status> [--wip-limit N]
#
# Example: bash transition.sh kanban/ 3 doing --wip-limit 3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

KANBAN_DIR="${1:?Usage: $0 <kanban_dir> <card_id> <new_status> [--wip-limit N]}"
CARD_ID="${2:?Specify card ID}"
NEW_STATUS="${3:?Specify new status: backlog, todo, doing, review, done, archive}"
WIP_LIMIT=0

shift 3
while [ $# -gt 0 ]; do
    case "$1" in
        --wip-limit) WIP_LIMIT="${2:?--wip-limit requires a number}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

VALID_STATUSES="backlog todo doing review done archive"
if ! echo "$VALID_STATUSES" | grep -qw "$NEW_STATUS"; then
    echo "Error: Invalid status '$NEW_STATUS'. Must be one of: $VALID_STATUSES" >&2
    exit 1
fi

# Find the card file by ID
CARD_FILE=$(find_card_file_by_id "$KANBAN_DIR" "$CARD_ID" || true)

if [ -z "$CARD_FILE" ]; then
    echo "Error: Card #$CARD_ID not found in $KANBAN_DIR" >&2
    exit 1
fi

CURRENT_STATUS=$(field "$CARD_FILE" status)
CARD_TITLE=$(title "$CARD_FILE")

# Validate: no-op
if [ "$CURRENT_STATUS" = "$NEW_STATUS" ]; then
    echo "Card #$CARD_ID is already '$NEW_STATUS'. No change." >&2
    exit 0
fi

# Validate: blocked_by check when moving to doing
if [ "$NEW_STATUS" = "doing" ]; then
    blockers=$(unresolved_blockers "$KANBAN_DIR" "$CARD_FILE" | xargs)
    if [ -n "$blockers" ]; then
        echo "BLOCKED: Card #$CARD_ID cannot move to 'doing'." >&2
        echo "  Unresolved blockers: $blockers" >&2
        exit 1
    fi
fi

# Validate: WIP limit on 'doing'
if [ "$NEW_STATUS" = "doing" ] && [ "$WIP_LIMIT" -gt 0 ]; then
    doing_count=0
    for f in "$KANBAN_DIR"/*.md; do
        [ -f "$f" ] || continue
        s=$(field "$f" status)
        [ "$s" = "doing" ] && doing_count=$((doing_count + 1))
    done

    if [ "$doing_count" -ge "$WIP_LIMIT" ]; then
        echo "WIP LIMIT: Already $doing_count cards in 'doing' (limit: $WIP_LIMIT)." >&2
        echo "  Finish or move existing cards before starting new work." >&2
        exit 1
    fi
fi

# Apply transition (portable awk-based in-place edit: GNU/BSD sed differ on -i)
TMP=$(mktemp)
awk -v s="$NEW_STATUS" '
    { sub(/\r$/, "") }
    !done_flag && /^status:[ \t]/ { print "status: " s; done_flag=1; next }
    { print }
' "$CARD_FILE" > "$TMP" && mv "$TMP" "$CARD_FILE"

# Append narrative entry
TODAY=$(date +%Y-%m-%d)
NARRATIVE_LINE="- $TODAY: Status changed from '$CURRENT_STATUS' to '$NEW_STATUS'. (by @assistant)"

append_narrative "$CARD_FILE" "$NARRATIVE_LINE"

echo "OK: Card #$CARD_ID '$CARD_TITLE' moved from '$CURRENT_STATUS' -> '$NEW_STATUS'"
