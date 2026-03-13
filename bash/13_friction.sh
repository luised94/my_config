# Friction tracking: central file, project-tagged entries.
#
# Rationale for central over per-project:
#   - One file to review weekly. Cross-project patterns visible
#     without aggregation scripts.
#   - Filtering by project is a grep. Splitting by project later
#     is awk. Going the other direction (merging per-project files
#     into a central view) is harder and never stays in sync.
#   - Friction often spans projects ("the terminal_output copy
#     desync is now a problem in sm2 AND tui") - central file
#     captures that naturally.
#
# Entry format:
#   ## 2026-03-11 14:30  project:sm2
#   What I was trying to do.
#   What actually happened or what annoyed me.
#   ?: idea or fix if one comes to mind
#
# Project: auto-detected from git root dirname, overridable.
#
# Sync: local only for now. Dropbox or USB sync deferred.
MC_FRICTION_DIRECTORY="$HOME/friction"
MC_FRICTION_FILEPATH="$MC_FRICTION_DIRECTORY/FRICTION.md"
# --- ensure file and directory exist ---------------------------------
_friction_ensure_file() {
    if [ ! -d "$MC_FRICTION_DIRECTORY" ]; then
        mkdir -p "$MC_FRICTION_DIRECTORY"
    fi
    if [ ! -f "$MC_FRICTION_FILEPATH" ]; then
        touch "$MC_FRICTION_FILEPATH"
    fi
}
_friction_ensure_file
# --- project detection -----------------------------------------------
_friction_detect_project() {
    local git_root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [ $? -ne 0 ]; then
        echo "unknown"
        return
    fi
    basename "$git_root"
}
# --- flog: append entry and open -------------------------------------
flog() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        cat <<'EOF'
flog - append a friction entry to the central friction log
Usage:
  flog [project]
Arguments:
  project    (optional) Project name. Auto-detected from git root if omitted.
Side effects:
  Appends a timestamped, project-tagged stub to MC_FRICTION_FILEPATH.
  Opens MC_FRICTION_FILEPATH in $EDITOR at the last line.
EOF
        return 0
    fi
    local project="${1:-$(_friction_detect_project)}"
    local stub
    stub="$(printf '\n## %s  project:%s\nWhat I was trying to do.\nWhat actually happened or what annoyed me.\n?: idea or fix if one comes to mind\n' \
        "$(date '+%Y-%m-%d %H:%M')" \
        "$project")"
    echo "$stub" >> "$MC_FRICTION_FILEPATH"
    "${EDITOR:-nvim}" + "$MC_FRICTION_FILEPATH"
}
# --- ffriction: filter entries by project ----------------------------
ffriction() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        cat <<'EOF'
ffriction - show friction entries, optionally filtered by project
Usage:
  ffriction              show all entries
  ffriction sm2          show entries for project:sm2
EOF
        return 0
    fi
    if [ -z "$1" ]; then
        cat "$MC_FRICTION_FILEPATH"
    else
        awk -v proj="project:$1" '
            /^## / { show = (index($0, proj) > 0) }
            show { print }
        ' "$MC_FRICTION_FILEPATH"
    fi
}
# --- fcount: friction summary per project ----------------------------
fcount() {
    grep -oP 'project:\K\S+' "$MC_FRICTION_FILEPATH" | sort | uniq -c | sort -rn
}
