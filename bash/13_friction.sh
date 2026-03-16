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
MC_FRICTION_ARCHIVE="$MC_FRICTION_DIRECTORY/archive"
MC_FRICTION_SCRIPTS="$MC_ROOT/scripts"

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

# --- check awk script exists ----------------------------------------
_friction_require_script() {
    local script="$MC_FRICTION_SCRIPTS/$1"
    if [ ! -f "$script" ]; then
        echo "error: missing $script" >&2
        return 1
    fi
}

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
    if [ -z "${1:-}" ]; then
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

# --- fbacklog: count remaining entries with total --------------------
fbacklog() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        cat <<'EOF'
fbacklog - show unaddressed friction entry counts by project
Usage:
  fbacklog
EOF
        return 0
    fi
    local total
    total=$(grep -c '^## ' "$MC_FRICTION_FILEPATH" 2>/dev/null || true)
    if [ "$total" = "0" ] || [ -z "$total" ]; then
        echo "  no open friction entries"
        return 0
    fi
    echo "  by project:"
    grep -oP 'project:\K\S+' "$MC_FRICTION_FILEPATH" | sort | uniq -c | sort -rn | sed 's/^/    /'
    echo "  total: $total"
}

# --- farchive: archive a project's entries ---------------------------
farchive() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        cat <<'EOF'
farchive - archive friction entries for a project
Usage:
  farchive <project>
Arguments:
  project    Project name to archive (e.g. kbd, sm2).
Side effects:
  Moves matching entries from FRICTION.md to archive/FRICTION_{project}_{YYYY-MM}.md.
  Rewrites FRICTION.md with remaining entries.
EOF
        return 0
    fi
    if [ -z "${1:-}" ]; then
        echo "usage: farchive <project>" >&2
        return 1
    fi
    _friction_require_script "mc_friction_archive.awk" || return 1

    local project="$1"
    local archive_dir="$MC_FRICTION_ARCHIVE"
    local archive_file="$archive_dir/FRICTION_${project}_$(date +%Y-%m).md"
    local tmp_file="$MC_FRICTION_DIRECTORY/.friction_remaining.tmp"

    mkdir -p "$archive_dir"

    awk -v project="$project" -v archive_file="$archive_file" \
        -f "$MC_FRICTION_SCRIPTS/mc_friction_archive.awk" \
        "$MC_FRICTION_FILEPATH" > "$tmp_file"

    # only overwrite if awk succeeded
    if [ $? -eq 0 ]; then
        mv "$tmp_file" "$MC_FRICTION_FILEPATH"
    else
        echo "error: archive failed, friction file unchanged" >&2
        rm -f "$tmp_file"
        return 1
    fi
}

# --- freport: generate friction report -------------------------------
freport() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        cat <<'EOF'
freport - generate a friction report
Usage:
  freport              report on active friction file
  freport <project>    report on active + archived entries for project
  freport -o <file>    write report to file instead of stdout
EOF
        return 0
    fi
    _friction_require_script "mc_friction_generate_report.awk" || return 1

    local output="/dev/stdout"
    local project=""
    local input_file=""

    # parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -o) output="$2"; shift 2 ;;
            *)  project="$1"; shift ;;
        esac
    done

    if [ -z "$project" ]; then
        # full report on active file
        awk -f "$MC_FRICTION_SCRIPTS/mc_friction_generate_report.awk" \
            "$MC_FRICTION_FILEPATH" > "$output"
    else
        # combine active entries for project + archived entries
        input_file="$MC_FRICTION_DIRECTORY/.friction_report_input.tmp"
        ffriction "$project" > "$input_file"
        # append any archived files for this project
        cat "$MC_FRICTION_ARCHIVE"/FRICTION_"${project}"_*.md >> "$input_file" 2>/dev/null
        awk -f "$MC_FRICTION_SCRIPTS/mc_friction_generate_report.awk" \
            "$input_file" > "$output"
        rm -f "$input_file"
    fi
}
