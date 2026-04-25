#!/usr/bin/env bash
# Auto-archive cards with status 'done' that haven't been modified in N days.
# Usage: bash auto_archive.sh <kanban_dir> [--days N] [--dry-run]
#
# Example: bash auto_archive.sh kanban/ --days 7
# Default: 3 days

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

KANBAN_DIR="${1:?Usage: $0 <kanban_dir> [--days N] [--dry-run]}"
DAYS=3
DRY_RUN=false

shift
while [ $# -gt 0 ]; do
    case "$1" in
        --days) DAYS="${2:?--days requires a number}"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

ARCHIVE_DIR="$KANBAN_DIR/archived"
THRESHOLD=$(days_ago_epoch "$DAYS")
ARCHIVED=0

for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue

    status=$(field "$f" status)
    [ "$status" = "done" ] || continue

    done_epoch=$(status_since_epoch "$f" done)
    [ -z "$done_epoch" ] && continue
    if [ "$done_epoch" -le "$THRESHOLD" ]; then
        id=$(field "$f" id)
        title=$(title "$f")
        fname=$(basename "$f")

        if [ "$DRY_RUN" = true ]; then
            echo "[DRY RUN] Would archive: #$id $title ($fname)"
        else
            mkdir -p "$ARCHIVE_DIR"
            mv "$f" "$ARCHIVE_DIR/$fname"
            echo "Archived: #$id $title -> archived/$fname"
        fi
        ARCHIVED=$((ARCHIVED + 1))
    fi
done

if [ "$ARCHIVED" -eq 0 ]; then
    echo "No cards eligible for archiving (done > $DAYS days)."
else
    [ "$DRY_RUN" = true ] && echo "($ARCHIVED cards would be archived)" || echo "($ARCHIVED cards archived)"
fi
