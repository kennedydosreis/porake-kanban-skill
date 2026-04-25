#!/usr/bin/env bash
# Create a new kanban card from a template.
# Usage: bash create_from_template.sh <kanban_dir> <template> <title> [assignee] [due_date]
#
# Templates: feature, bug, spike, chore
# Example:  bash create_from_template.sh kanban/ feature "Add OAuth support" "@claude" "2026-03-15"

set -euo pipefail

# Bash 5.2+ enables patsub_replacement by default, which makes '&' in the
# replacement side of ${var//pat/repl} expand to the matched text (sed-like).
# Disable it so titles containing '&' (e.g. "AT&T") stay literal.
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/card_utils.sh"

KANBAN_DIR="${1:?Usage: $0 <kanban_dir> <template> <title> [assignee] [due_date]}"
TEMPLATE="${2:?Specify template: feature, bug, spike, chore}"
TITLE="${3:?Specify card title}"
ASSIGNEE="${4:-}"
DUE_DATE="${5:-}"
TEMPLATE_FILE="$SCRIPT_DIR/templates/${TEMPLATE}.md"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template '$TEMPLATE' not found." >&2
    echo "Available templates:" >&2
    ls "$SCRIPT_DIR/templates/"*.md 2>/dev/null | xargs -I{} basename {} .md | sed 's/^/  /' >&2
    exit 1
fi

# Auto-increment ID: scan kanban/ and kanban/archived/
max_id=0
for dir in "$KANBAN_DIR" "$KANBAN_DIR/archived"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        fid=$(field "$f" id)
        [ -n "$fid" ] && [ "$fid" -gt "$max_id" ] 2>/dev/null && max_id="$fid"
    done
done
NEW_ID=$((max_id + 1))

# Generate kebab-case filename
filename=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
filepath="$KANBAN_DIR/${filename}.md"

# Prevent overwrite
if [ -f "$filepath" ]; then
    filepath="$KANBAN_DIR/${filename}-${NEW_ID}.md"
fi

mkdir -p "$KANBAN_DIR"

# Fill template using bash parameter expansion (literal substitution; no sed metachars risk)
content=$(cat "$TEMPLATE_FILE")
content=${content//__ID__/$NEW_ID}
content=${content//__TITLE__/$TITLE}
content=${content//__ASSIGNEE__/$ASSIGNEE}
content=${content//__DUE_DATE__/${DUE_DATE:-}}
printf '%s\n' "$content" > "$filepath"

echo "Created card #$NEW_ID: $filepath (template: $TEMPLATE)"
