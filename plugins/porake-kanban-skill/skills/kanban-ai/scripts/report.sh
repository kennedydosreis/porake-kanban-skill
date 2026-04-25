#!/usr/bin/env bash
# Generate board metrics report.
# Shows: card distribution, priority breakdown, aging cards, overdue cards, throughput.
# Usage: bash report.sh <kanban_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

KANBAN_DIR="${1:?Usage: $0 <kanban_dir>}"

TODAY=$(date +%Y-%m-%d)
TODAY_EPOCH=$(date +%s)

echo "=== KANBAN REPORT — $TODAY ==="
echo

# --- Distribution ---
echo "CARD DISTRIBUTION:"
total=0
for col in backlog todo doing review done; do
    count=0
    for f in "$KANBAN_DIR"/*.md; do
        [ -f "$f" ] || continue
        s=$(field "$f" status)
        [ "$s" = "$col" ] && count=$((count + 1))
    done
    total=$((total + count))
    bar=""
    if [ "$count" -gt 0 ]; then
        bar=$(printf '%0.s█' $(seq 1 "$count") 2>/dev/null || true)
    fi
    printf "  %-10s %2d  %s\n" "$col" "$count" "$bar"
done
archived=0
[ -d "$KANBAN_DIR/archived" ] && archived=$(find "$KANBAN_DIR/archived" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
printf "  %-10s %2d\n" "archived" "$archived"
echo "  Total active: $total"
echo

# --- Priority Breakdown ---
echo "PRIORITY BREAKDOWN:"
high=0; normal=0
for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue
    s=$(field "$f" status)
    case "$s" in
        done|archive)
            continue
            ;;
    esac
    p=$(field "$f" priority)
    if [ "$p" = "High" ]; then
        high=$((high + 1))
    else
        normal=$((normal + 1))
    fi
done
echo "  High:   $high"
echo "  Normal: $normal"
echo

# --- Overdue Cards ---
echo "OVERDUE CARDS:"
found=false
for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue
    s=$(field "$f" status)
    case "$s" in
        done|archive)
            continue
            ;;
    esac
    due=$(field "$f" due_date)
    [ -z "$due" ] && continue
    due_epoch=$(date_to_epoch "$due")
    if [ "$due_epoch" -gt 0 ] && [ "$due_epoch" -lt "$TODAY_EPOCH" ]; then
        id=$(field "$f" id); t=$(title "$f")
        days_over=$(( (TODAY_EPOCH - due_epoch) / 86400 ))
        echo "  #$id $t  (due: $due, ${days_over}d overdue)"
        found=true
    fi
done
$found || echo "  (none)"
echo

# --- Aging Cards (in 'doing' for more than 7 days) ---
echo "AGING CARDS (doing > 7 days):"
found=false
for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue
    s=$(field "$f" status)
    [ "$s" = "doing" ] || continue
    doing_since=$(status_since_epoch "$f" doing)
    age_days=$(( (TODAY_EPOCH - doing_since) / 86400 ))
    if [ "$age_days" -gt 7 ]; then
        id=$(field "$f" id); t=$(title "$f")
        echo "  #$id $t  (${age_days} days in doing)"
        found=true
    fi
done
$found || echo "  (none)"
echo

# --- Throughput (done in last 7 / 30 days) ---
echo "THROUGHPUT:"
WEEK_AGO=$(days_ago_epoch 7)
MONTH_AGO=$(days_ago_epoch 30)
done_7=0; done_30=0
for dir in "$KANBAN_DIR" "$KANBAN_DIR/archived"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        s=$(field "$f" status)
        [ "$s" = "done" ] || continue
        done_since=$(status_since_epoch "$f" done)
        [ "$done_since" -ge "$WEEK_AGO" ] && done_7=$((done_7 + 1))
        [ "$done_since" -ge "$MONTH_AGO" ] && done_30=$((done_30 + 1))
    done
done
echo "  Last 7 days:  $done_7 cards"
echo "  Last 30 days: $done_30 cards"

# --- Blocked chain detection ---
echo
echo "DEPENDENCY CHAINS:"
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
    echo "  #$id $t  <- blocked by $blockers"
    found=true
done
$found || echo "  (no active dependencies)"
