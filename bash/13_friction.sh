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

# --- validate project name ------------------------------------------
_friction_validate_project_name() {
    local name="$1"
    if [ -z "$name" ]; then
        echo "error: project name cannot be empty" >&2
        return 1
    fi
    if ! echo "$name" | grep -qP '^[a-z0-9_-]+$'; then
        echo "error: project name must match [a-z0-9_-], got: $name" >&2
        return 1
    fi
}

# --- check friction file has entries ---------------------------------
_friction_require_entries() {
    if [ ! -s "$MC_FRICTION_FILEPATH" ]; then
        echo "error: friction file is empty" >&2
        return 1
    fi
    if ! grep -q '^## ' "$MC_FRICTION_FILEPATH"; then
        echo "error: friction file has no entries (no ## headers)" >&2
        return 1
    fi
}

# --- check if friction file is open elsewhere ------------------------
_friction_check_lock() {
    local pid=""
    if command -v lsof >/dev/null 2>&1; then
        pid=$(lsof -t "$MC_FRICTION_FILEPATH" 2>/dev/null)
    elif command -v fuser >/dev/null 2>&1; then
        pid=$(fuser "$MC_FRICTION_FILEPATH" 2>/dev/null)
    fi
    if [ -n "$pid" ]; then
        echo "warning: FRICTION.md is open in another process (pid: $pid)" >&2
        echo "  proceed anyway? [y/N] " >&2
        read -r confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            return 1
        fi
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
    if [ -n "${1:-}" ]; then
        _friction_validate_project_name "$project" || return 1
    fi
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
        _friction_validate_project_name "$1" || return 1
        _friction_require_entries || return 1
        local output
        output=$(awk -v proj="project:$1" '
            /^## / { show = (index($0, proj) > 0) }
            show { print }
        ' "$MC_FRICTION_FILEPATH")
        if [ -z "$output" ]; then
            echo "no entries found for project:$1" >&2
            return 1
        fi
        echo "$output"
    fi
}

# --- fcount: friction summary per project ----------------------------
fcount() {
    _friction_require_entries || return 1
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
    _friction_require_entries || return 1
    local total
    total=$(grep -c '^## ' "$MC_FRICTION_FILEPATH" 2>/dev/null || true)
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
    _friction_validate_project_name "$1" || return 1
    _friction_require_entries || return 1
    _friction_require_script "mc_friction_archive.awk" || return 1
    _friction_check_lock || return 1

    local project="$1"

    # verify project has entries before invoking awk
    if ! grep -q "project:$project" "$MC_FRICTION_FILEPATH"; then
        echo "error: no entries found for project:$project" >&2
        return 1
    fi

    local archive_dir="$MC_FRICTION_ARCHIVE"
    local archive_file="$archive_dir/FRICTION_${project}_$(date +%Y-%m).md"
    local tmp_file="$MC_FRICTION_DIRECTORY/.friction_remaining.tmp"

    mkdir -p "$archive_dir"

    awk -v project="$project" -v archive_file="$archive_file" \
        -f "$MC_FRICTION_SCRIPTS/mc_friction_archive.awk" \
        "$MC_FRICTION_FILEPATH" > "$tmp_file"

    if [ $? -ne 0 ]; then
        echo "error: archive failed, friction file unchanged" >&2
        rm -f "$tmp_file"
        return 1
    fi

    # validate temp file before swap: either non-empty (remaining
    # entries exist) or empty (all entries were for this project)
    local original_count remaining_count
    original_count=$(grep -c '^## ' "$MC_FRICTION_FILEPATH" || true)
    remaining_count=$(grep -c '^## ' "$tmp_file" 2>/dev/null || true)
    local archived_count=$(( original_count - remaining_count ))

    if [ "$archived_count" -le 0 ]; then
        echo "error: archive produced no changes, friction file unchanged" >&2
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$MC_FRICTION_FILEPATH"
    echo "  archived $archived_count entries to $archive_file"
    echo "  remaining: $remaining_count entries"
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
            -o)
                if [ -z "${2:-}" ]; then
                    echo "error: -o requires a file path" >&2
                    return 1
                fi
                output="$2"
                local output_dir
                output_dir="$(dirname "$output")"
                if [ ! -d "$output_dir" ]; then
                    echo "error: output directory does not exist: $output_dir" >&2
                    return 1
                fi
                if [ ! -w "$output_dir" ]; then
                    echo "error: output directory is not writable: $output_dir" >&2
                    return 1
                fi
                shift 2
                ;;
            *)
                project="$1"
                _friction_validate_project_name "$project" || return 1
                shift
                ;;
        esac
    done

    _friction_require_entries || return 1

    if [ -z "$project" ]; then
        # full report on active file
        awk -f "$MC_FRICTION_SCRIPTS/mc_friction_generate_report.awk" \
            "$MC_FRICTION_FILEPATH" > "$output"
    else
        # combine active entries for project + archived entries
        input_file="$MC_FRICTION_DIRECTORY/.friction_report_input.tmp"
        ffriction "$project" > "$input_file" 2>/dev/null
        # append any archived files for this project
        cat "$MC_FRICTION_ARCHIVE"/FRICTION_"${project}"_*.md >> "$input_file" 2>/dev/null
        if [ ! -s "$input_file" ]; then
            echo "error: no entries found for project:$project (active or archived)" >&2
            rm -f "$input_file"
            return 1
        fi
        awk -f "$MC_FRICTION_SCRIPTS/mc_friction_generate_report.awk" \
            "$input_file" > "$output"
        rm -f "$input_file"
    fi
}
