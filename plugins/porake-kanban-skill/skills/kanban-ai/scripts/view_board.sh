#!/usr/bin/env bash
# Display kanban cards grouped by status.
# Usage: bash view_board.sh [kanban-directory]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

KANBAN_DIR="${1:-kanban}"

if [ ! -d "$KANBAN_DIR" ]; then
    echo "Error: '$KANBAN_DIR' not found." >&2
    exit 1
fi

backlog_col=""
todo_col=""
doing_col=""
review_col=""
done_col=""
archive_col=""

for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue

    id=$(field "$f" id)
    status=$(field "$f" status)
    priority=$(field "$f" priority)
    blockers=$(unresolved_blockers "$KANBAN_DIR" "$f" | xargs)
    t=$(title "$f")
    [ -z "$t" ] && t=$(basename "$f" .md)

    line="  #${id} ${t}"
    [ "$priority" = "High" ] && line="$line [HIGH]"
    [ -n "$blockers" ] && line="$line [blocked: $blockers]"

    case "$status" in
        backlog) backlog_col+="$line"$'\n' ;;
        todo) todo_col+="$line"$'\n' ;;
        doing) doing_col+="$line"$'\n' ;;
        review) review_col+="$line"$'\n' ;;
        done) done_col+="$line"$'\n' ;;
        archive) archive_col+="$line"$'\n' ;;
    esac
done

for status in backlog todo doing review done archive; do
    printf "=== %-8s ===\n" "$(echo "$status" | tr '[:lower:]' '[:upper:]')"
    case "$status" in
        backlog) output="$backlog_col" ;;
        todo) output="$todo_col" ;;
        doing) output="$doing_col" ;;
        review) output="$review_col" ;;
        done) output="$done_col" ;;
        archive) output="$archive_col" ;;
    esac

    if [ -z "$output" ]; then
        echo "  (empty)"
    else
        printf "%s" "$output"
    fi
    echo
done
