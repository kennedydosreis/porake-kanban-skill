#!/usr/bin/env bash
# Scan a repository and produce a project profile.
# Output: markdown file with languages, frameworks, size, structure, and signals.
# Usage: bash profiler.sh <repo_path> <output_file>
#
# Example: bash profiler.sh ~/projects/myapp kanban/.project-profile.md

set -euo pipefail

REPO="${1:?Usage: $0 <repo_path> <output_file>}"
OUTPUT="${2:?Specify output file path}"

if [ ! -d "$REPO" ]; then
    echo "Error: '$REPO' is not a directory." >&2
    exit 1
fi

cd "$REPO"

# --- Languages: count files by extension, top 10 ---
languages=$(find . -type f \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/venv/*' \
    -not -path '*/.venv/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/target/*' \
    -not -path '*/__pycache__/*' \
    2>/dev/null | \
    sed -n 's/.*\.\([a-zA-Z0-9]\{1,10\}\)$/\1/p' | \
    sort | uniq -c | sort -rn | head -10)

# --- Total file count and rough size ---
total_files=$(find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | wc -l)
repo_size=$(du -sh . 2>/dev/null | awk '{print $1}')

# --- Package managers detected ---
pkg_managers=""
[ -f "package.json" ] && pkg_managers="$pkg_managers npm/node"
[ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ] && pkg_managers="$pkg_managers python/pip"
[ -f "Cargo.toml" ] && pkg_managers="$pkg_managers rust/cargo"
[ -f "go.mod" ] && pkg_managers="$pkg_managers go/modules"
[ -f "pom.xml" ] && pkg_managers="$pkg_managers java/maven"
[ -f "build.gradle" ] || [ -f "build.gradle.kts" ] && pkg_managers="$pkg_managers java/gradle"
[ -f "Gemfile" ] && pkg_managers="$pkg_managers ruby/bundler"
[ -f "composer.json" ] && pkg_managers="$pkg_managers php/composer"
[ -f "mix.exs" ] && pkg_managers="$pkg_managers elixir/mix"

# --- Framework signals (grep'd from deps) ---
frameworks=""
if [ -f "package.json" ]; then
    for fw in react vue svelte next nuxt angular express fastify nestjs; do
        grep -q "\"$fw\"" package.json 2>/dev/null && frameworks="$frameworks $fw"
    done
fi
for pyfile in requirements.txt pyproject.toml setup.py Pipfile; do
    [ -f "$pyfile" ] || continue
    for fw in django fastapi flask pyramid tornado starlette; do
        grep -qi "^$fw\|$fw==\|$fw>=\|$fw = \|\"$fw\"" "$pyfile" 2>/dev/null && frameworks="$frameworks $fw"
    done
done

# --- AI/ML signals ---
ai_signals=""
for pyfile in requirements.txt pyproject.toml setup.py Pipfile; do
    [ -f "$pyfile" ] || continue
    for lib in torch tensorflow transformers langchain openai anthropic llama scikit-learn pandas numpy; do
        grep -qi "^$lib\|$lib==\|$lib>=\|$lib = \|\"$lib\"" "$pyfile" 2>/dev/null && ai_signals="$ai_signals $lib"
    done
done
notebook_count=$(find . -name '*.ipynb' -not -path '*/.git/*' 2>/dev/null | wc -l)
[ "$notebook_count" -gt 0 ] && ai_signals="$ai_signals jupyter($notebook_count)"

# --- CI/CD signals ---
ci_signals=""
[ -d ".github/workflows" ] && ci_signals="$ci_signals github-actions($(find .github/workflows -name '*.yml' -o -name '*.yaml' 2>/dev/null | wc -l))"
[ -f ".gitlab-ci.yml" ] && ci_signals="$ci_signals gitlab-ci"
[ -f "Jenkinsfile" ] && ci_signals="$ci_signals jenkins"
[ -f ".circleci/config.yml" ] && ci_signals="$ci_signals circle-ci"

# --- Test presence ---
test_signals=""
test_dirs=$(find . -maxdepth 3 -type d \( -name 'test' -o -name 'tests' -o -name '__tests__' -o -name 'spec' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)
[ -n "$test_dirs" ] && test_signals="yes (dirs: $(echo "$test_dirs" | tr '\n' ' '))"
[ -z "$test_signals" ] && test_signals="no test directories found"

# --- Top-level structure ---
top_dirs=$(find . -maxdepth 1 -type d -not -name '.' -not -name '.git' -not -name 'node_modules' -not -name 'venv' -not -name '.venv' 2>/dev/null | sed 's|^\./||' | sort)

# --- Documentation ---
doc_signals=""
[ -f "README.md" ] || [ -f "README.rst" ] || [ -f "README" ] && doc_signals="$doc_signals README"
[ -d "docs" ] || [ -d "doc" ] && doc_signals="$doc_signals docs/"
[ -f "CONTRIBUTING.md" ] && doc_signals="$doc_signals CONTRIBUTING"
[ -f "ARCHITECTURE.md" ] && doc_signals="$doc_signals ARCHITECTURE"

# --- Git activity (last 90 days) ---
git_activity="n/a"
if [ -d ".git" ]; then
    commits_90d=$(git log --since="90 days ago" --oneline 2>/dev/null | wc -l)
    contributors=$(git log --since="90 days ago" --format='%ae' 2>/dev/null | sort -u | wc -l)
    git_activity="$commits_90d commits, $contributors contributors (last 90d)"
fi

# --- Write output ---
mkdir -p "$(dirname "$OUTPUT")"

{
    echo "# Project Profile"
    echo
    echo "Generated: $(date +%Y-%m-%d)"
    echo "Path: $REPO"
    echo
    echo "## Size"
    echo "- Total files: $total_files"
    echo "- Repo size: $repo_size"
    echo "- Git activity: $git_activity"
    echo
    echo "## Top File Types"
    echo '```'
    echo "$languages"
    echo '```'
    echo
    echo "## Package Managers"
    echo "-${pkg_managers:- none detected}"
    echo
    echo "## Frameworks Detected"
    echo "-${frameworks:- none detected}"
    echo
    echo "## AI/ML Signals"
    echo "-${ai_signals:- none detected}"
    echo
    echo "## CI/CD"
    echo "-${ci_signals:- none detected}"
    echo
    echo "## Tests"
    echo "- $test_signals"
    echo
    echo "## Documentation"
    echo "-${doc_signals:- minimal}"
    echo
    echo "## Top-Level Structure"
    echo '```'
    echo "$top_dirs"
    echo '```'
} > "$OUTPUT"

echo "Profile written to: $OUTPUT"
