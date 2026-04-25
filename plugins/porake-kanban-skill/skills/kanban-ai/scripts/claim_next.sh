#!/usr/bin/env bash
# Claim the next available card for an agent before starting parallel work.
# Usage: bash claim_next.sh <kanban_dir> <assignee> [--from "todo backlog"] [--wip-limit N] [--dry-run]
#
# Example: bash claim_next.sh kanban/ codex --wip-limit 3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

usage() {
    echo "Usage: $0 <kanban_dir> <assignee> [--from \"todo backlog\"] [--wip-limit N] [--dry-run]" >&2
}

KANBAN_DIR="${1:-}"
ASSIGNEE="${2:-}"
FROM_STATUSES="todo backlog"
WIP_LIMIT=0
DRY_RUN=0

if [ -z "$KANBAN_DIR" ] || [ -z "$ASSIGNEE" ]; then
    usage
    exit 1
fi

shift 2
while [ $# -gt 0 ]; do
    case "$1" in
        --from)
            FROM_STATUSES="${2:?--from requires one or more statuses}"
            shift 2
            ;;
        --wip-limit)
            WIP_LIMIT="${2:?--wip-limit requires a number}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ ! -d "$KANBAN_DIR" ]; then
    echo "Error: '$KANBAN_DIR' not found." >&2
    exit 1
fi

if ! [ "$WIP_LIMIT" -ge 0 ] 2>/dev/null; then
    echo "Error: --wip-limit must be a non-negative integer." >&2
    exit 1
fi

FROM_STATUSES=$(printf '%s\n' "$FROM_STATUSES" | tr ',' ' ' | xargs)
if [ -z "$FROM_STATUSES" ]; then
    echo "Error: --from must include at least one status." >&2
    exit 1
fi

for wanted_status in $FROM_STATUSES; do
    case "$wanted_status" in
        backlog|todo|doing|review|done|archive) ;;
        *)
            echo "Error: Invalid --from status '$wanted_status'." >&2
            exit 1
            ;;
    esac
done

normalize_assignee() {
    trim_quotes "${1-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

yaml_quote() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '"%s"\n' "$value"
}

status_rank_for() {
    local status="$1"
    local rank=0
    local wanted

    for wanted in $FROM_STATUSES; do
        rank=$((rank + 1))
        if [ "$status" = "$wanted" ]; then
            printf '%s\n' "$rank"
            return 0
        fi
    done

    return 1
}

append_narrative() {
    local file="$1"
    local line="$2"
    local tmp

    if grep -q "^## Narrative" "$file"; then
        tmp=$(mktemp)
        awk -v line="$line" '
            { sub(/\r$/, "") }
            !added && /^## Narrative/ { print; print line; added=1; next }
            { print }
        ' "$file" > "$tmp" && mv "$tmp" "$file"
    else
        printf "\n## Narrative\n%s\n" "$line" >> "$file"
    fi
}

claim_card() {
    local file="$1"
    local old_status="$2"
    local tmp
    local quoted_assignee

    quoted_assignee=$(yaml_quote "$ASSIGNEE")
    tmp=$(mktemp)

    awk -v assignee="$quoted_assignee" '
        { sub(/\r$/, "") }
        /^---$/ {
            if (fm == 1 && !assignee_done) {
                print "assignee: " assignee
                assignee_done = 1
            }
            fm++
            print
            next
        }
        fm == 1 && /^status:[ \t]*/ {
            print "status: doing"
            status_done = 1
            next
        }
        fm == 1 && /^assignee:[ \t]*/ {
            print "assignee: " assignee
            assignee_done = 1
            next
        }
        fm == 1 && /^blocked_by:[ \t]*/ {
            print
            if (!assignee_done) {
                print "assignee: " assignee
                assignee_done = 1
            }
            next
        }
        { print }
    ' "$file" > "$tmp" && mv "$tmp" "$file"

    append_narrative \
        "$file" \
        "- $(date +%Y-%m-%d): Claimed by '$ASSIGNEE' and moved from '$old_status' to 'doing'. (by @assistant)"
}

LOCK_DIR="$KANBAN_DIR/.claim.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "CLAIM BUSY: another claim appears to be running for $KANBAN_DIR." >&2
    echo "  Retry after the other agent finishes claiming a card." >&2
    exit 1
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

if [ "$WIP_LIMIT" -gt 0 ]; then
    doing_count=0
    for f in "$KANBAN_DIR"/*.md; do
        [ -f "$f" ] || continue
        [ "$(field "$f" status)" = "doing" ] && doing_count=$((doing_count + 1))
    done

    if [ "$doing_count" -ge "$WIP_LIMIT" ]; then
        echo "WIP LIMIT: Already $doing_count cards in 'doing' (limit: $WIP_LIMIT)." >&2
        exit 1
    fi
fi

candidates=$(mktemp)
trap 'rm -f "$candidates" 2>/dev/null || true; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue

    status=$(field "$f" status)
    status_rank=$(status_rank_for "$status" || true)
    [ -n "$status_rank" ] || continue

    current_assignee=$(normalize_assignee "$(field "$f" assignee)")
    case "$current_assignee" in
        ""|null|~) ;;
        *) continue ;;
    esac

    blockers=$(unresolved_blockers "$KANBAN_DIR" "$f" | xargs)
    [ -z "$blockers" ] || continue

    id=$(field "$f" id)
    [ -n "$id" ] || continue

    priority=$(field "$f" priority)
    priority_rank=1
    [ "$priority" = "High" ] && priority_rank=0

    printf '%s\t%s\t%s\t%s\n' "$status_rank" "$priority_rank" "$id" "$f" >> "$candidates"
done

if [ ! -s "$candidates" ]; then
    echo "NO CLAIMABLE CARD: no unassigned, unblocked cards found in: $FROM_STATUSES" >&2
    exit 1
fi

selected_line=$(sort -t $'\t' -k1,1n -k2,2n -k3,3n "$candidates" | head -n1)
IFS=$'\t' read -r _status_rank _priority_rank selected_id selected_file <<EOF_SELECTED
$selected_line
EOF_SELECTED

selected_status=$(field "$selected_file" status)
selected_title=$(title "$selected_file")
[ -n "$selected_title" ] || selected_title=$(basename "$selected_file" .md)

if [ "$DRY_RUN" -eq 1 ]; then
    echo "NEXT: #$selected_id $selected_title [$selected_status] -> $ASSIGNEE"
    echo "FILE: $selected_file"
    exit 0
fi

claim_card "$selected_file" "$selected_status"

echo "CLAIMED: #$selected_id $selected_title [$selected_status -> doing] by $ASSIGNEE"
echo "FILE: $selected_file"
