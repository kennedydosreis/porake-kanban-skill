#!/usr/bin/env bash
# Multi-agent code analysis orchestrator.
# Runs: profile -> decompose -> execute specialists -> synthesize action board.
#
# Usage: bash analyze.sh <repo_path> [--kanban-dir DIR] [--action-dir DIR] [--skip-profile]
#
# Requires: claude CLI (Claude Code) installed and authenticated.

set -euo pipefail

# --- Defaults ---
REPO=""
KANBAN_DIR="kanban/analysis"
ACTION_DIR="kanban/actions"
SKIP_PROFILE=false
DRY_RUN=false

# --- Parse args ---
while [ $# -gt 0 ]; do
    case "$1" in
        --kanban-dir) KANBAN_DIR="$2"; shift 2 ;;
        --action-dir) ACTION_DIR="$2"; shift 2 ;;
        --skip-profile) SKIP_PROFILE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            sed -n '/^# / { s/^# \?//; p; }' "$0" | head -15
            exit 0 ;;
        *) [ -z "$REPO" ] && REPO="$1" || { echo "Unknown arg: $1" >&2; exit 1; }; shift ;;
    esac
done

[ -z "$REPO" ] && { echo "Error: repo_path required" >&2; echo "Usage: $0 <repo_path>" >&2; exit 1; }
[ ! -d "$REPO" ] && { echo "Error: '$REPO' is not a directory" >&2; exit 1; }

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KANBAN_SCRIPTS="$(cd "$SCRIPT_DIR/../scripts" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
SPECIALISTS_DIR="$SCRIPT_DIR/specialists"
PROFILE_PATH="$KANBAN_DIR/.project-profile.md"

. "$KANBAN_SCRIPTS/card_utils.sh"

# --- Pre-flight ---
if ! command -v claude >/dev/null 2>&1; then
    echo "Error: 'claude' CLI not found. Install Claude Code first." >&2
    exit 1
fi

mkdir -p "$KANBAN_DIR" "$ACTION_DIR"

# --- Helper: render a prompt template with variable substitution ---
render_prompt() {
    local template="$1"
    sed \
        -e "s|{{PROFILE_PATH}}|$PROFILE_PATH|g" \
        -e "s|{{SPECIALISTS_DIR}}|$SPECIALISTS_DIR|g" \
        -e "s|{{KANBAN_DIR}}|$KANBAN_DIR|g" \
        -e "s|{{ACTION_DIR}}|$ACTION_DIR|g" \
        -e "s|{{SCRIPTS_DIR}}|$KANBAN_SCRIPTS|g" \
        "$template"
}

# --- Helper: call Claude with a prompt, returning output ---
call_claude() {
    local prompt="$1"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would call: claude -p"
        echo "--- PROMPT ---"
        echo "$prompt" | head -20
        echo "... (truncated)"
        echo "--------------"
        return 0
    fi
    # Non-interactive mode. Allow all standard tools so Claude can read files and run scripts.
    claude -p "$prompt"
}

# =============================================================================
# PHASE 1: Profile
# =============================================================================
echo "=== PHASE 1: Profiling repository ==="
if [ "$SKIP_PROFILE" = true ] && [ -f "$PROFILE_PATH" ]; then
    echo "Skipping profile (using existing: $PROFILE_PATH)"
else
    bash "$SCRIPT_DIR/profiler.sh" "$REPO" "$PROFILE_PATH"
fi
echo

# =============================================================================
# PHASE 2: Decompose
# =============================================================================
echo "=== PHASE 2: Decomposing into analysis cards ==="

# Only decompose if no analysis cards exist yet (idempotency)
existing_cards=$(find "$KANBAN_DIR" -maxdepth 1 -name '*.md' ! -name '.project-profile.md' 2>/dev/null | wc -l)
if [ "$existing_cards" -gt 0 ]; then
    echo "Analysis cards already exist ($existing_cards found). Skipping decomposition."
    echo "To re-decompose, clear $KANBAN_DIR/ first."
else
    decomposer_prompt=$(render_prompt "$PROMPTS_DIR/decomposer.md")
    # Prepend the repo context
    full_prompt="You are analyzing the repository at: $REPO
Change to that directory before using bash tools for repo inspection.

$decomposer_prompt"
    call_claude "$full_prompt"
fi
echo

# =============================================================================
# PHASE 3: Execute specialists
# =============================================================================
echo "=== PHASE 3: Executing specialists ==="

# Loop: find cards in todo with no unresolved blockers, process one at a time
iteration=0
max_iterations=50
while [ "$iteration" -lt "$max_iterations" ]; do
    iteration=$((iteration + 1))

    # Find next eligible card
    next_card=""
    for f in "$KANBAN_DIR"/*.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = ".project-profile.md" ] && continue

        status=$(field "$f" status)
        [ "$status" = "todo" ] || continue

        # Check blockers
        blocked_raw=$(field "$f" blocked_by)
        all_resolved=true
        while IFS= read -r bid; do
            for bf in "$KANBAN_DIR"/*.md; do
                [ -f "$bf" ] || continue
                bfid=$(field "$bf" id)
                if [ "$bfid" = "$bid" ]; then
                    bstatus=$(field "$bf" status)
                    [ "$bstatus" = "done" ] || all_resolved=false
                fi
            done
        done < <(list_values "$blocked_raw")

        if [ "$all_resolved" = true ]; then
            next_card="$f"
            break
        fi
    done

    if [ -z "$next_card" ]; then
        # Check if everything is done
        todo_count=0
        for f in "$KANBAN_DIR"/*.md; do
            [ -f "$f" ] || continue
            [ "$(basename "$f")" = ".project-profile.md" ] && continue
            s=$(field "$f" status)
            [ "$s" = "todo" ] && todo_count=$((todo_count + 1))
        done
        if [ "$todo_count" -gt 0 ]; then
            echo "WARNING: $todo_count cards still in 'todo' but all blocked. Possible cycle." >&2
        else
            echo "All cards processed."
        fi
        break
    fi

    card_id=$(field "$next_card" id)
    specialist=$(field "$next_card" specialist)
    # Fall back to assignee if no specialist field
    [ -z "$specialist" ] && specialist=$(field "$next_card" assignee | tr -d '"@')

    specialist_def="$SPECIALISTS_DIR/${specialist}.md"
    if [ ! -f "$specialist_def" ]; then
        echo "WARNING: No specialist definition for '$specialist' (card #$card_id). Using generic role."
        specialist_def="$SPECIALISTS_DIR/architect.md"  # fallback
    fi

    echo "--- Working card #$card_id (specialist: $specialist) ---"

    # Mark card as 'doing' to avoid double-processing on resume
    bash "$KANBAN_SCRIPTS/transition.sh" "$KANBAN_DIR" "$card_id" doing || {
        echo "Failed to transition card #$card_id to doing. Skipping." >&2
        continue
    }

    specialist_prompt=$(render_prompt "$PROMPTS_DIR/specialist.md" | \
        sed \
            -e "s|{{SPECIALIST_NAME}}|$specialist|g" \
            -e "s|{{SPECIALIST_DEFINITION}}|$specialist_def|g" \
            -e "s|{{CARD_PATH}}|$next_card|g" \
            -e "s|{{CARD_ID}}|$card_id|g")

    full_prompt="You are analyzing the repository at: $REPO
Change to that directory before using bash tools for repo inspection.

$specialist_prompt"
    call_claude "$full_prompt" || {
        echo "Specialist failed on card #$card_id. Card remains in 'doing' state." >&2
        # Continue to next iteration; operator can resume
    }

    # Verify the specialist actually advanced the card. If it's still 'doing',
    # the specialist likely forgot to run transition.sh. Flag it so the loop
    # doesn't silently exit with work unfinished.
    post_status=$(field "$next_card" status)
    if [ "$post_status" = "doing" ]; then
        echo "WARNING: Card #$card_id still in 'doing' after specialist run." >&2
        echo "  Inspect $next_card and transition manually, or re-run analyze.sh." >&2
    fi
done

echo

# =============================================================================
# PHASE 4: Synthesize
# =============================================================================
echo "=== PHASE 4: Synthesizing action board ==="

synthesizer_prompt=$(render_prompt "$PROMPTS_DIR/synthesizer.md")
full_prompt="You are analyzing the repository at: $REPO.
Read the analysis cards in $KANBAN_DIR and write outputs to $ACTION_DIR.

$synthesizer_prompt"
call_claude "$full_prompt"

echo
echo "=== DONE ==="
echo "Analysis cards:  $KANBAN_DIR/"
echo "Action board:    $ACTION_DIR/"
echo "Executive summary: $ACTION_DIR/ARCHITECTURE-REVIEW.md"
