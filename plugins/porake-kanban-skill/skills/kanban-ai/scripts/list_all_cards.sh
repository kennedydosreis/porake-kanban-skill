#!/usr/bin/env bash
# Export all kanban cards in pipe-delimited format.
# Output: id|status|blocked_by|title

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

KANBAN_DIR="${1:-.}"

for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue
    id=$(field "$f" id)
    status=$(field "$f" status)
    blocked=$(field "$f" blocked_by)
    title_text=$(title "$f")
    blocked=$(printf '%s\n' "$blocked" | tr -d '[]\r')
    echo "$id|$status|$blocked|$title_text"
done | sort -t '|' -k1,1n
