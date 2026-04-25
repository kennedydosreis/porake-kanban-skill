#!/usr/bin/env bash
# Submit a claimed card for review by another agent.
# Usage: bash submit_for_review.sh <kanban_dir> <card_id> <reviewer>
#
# Example: bash submit_for_review.sh kanban/ 3 claude

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

usage() {
    echo "Usage: $0 <kanban_dir> <card_id> <reviewer>" >&2
}

KANBAN_DIR="${1:-}"
CARD_ID="${2:-}"
REVIEWER="${3:-}"

if [ -z "$KANBAN_DIR" ] || [ -z "$CARD_ID" ] || [ -z "$REVIEWER" ]; then
    usage
    exit 1
fi

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
CURRENT_ASSIGNEE=$(normalize_field_value "$(field "$CARD_FILE" assignee)")
NORMALIZED_REVIEWER=$(normalize_field_value "$REVIEWER")

case "$CURRENT_STATUS" in
    done|archive)
        echo "Error: Card #$CARD_ID is already '$CURRENT_STATUS' and cannot be submitted for review." >&2
        exit 1
        ;;
esac

if [ -n "$CURRENT_ASSIGNEE" ] && [ "$CURRENT_ASSIGNEE" = "$NORMALIZED_REVIEWER" ]; then
    echo "Error: Reviewer '$NORMALIZED_REVIEWER' is already the card assignee." >&2
    echo "  Choose the other provider for review." >&2
    exit 1
fi

LOCK_DIR="$KANBAN_DIR/.review.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "REVIEW BUSY: another review action appears to be running for $KANBAN_DIR." >&2
    exit 1
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

TMP=$(mktemp)
quoted_reviewer=$(yaml_quote "$NORMALIZED_REVIEWER")

awk -v assignee="$quoted_reviewer" '
    { sub(/\r$/, "") }
    /^---$/ {
        if (fm == 1) {
            if (!status_done) {
                print "status: review"
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
        print "status: review"
        status_done = 1
        next
    }
    fm == 1 && /^assignee:[ \t]*/ {
        print "assignee: " assignee
        assignee_done = 1
        next
    }
    { print }
' "$CARD_FILE" > "$TMP" && mv "$TMP" "$CARD_FILE"

TODAY=$(date +%Y-%m-%d)
if [ -n "$CURRENT_ASSIGNEE" ]; then
    actor="'$CURRENT_ASSIGNEE'"
else
    actor="the current agent"
fi
append_narrative "$CARD_FILE" "- $TODAY: Submitted for review by $actor; assigned review to '$NORMALIZED_REVIEWER'. (by @assistant)"

echo "REVIEW: #$CARD_ID $CARD_TITLE [$CURRENT_STATUS -> review] assigned to $NORMALIZED_REVIEWER"
echo "FILE: $CARD_FILE"
