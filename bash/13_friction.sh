#!/usr/bin/env bash
# 13_friction.sh -- friction tracking: single-line entries, project-tagged.
# Source this file. Do not execute directly.
# Loaded by bash/ startup chain after 06_usb.sh.
#
# Entry format (one per line):
#   @@ 2026-03-11 14:30 project:sm2 | description text here
#
# Fields:
#   @@           -- entry marker
#   ISO date     -- YYYY-MM-DD HH:MM, auto-generated
#   project:name -- project tag, auto-detected or explicit
#   |            -- separator
#   text         -- free-form description, no newlines
#
# Data lives in a git repo. Archive is a directory of per-project
# monthly files. Archiving creates a git commit. fundo rolls back
# the last archive commit.
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

if [[ -d "$MC_FRICTION_DIRECTORY/.git" ]]; then
    MC_FRICTION_IS_REPO=true
else
    echo "friction[WARN]: $MC_FRICTION_DIRECTORY is not a git repo, farchive and fundo will not work"
    MC_FRICTION_IS_REPO=false
fi

# --- helpers ---
# _friction_validate_project_name -- validate project name format
# Used by: flog, ffriction, farchive, fundo
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

# _friction_require_entries -- check friction file has entries
# Used by: ffriction, fbacklog, farchive
_friction_require_entries() {
    if [[ ! -s "$MC_FRICTION_FILEPATH" ]]; then
        echo "friction[ERROR]: friction file is empty" >&2
        return 1
    fi
    if ! grep -q '^@@ ' "$MC_FRICTION_FILEPATH"; then
        echo "friction[ERROR]: friction file has no entries (no @@ lines)" >&2
        return 1
    fi
}
