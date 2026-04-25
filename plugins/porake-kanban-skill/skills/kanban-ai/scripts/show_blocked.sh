#!/usr/bin/env bash
# Show cards that are currently blocked and their unresolved blockers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

KANBAN_DIR="${1:-.}"

echo "=== Blocked Cards ==="
echo

for file in "$KANBAN_DIR"/*.md; do
    [ -f "$file" ] || continue

    status=$(field "$file" status)
    case "$status" in
        done|archive)
            continue
            ;;
    esac

    blockers=$(unresolved_blockers "$KANBAN_DIR" "$file" | xargs)
    [ -n "$blockers" ] || continue

    id=$(field "$file" id)
    title_text=$(title "$file")

    printf "#%-3s %-12s %s\n" "${id:-?}" "[$status]" "$title_text"
    echo "  Blocked by: $blockers"
    echo
done
