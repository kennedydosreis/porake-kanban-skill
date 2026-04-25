#!/usr/bin/env bash
# Shared helpers for parsing kanban card files.

field() {
    awk -v f="$2" '
        { sub(/\r$/, "") }
        /^---$/ { fm++; next }
        fm == 1 && index($0, f ":") == 1 {
            sub("^" f ":[ \t]*", "")
            print
            exit
        }
    ' "$1"
}

title() {
    awk '
        { sub(/\r$/, "") }
        /^---$/ { fm++; next }
        fm == 2 && /^# / {
            sub("^# ", "")
            print
            exit
        }
    ' "$1"
}

trim_quotes() {
    local value="${1-}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s\n' "$value"
}

list_values() {
    local raw="${1-}"
    printf '%s\n' "$raw" \
        | tr -d '[]\r' \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | awk 'NF'
}

file_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo "0"
}

date_to_epoch() {
    date -d "$1" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || true
}

days_ago_epoch() {
    date -d "$1 days ago" +%s 2>/dev/null || date -v-"${1}"d +%s 2>/dev/null || echo "0"
}

status_since_epoch() {
    local file="$1"
    local target_status="$2"
    local last_date

    last_date=$(
        awk -v target="$target_status" '
            BEGIN { quote = sprintf("%c", 39) }
            {
                sub(/\r$/, "")
                if (index($0, "to " quote target quote) > 0 &&
                    match($0, /^- [0-9]{4}-[0-9]{2}-[0-9]{2}:/)) {
                    print substr($0, 3, 10)
                }
            }
        ' "$file" | tail -n1
    )

    if [ -n "$last_date" ]; then
        date_to_epoch "$last_date"
    else
        file_mtime "$file"
    fi
}

find_card_file_by_id() {
    local kanban_dir="$1"
    local card_id="$2"
    local dir
    local file
    local file_id

    for dir in "$kanban_dir" "$kanban_dir/archived"; do
        [ -d "$dir" ] || continue
        for file in "$dir"/*.md; do
            [ -f "$file" ] || continue
            file_id=$(field "$file" id)
            if [ "$file_id" = "$card_id" ]; then
                printf '%s\n' "$file"
                return 0
            fi
        done
    done

    return 1
}

unresolved_blockers() {
    local kanban_dir="$1"
    local file="$2"
    local blocker_id
    local blocker_file
    local blocker_status

    while IFS= read -r blocker_id; do
        [ -n "$blocker_id" ] || continue
        blocker_file=$(find_card_file_by_id "$kanban_dir" "$blocker_id" || true)
        if [ -z "$blocker_file" ]; then
            printf '#%s(missing)\n' "$blocker_id"
            continue
        fi

        blocker_status=$(field "$blocker_file" status)
        case "$blocker_status" in
            done|archive)
                ;;
            *)
                printf '#%s(%s)\n' "$blocker_id" "${blocker_status:-unknown}"
                ;;
        esac
    done < <(list_values "$(field "$file" blocked_by)")
}
