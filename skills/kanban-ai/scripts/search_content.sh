#!/usr/bin/env bash
# Search kanban card content (case-insensitive, literal match).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

if [ $# -eq 1 ]; then
    KANBAN_DIR="."
    SEARCH_TERM="$1"
elif [ $# -ge 2 ]; then
    KANBAN_DIR="$1"
    shift
    SEARCH_TERM="$*"
else
    SEARCH_TERM=""
fi

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: $0 [kanban_dir] <search_term>"
    echo "Example: $0 kanban/ 'temporal signals'"
    exit 1
fi

echo "=== Cards matching: $SEARCH_TERM ==="
echo

for file in "$KANBAN_DIR"/*.md; do
    [ -f "$file" ] || continue
    grep -F -i -q "$SEARCH_TERM" "$file" || continue

    id=$(field "$file" id)
    status=$(field "$file" status)
    title_text=$(title "$file")

    printf "#%-3s %-12s %s\n" "${id:-?}" "[$status]" "$title_text"

    echo "  Matches:"
    grep -F -i -n -C1 "$SEARCH_TERM" "$file" | head -10 | sed 's/^/    /'
    echo
done
