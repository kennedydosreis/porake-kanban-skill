#!/usr/bin/env bash
# List all tags used in kanban cards with counts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

KANBAN_DIR="${1:-.}"

echo "=== Tag Usage ==="
echo

for f in "$KANBAN_DIR"/*.md; do
    [ -f "$f" ] || continue
    tags=$(field "$f" tags)
    [ -n "$tags" ] || continue
    list_values "$tags"
done | sort | uniq -c | sort -rn | awk '{printf "%3d  %s\n", $1, $2}'
