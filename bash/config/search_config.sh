#!/bin/bash

# Default exclusion patterns
DEFAULT_SEARCH_EXCLUDE_DIRS=(
    ".git"
    "node_modules"
    "build"
    "dist"
    "renv"
    ".venv"
)

DEFAULT_SEARCH_EXCLUDE_FILES=(
    "*.log"
    "*.tmp"
    "*.bak"
    "*.swp"
    "*.gitignore"
    "*.Rprofile"
)

# Search options configuration
SEARCH_OPTIONS=(
    "h|help:Show this help message"
    "e|exclude-dir:Additional directory to exclude (requires value)"
    "f|exclude-file:Additional file pattern to exclude (requires value)"
    "v|verbose:Enable verbose output"
    "q|quiet:Suppress all output except final counts"
    "d|max-depth:Maximum directory depth to search (requires value)"
)

# Default settings
DEFAULT_SEARCH_VERBOSE=0
DEFAULT_SEARCH_QUIET=0
