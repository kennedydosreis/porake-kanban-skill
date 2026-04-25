#!/usr/bin/env bash
# Generate a daily standup summary from the kanban board.
# Shows: what's in progress, what's blocked, what was recently done, what's next.
# Usage: bash standup.sh <kanban_dir> [--days N]
#
# --days N: consider cards modified in the last N days as "recently done" (default: 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

KANBAN_DIR="${1:?Usage: $0 <kanban_dir> [--days N]}"
DAYS=1

shift
while [ $# -gt 0 ]; do
    case "$1" in
        --days) DAYS="${2:?--days requires a number}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

TODAY=$(date +%Y-%m-%d)
THRESHOLD=$(days_ago_epoch "$DAYS")

echo "=== STANDUP $TODAY ==="
echo

# In Progress
echo "IN PROGRESS:"
found=false
for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue
    s=$(field "$f" status)
    [ "$s" = "doing" ] || continue
    id=$(field "$f" id); t=$(title "$f"); a=$(trim_quotes "$(field "$f" assignee)"); p=$(field "$f" priority)
    line="  #$id $t"
    [ -n "$a" ] && line="$line ($a)"
    [ "$p" = "High" ] && line="$line [HIGH]"
    echo "$line"
    found=true
done
$found || echo "  (nothing in progress)"
echo

# In Review
echo "IN REVIEW:"
found=false
for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue
    s=$(field "$f" status)
    [ "$s" = "review" ] || continue
    id=$(field "$f" id); t=$(title "$f"); a=$(trim_quotes "$(field "$f" assignee)"); p=$(field "$f" priority)
    line="  #$id $t"
    [ -n "$a" ] && line="$line (review: $a)"
    [ "$p" = "High" ] && line="$line [HIGH]"
    echo "$line"
    found=true
done
$found || echo "  (nothing in review)"
echo

# Blocked
echo "BLOCKED:"
found=false
for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue
    s=$(field "$f" status)
    case "$s" in
        done|archive)
            continue
            ;;
    esac
    blockers=$(unresolved_blockers "$KANBAN_DIR" "$f" | xargs)
    [ -n "$blockers" ] || continue
    id=$(field "$f" id); t=$(title "$f")
    echo "  #$id $t  [blocked by: $blockers]"
    found=true
done
$found || echo "  (nothing blocked)"
echo

# Recently Done
echo "RECENTLY DONE:"
found=false
for dir in "$KANBAN_DIR" "$KANBAN_DIR/archived"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        s=$(field "$f" status)
        [ "$s" = "done" ] || continue
        done_since=$(status_since_epoch "$f" done)
        if [ "$done_since" -ge "$THRESHOLD" ]; then
            id=$(field "$f" id); t=$(title "$f"); a=$(trim_quotes "$(field "$f" assignee)")
            line="  #$id $t"
            [ -n "$a" ] && line="$line ($a)"
            echo "$line"
            found=true
        fi
    done
done
$found || echo "  (nothing completed recently)"
echo

# Up Next (highest priority todo cards)
echo "UP NEXT (todo):"
todo_rows=$(
    for f in "$KANBAN_DIR"/*.md; do
        [ -f "$f" ] || continue
        s=$(field "$f" status)
        [ "$s" = "todo" ] || continue
        id=$(field "$f" id); t=$(title "$f"); p=$(field "$f" priority)
        is_blocked="no"
        blockers=$(unresolved_blockers "$KANBAN_DIR" "$f" | xargs)
        [ -n "$blockers" ] && is_blocked="yes"
        # Sort: High first (0), then Normal (1); unblocked first
        sort_key="1"
        [ "$p" = "High" ] && sort_key="0"
        [ "$is_blocked" = "yes" ] && sort_key="${sort_key}1" || sort_key="${sort_key}0"
        echo "${sort_key}|#${id} ${t}|${p}|${is_blocked}"
    done | sort | head -5
)

if [ -z "$todo_rows" ]; then
    echo "  (backlog is empty)"
else
    printf '%s\n' "$todo_rows" | while IFS='|' read -r _ card prio blocked; do
        line="  $card"
        [ "$prio" = "High" ] && line="$line [HIGH]"
        [ "$blocked" = "yes" ] && line="$line [BLOCKED]"
        echo "$line"
    done
fi
echo

# Summary counts
echo "--- BOARD SUMMARY ---"
for col in backlog todo doing review done; do
    count=0
    for f in "$KANBAN_DIR"/*.md; do
        [ -f "$f" ] || continue
        s=$(field "$f" status)
        [ "$s" = "$col" ] && count=$((count + 1))
    done
    printf "  %-10s %d\n" "$col" "$count"
done
archived=0
[ -d "$KANBAN_DIR/archived" ] && archived=$(find "$KANBAN_DIR/archived" -maxdepth 1 -name '*.md' | wc -l)
printf "  %-10s %d\n" "archived" "$archived"
