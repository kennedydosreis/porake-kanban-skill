#!/usr/bin/env bash
# Search kanban cards by tag.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

if [ $# -eq 1 ]; then
    KANBAN_DIR="."
    TAG="$1"
elif [ $# -ge 2 ]; then
    KANBAN_DIR="$1"
    TAG="$2"
else
    TAG=""
fi

if [ -z "$TAG" ]; then
    echo "Usage: $0 [kanban_dir] <tag>"
    echo "Example: $0 kanban/ ai-discoverability"
    exit 1
fi

echo "=== Cards tagged with: $TAG ==="
echo

for file in "$KANBAN_DIR"/*.md; do
    [ -f "$file" ] || continue
    match=false
    while IFS= read -r tag; do
        if [ "$tag" = "$TAG" ]; then
            match=true
            break
        fi
    done < <(list_values "$(field "$file" tags)")

    [ "$match" = true ] || continue

    id=$(field "$file" id)
    status=$(field "$file" status)
    title_text=$(title "$file")
    printf "#%-3s %-12s %s\n" "${id:-?}" "[$status]" "$title_text"
done
