#!/usr/bin/env bash
# 13_friction.sh -- friction tracking: rapid-capture inbox with project tagging.
# Source this file. Do not execute directly.
# Loaded by bash/ startup chain after 06_usb.sh.
#
# --- data model ---
#
# FRICTION.md is a working inbox. Entries are logged via friction_log,
# reviewed via friction_show, and removed via friction_archive.
# Archiving is the only status transition. The archive directory
# is the outbox (graveyard). There is no "resolved" or "in progress"
# state. Entries have no unique ID; identity is the full line content.
#
# Entry format (one per line):
#   @@ 2026-03-11 14:30 project:sm2 | description text here
#
# Fields:
#   @@              entry marker (literal)
#   YYYY-MM-DD      date, auto-generated
#   HH:MM           time, auto-generated
#   project:name    project tag (auto-detected from git root or explicit)
#   |               separator (literal)
#   text            free-form description, single line
#
# Non-entry lines (lines not starting with @@) are preserved by all
# operations. They serve as optional note space. Indented lines after
# an @@ entry are loosely associated with that entry and travel with
# it during archive. They are not parsed.
#
# --- project naming convention ---
#
# Projects use hierarchical names: domain-subtopic, hyphen-separated.
# Examples:
#   friction              bare domain (the friction tool itself)
#   friction-archive      subtopic under friction
#   friction-show         subtopic under friction
#   my_config-zotero      subtopic under my_config
#   llms-prompts          subtopic under llms
#
# The domain is the first segment before the first hyphen.
# If no hyphen, the project name IS the domain.
#
# --- matching behavior ---
#
# friction_show uses PREFIX matching by default:
#   fshow friction        matches friction, friction-archive, friction-show
#   fshow friction-show   matches friction-show only (no further subtopics)
#   fshow --exact friction  matches only bare "friction"
#
# friction_archive uses EXACT matching by default:
#   farchive friction-archive   archives only friction-archive entries
#   farchive friction           archives only bare "friction" entries
#   farchive --prefix friction  archives friction and all subtopics
#
# The asymmetry is intentional: reading is cheap, moving is not.
#
# --- output contract ---
#
# Entry data goes to stdout. Diagnostics, summaries, and feedback
# go to stderr. This makes all commands pipe-friendly:
#   fshow friction | wc -l          count entries
#   fshow friction 2>/dev/null      clean entry data only
#   fshow friction                  both streams print to terminal
#
# --- dependencies ---
#
# mc_friction.awk    consolidated awk script for show and archive
# usb.sh             USB sync (optional, degrades gracefully)
#
# Data lives in a git repo. Archive is a directory of per-project
# monthly files. Archiving creates a git commit. friction_undo
# rolls back the last archive commit.
#
# USB integration: reads USB_* variables set by usb.sh (loaded by
# bash/06_usb.sh). Does not source usb.sh. Degrades gracefully
# if usb.sh has not run.

# --- usb.sh integration check ---
# usb.sh is loaded by infrastructure (bash/06_usb.sh) before this file.
# This module does not source usb.sh. It reads variables usb.sh set
# during shell initialization. If usb.sh has not run, USB features
# degrade gracefully via variable fallbacks below.
#
# This check is a runtime safety net, not dead code. It fires when:
# - usb-sh repo is not cloned on this machine
# - bash/ chain load order changed and usb.sh loads after this file
# - usb.sh was removed from the infrastructure chain
if [[ "${USB_INITIALIZED:-}" != true ]]; then
    if [[ -f "$HOME/personal_repos/usb-sh/usb.sh" ]]; then
        echo "friction[WARN]: usb.sh found but not loaded (check bash/ chain load order)"
    else
        echo "friction[WARN]: usb.sh not found, USB features unavailable"
    fi
    export USB_CONNECTED="${USB_CONNECTED:-false}"
fi

# --- variable setup ---
MC_FRICTION_DIRECTORY="${USB_FRICTION_LOCAL_DIR:-$HOME/personal_repos/friction}"
MC_FRICTION_FILEPATH="$MC_FRICTION_DIRECTORY/FRICTION.md"
MC_FRICTION_ARCHIVE="$MC_FRICTION_DIRECTORY/archive"
MC_FRICTION_AWK_SCRIPT="$HOME/personal_repos/my_config/scripts/mc_friction_process_entries.awk"

# --- source-time checks ---

if [[ ! -d "$MC_FRICTION_DIRECTORY" ]]; then
  mkdir -p "$MC_FRICTION_DIRECTORY"
fi

if [[ ! -f "$MC_FRICTION_FILEPATH" ]]; then
    touch "$MC_FRICTION_FILEPATH"
fi

if [[ ! -d "$MC_FRICTION_ARCHIVE" ]]; then
    mkdir -p "$MC_FRICTION_ARCHIVE"
fi

if [[ ! -d "$MC_FRICTION_DIRECTORY/.git" ]]; then
    echo "friction[WARN]: $MC_FRICTION_DIRECTORY is not a git repo, friction_archive and friction_undo will not work"
fi

if [[ ! -f "$MC_FRICTION_AWK_SCRIPT" ]]; then
    echo "friction[WARN]: awk script not found: $MC_FRICTION_AWK_SCRIPT"
    echo "friction[WARN]: friction_show and friction_archive will not work"
fi

# --- helpers ---
# _friction_require_repo -- check friction directory is a git repo
# Used by: friction_archive, friction_undo, fpush, fpull
_friction_require_repo() {
    if [[ ! -d "$MC_FRICTION_DIRECTORY/.git" ]]; then
        echo "friction[ERROR]: $MC_FRICTION_DIRECTORY is not a git repo" >&2
        return 1
    fi
}

# _friction_validate_project_name -- validate project name format
# Used by: friction_log, friction_show, friction_archive, friction_undo
_friction_validate_project_name() {
    local friction_project_name="$1"
    if [[ -z "$friction_project_name" ]]; then
        echo "friction[ERROR]: project name cannot be empty" >&2
        return 1
    fi
    if [[ ! "$friction_project_name" =~ ^[a-z0-9_-]+$ ]]; then
        echo "friction[ERROR]: project name must match [a-z0-9_-], got: $friction_project_name" >&2
        return 1
    fi
}


# --- public functions ---

# friction_log -- append a friction entry
# Usage: friction_log [-p project] message...
# Project auto-detected from git root dirname if -p not given.
friction_log() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
friction_log (alias: flog) - append a single-line friction entry
Usage:
  friction_log message...              project auto-detected from git root
  friction_log -p project message...   project set explicitly
EOF
        return 0
    fi

    local friction_project=""
    local friction_message=""
    local friction_timestamp=""
    local friction_git_root=""

    if [[ "$1" == "-p" ]]; then
        if [[ -z "${2:-}" ]]; then
            echo "friction[ERROR]: -p requires a project name" >&2
            return 1
        fi
        friction_project="$2"
        _friction_validate_project_name "$friction_project" || return 1
        shift 2
    fi

    friction_message="$*"
    if [[ -z "$friction_message" ]]; then
        echo "friction[ERROR]: message cannot be empty" >&2
        echo "friction: usage: friction_log [-p project] message..." >&2
        return 1
    fi

    if [[ -z "$friction_project" ]]; then
        friction_git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
        if [[ -n "$friction_git_root" ]]; then
            friction_project="$(basename "$friction_git_root")"
        else
            friction_project="unknown"
        fi
    fi

    friction_timestamp="$(date '+%Y-%m-%d %H:%M')"
    echo "@@ $friction_timestamp project:$friction_project | $friction_message" >> "$MC_FRICTION_FILEPATH"
    echo "friction: logged to project:$friction_project" >&2
}


# friction_show -- show friction entries with summary
# Replaces friction_show and friction_backlog.
# Default matching is prefix: fshow friction matches friction, friction-archive, etc.
# Use --exact for exact project match only.
# Summary (project breakdown, time-of-day, stale flags) goes to stderr.
# Entry data goes to stdout (pipe-friendly).
friction_show() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
friction_show (alias: fshow) - show friction entries with summary
Usage:
  friction_show                    show all entries
  friction_show friction           show friction and all subtopics (prefix match)
  friction_show --exact friction   show only exact project:friction entries
  friction_show friction 2>/dev/null   entries only, no summary
EOF
        return 0
    fi

    if [[ ! -f "$MC_FRICTION_AWK_SCRIPT" ]]; then
        echo "friction[ERROR]: awk script not found: $MC_FRICTION_AWK_SCRIPT" >&2
        return 1
    fi

    local friction_show_match_mode="prefix"
    local friction_show_project=""

    if [[ "${1:-}" == "--exact" ]]; then
        friction_show_match_mode="exact"
        shift
    fi

    if [[ -n "${1:-}" ]]; then
        friction_show_project="$1"
        _friction_validate_project_name "$friction_show_project" || return 1
    fi

    # compute stale threshold: 14 days ago, portable across GNU and macOS date
    local friction_show_stale_before=""
    if date -d '14 days ago' +%Y-%m-%d > /dev/null 2>&1; then
        friction_show_stale_before="$(date -d '14 days ago' +%Y-%m-%d)"
    elif date -v-14d +%Y-%m-%d > /dev/null 2>&1; then
        friction_show_stale_before="$(date -v-14d +%Y-%m-%d)"
    fi

    local friction_show_today=""
    friction_show_today="$(date +%Y-%m-%d)"

    awk -f "$MC_FRICTION_AWK_SCRIPT" \
        -v mode=show \
        -v project="$friction_show_project" \
        -v match_mode="$friction_show_match_mode" \
        -v stale_before="$friction_show_stale_before" \
        -v today="$friction_show_today" \
        "$MC_FRICTION_FILEPATH"
}

# friction_open -- open friction file in editor
# Usage: friction_open
friction_open() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
friction_open (alias: fopen)  - open friction file in editor
Usage:
  friction_open
EOF
        return 0
    fi

    local friction_editor="${EDITOR:-}"
    if [[ -z "$friction_editor" ]]; then
        echo "friction[ERROR]: EDITOR is not set" >&2
        echo "friction: set EDITOR in your shell config (e.g. export EDITOR=nvim)" >&2
        return 1
    fi

    if ! command -v "$friction_editor" > /dev/null 2>&1; then
        echo "friction[ERROR]: editor not found: $friction_editor" >&2
        return 1
    fi

    "$friction_editor" "$MC_FRICTION_FILEPATH"
}



# friction_archive -- archive friction entries for a project
# Dry-run by default: previews matched entries and prompts for confirmation.
# Use --execute to skip the preview and archive immediately.
# Default matching is exact: farchive friction archives only project:friction.
# Use --prefix to archive a project and all its subtopics.
# Use --before YYYY-MM-DD to archive only entries older than a date.
# Moves matched entries to archive/FRICTION_{project}_{YYYY-MM}.md.
# Creates a git commit. Use friction_undo to roll back.
friction_archive() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
friction_archive (alias: farchive) - archive friction entries for a project
Usage:
  friction_archive project                           preview, then confirm
  friction_archive --execute project                 skip preview, archive immediately
  friction_archive --prefix project                  match project and all subtopics
  friction_archive project --before YYYY-MM-DD       only entries before date
  friction_archive --prefix project --before YYYY-MM-DD  combined
Side effects:
  Moves matching entries from FRICTION.md to archive/FRICTION_{project}_{YYYY-MM}.md.
  Creates a git commit. Use friction_undo to roll back.
EOF
        return 0
    fi

    _friction_require_repo || return 1

    if [[ ! -f "$MC_FRICTION_AWK_SCRIPT" ]]; then
        echo "friction[ERROR]: awk script not found: $MC_FRICTION_AWK_SCRIPT" >&2
        return 1
    fi

    # --- parse arguments ---
    local friction_archive_match_mode="exact"
    local friction_archive_project=""
    local friction_archive_before_date=""
    local friction_archive_execute=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)
                friction_archive_match_mode="prefix"
                shift
                ;;
            --execute)
                friction_archive_execute=true
                shift
                ;;
            --before)
                if [[ -z "${2:-}" ]]; then
                    echo "friction[ERROR]: --before requires a date (YYYY-MM-DD)" >&2
                    return 1
                fi
                friction_archive_before_date="$2"
                if [[ ! "$friction_archive_before_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                    echo "friction[ERROR]: --before date must be YYYY-MM-DD, got: $friction_archive_before_date" >&2
                    return 1
                fi
                shift 2
                ;;
            -*)
                echo "friction[ERROR]: unknown flag: $1" >&2
                return 1
                ;;
            *)
                if [[ -n "$friction_archive_project" ]]; then
                    echo "friction[ERROR]: unexpected argument: $1" >&2
                    return 1
                fi
                friction_archive_project="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$friction_archive_project" ]]; then
        echo "friction[ERROR]: usage: friction_archive [--execute] [--prefix] project [--before YYYY-MM-DD]" >&2
        return 1
    fi

    _friction_validate_project_name "$friction_archive_project" || return 1

    if [[ ! -s "$MC_FRICTION_FILEPATH" ]]; then
        echo "friction[ERROR]: friction file is empty" >&2
        return 1
    fi

    # --- dry-run preview ---
    # run awk in show mode with the same filters to preview what would be archived
    local friction_preview_count=""
    friction_preview_count="$(awk -f "$MC_FRICTION_AWK_SCRIPT" \
        -v mode=show \
        -v project="$friction_archive_project" \
        -v match_mode="$friction_archive_match_mode" \
        -v before_date="$friction_archive_before_date" \
        "$MC_FRICTION_FILEPATH" 2>/dev/null | grep -c '^@@ ' || echo 0)"

    if [[ "$friction_preview_count" -le 0 ]]; then
        echo "friction: no entries match, nothing to archive" >&2
        return 1
    fi

    if [[ "$friction_archive_execute" != true ]]; then
        # show the matched entries
        echo "friction: entries to archive:" >&2
        echo "" >&2
        awk -f "$MC_FRICTION_AWK_SCRIPT" \
            -v mode=show \
            -v project="$friction_archive_project" \
            -v match_mode="$friction_archive_match_mode" \
            -v before_date="$friction_archive_before_date" \
            "$MC_FRICTION_FILEPATH" 2>/dev/null | head -50 >&2

        if [[ "$friction_preview_count" -gt 50 ]]; then
            echo "  ... and $(( friction_preview_count - 50 )) more" >&2
        fi

        echo "" >&2
        echo -n "friction: archive $friction_preview_count entries? [y/N] " >&2
        local friction_archive_confirm=""
        read -r friction_archive_confirm
        if [[ "$friction_archive_confirm" != "y" && "$friction_archive_confirm" != "Y" ]]; then
            echo "friction: cancelled" >&2
            return 0
        fi
    fi

    # --- lock check ---
    local friction_lock_pid=""
    if command -v lsof > /dev/null 2>&1; then
        friction_lock_pid="$(lsof -t "$MC_FRICTION_FILEPATH" 2>/dev/null)"
    elif command -v fuser > /dev/null 2>&1; then
        friction_lock_pid="$(fuser "$MC_FRICTION_FILEPATH" 2>/dev/null)"
    fi

    if [[ -n "$friction_lock_pid" ]]; then
        echo "friction[WARN]: FRICTION.md is open in another process (pid: $friction_lock_pid)" >&2
        echo -n "  proceed anyway? [y/N] " >&2
        local friction_lock_confirm=""
        read -r friction_lock_confirm
        if [[ "$friction_lock_confirm" != "y" && "$friction_lock_confirm" != "Y" ]]; then
            return 1
        fi
    fi

    # --- count entries before archive ---
    local friction_original_entry_count=""
    friction_original_entry_count="$(grep -c '^@@ ' "$MC_FRICTION_FILEPATH" || echo 0)"

    local friction_archive_file="$MC_FRICTION_ARCHIVE/FRICTION_${friction_archive_project}_$(date +%Y-%m).md"
    local friction_remaining_tmp="$MC_FRICTION_DIRECTORY/.friction_remaining.tmp"

    # --- run awk archive ---
    if ! awk -f "$MC_FRICTION_AWK_SCRIPT" \
        -v mode=archive \
        -v project="$friction_archive_project" \
        -v match_mode="$friction_archive_match_mode" \
        -v before_date="$friction_archive_before_date" \
        -v archive_file="$friction_archive_file" \
        "$MC_FRICTION_FILEPATH" > "$friction_remaining_tmp"; then
        echo "friction[ERROR]: awk script failed, friction file unchanged" >&2
        rm -f "$friction_remaining_tmp"
        return 1
    fi

    # --- atomic swap verification ---
    local friction_remaining_entry_count=""
    friction_remaining_entry_count="$(grep -c '^@@ ' "$friction_remaining_tmp" 2>/dev/null || echo 0)"

    local friction_archived_entry_count=$(( friction_original_entry_count - friction_remaining_entry_count ))

    if [[ "$friction_archived_entry_count" -le 0 ]]; then
        echo "friction[ERROR]: no entries matched, friction file unchanged" >&2
        rm -f "$friction_remaining_tmp"
        return 1
    fi

    # --- swap and commit ---
    mv "$friction_remaining_tmp" "$MC_FRICTION_FILEPATH"

    git -C "$MC_FRICTION_DIRECTORY" add -A

    local friction_commit_message="friction: archive $friction_archive_project ($friction_archived_entry_count entries)"
    if [[ -n "$friction_archive_before_date" ]]; then
        friction_commit_message="friction: archive $friction_archive_project before $friction_archive_before_date ($friction_archived_entry_count entries)"
    fi
    if [[ "$friction_archive_match_mode" == "prefix" ]]; then
        friction_commit_message="friction: archive ${friction_archive_project}* ($friction_archived_entry_count entries)"
        if [[ -n "$friction_archive_before_date" ]]; then
            friction_commit_message="friction: archive ${friction_archive_project}* before $friction_archive_before_date ($friction_archived_entry_count entries)"
        fi
    fi

    git -C "$MC_FRICTION_DIRECTORY" commit -m "$friction_commit_message"

    echo "friction: archived $friction_archived_entry_count entries to $friction_archive_file" >&2
    echo "friction: remaining $friction_remaining_entry_count entries" >&2
}

# friction_undo -- roll back the last friction_archive commit
# Usage: friction_undo
# Checks that the last commit message matches the archive pattern
# before resetting. This prevents accidentally undoing non-archive commits.
friction_undo() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
friction_undo  (alias: fundo)- roll back the last friction_archive commit
Usage:
  friction_undo
Side effects:
  Resets the last commit if it was a friction_archive commit.
  Restores FRICTION.md and archive/ to their pre-archive state.
EOF
        return 0
    fi

    _friction_require_repo || return 1

    local friction_last_commit_message=""
    friction_last_commit_message="$(git -C "$MC_FRICTION_DIRECTORY" log -1 --format=%s 2>/dev/null)"

    if [[ ! "$friction_last_commit_message" =~ ^friction:\ archive\ .+ ]]; then
        echo "friction[ERROR]: last commit is not an archive commit" >&2
        echo "friction: last commit: $friction_last_commit_message" >&2
        return 1
    fi

    echo "friction: undoing: $friction_last_commit_message"
    git -C "$MC_FRICTION_DIRECTORY" reset --hard HEAD~1
}

# --- aliases ---
alias flog='friction_log'
alias fshow='friction_show'
alias fopen='friction_open'
alias farchive='friction_archive'
alias fundo='friction_undo'
