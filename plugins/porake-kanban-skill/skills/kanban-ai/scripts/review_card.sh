#!/usr/bin/env bash
# Resolve a review card by approving it or pulling it back into development.
# Usage: bash review_card.sh <kanban_dir> <card_id> approve|changes <reviewer> [next_assignee]
#
# Examples:
#   bash review_card.sh kanban/ 3 approve claude
#   bash review_card.sh kanban/ 3 changes claude
#   bash review_card.sh kanban/ 3 changes claude codex

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

usage() {
    echo "Usage: $0 <kanban_dir> <card_id> approve|changes <reviewer> [next_assignee]" >&2
}

KANBAN_DIR="${1:-}"
CARD_ID="${2:-}"
ACTION="${3:-}"
REVIEWER="${4:-}"
NEXT_ASSIGNEE="${5:-}"

if [ -z "$KANBAN_DIR" ] || [ -z "$CARD_ID" ] || [ -z "$ACTION" ] || [ -z "$REVIEWER" ]; then
    usage
    exit 1
fi

case "$ACTION" in
    approve|changes) ;;
    *)
        echo "Error: action must be 'approve' or 'changes'." >&2
        usage
        exit 1
        ;;
esac

if [ ! -d "$KANBAN_DIR" ]; then
    echo "Error: '$KANBAN_DIR' not found." >&2
    exit 1
fi

CARD_FILE=$(find_card_file_by_id "$KANBAN_DIR" "$CARD_ID" || true)
if [ -z "$CARD_FILE" ]; then
    echo "Error: Card #$CARD_ID not found in $KANBAN_DIR" >&2
    exit 1
fi

CURRENT_STATUS=$(field "$CARD_FILE" status)
CARD_TITLE=$(title "$CARD_FILE")
NORMALIZED_REVIEWER=$(normalize_field_value "$REVIEWER")

if [ "$CURRENT_STATUS" != "review" ]; then
    echo "Error: Card #$CARD_ID is '$CURRENT_STATUS', not 'review'." >&2
    echo "  Submit it with submit_for_review.sh before resolving review." >&2
    exit 1
fi

if [ -z "$NEXT_ASSIGNEE" ]; then
    NEXT_ASSIGNEE="$NORMALIZED_REVIEWER"
else
    NEXT_ASSIGNEE=$(normalize_field_value "$NEXT_ASSIGNEE")
fi

LOCK_DIR="$KANBAN_DIR/.review.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "REVIEW BUSY: another review action appears to be running for $KANBAN_DIR." >&2
    exit 1
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

if [ "$ACTION" = "approve" ]; then
    NEW_STATUS="done"
    NEW_ASSIGNEE=""
    SET_PRIORITY=0
    NEW_PRIORITY=""
    SUMMARY="APPROVED: #$CARD_ID $CARD_TITLE [review -> done] by $NORMALIZED_REVIEWER"
    NARRATIVE="Approved by '$NORMALIZED_REVIEWER' and finalized."
else
    NEW_STATUS="doing"
    NEW_ASSIGNEE="$NEXT_ASSIGNEE"
    SET_PRIORITY=1
    NEW_PRIORITY="High"
    SUMMARY="CHANGES: #$CARD_ID $CARD_TITLE [review -> doing] assigned to $NEXT_ASSIGNEE with High priority"
    NARRATIVE="Changes requested by '$NORMALIZED_REVIEWER'; pulled back into development with High priority for '$NEXT_ASSIGNEE'."
fi

TMP=$(mktemp)
quoted_assignee=$(yaml_quote "$NEW_ASSIGNEE")

awk \
    -v status="$NEW_STATUS" \
    -v assignee="$quoted_assignee" \
    -v set_priority="$SET_PRIORITY" \
    -v priority="$NEW_PRIORITY" '
    { sub(/\r$/, "") }
    /^---$/ {
        if (fm == 1) {
            if (!status_done) {
                print "status: " status
            }
            if (set_priority == 1 && !priority_done) {
                print "priority: " priority
            }
            if (!assignee_done) {
                print "assignee: " assignee
            }
        }
        fm++
        print
        next
    }
    fm == 1 && /^status:[ \t]*/ {
        print "status: " status
        status_done = 1
        next
    }
    fm == 1 && /^priority:[ \t]*/ {
        if (set_priority == 1) {
            print "priority: " priority
        } else {
            print
        }
        priority_done = 1
        next
    }
    fm == 1 && /^assignee:[ \t]*/ {
        print "assignee: " assignee
        assignee_done = 1
        next
    }
    { print }
' "$CARD_FILE" > "$TMP" && mv "$TMP" "$CARD_FILE"

append_narrative "$CARD_FILE" "- $(date +%Y-%m-%d): $NARRATIVE (by @assistant)"

echo "$SUMMARY"
echo "FILE: $CARD_FILE"
