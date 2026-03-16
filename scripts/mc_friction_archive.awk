#!/usr/bin/awk -f
# mc_friction_archive.awk -- split friction entries by project
#
# Usage (called by farchive wrapper):
#   awk -v project="kbd" -v archive_file="path/to/archive.md" \
#       -f mc_friction_archive.awk FRICTION.md > remaining.tmp
#
# Matched entries  -> appended to archive_file
# Remaining entries -> written to stdout (wrapper swaps back)
# Summary          -> written to stderr

BEGIN {
    matched = 0
    kept = 0
    in_entry = 0
    buf = ""
    entry_project = ""
}

# detect entry header
/^## [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
    # flush previous entry
    if (in_entry) flush_entry()

    in_entry = 1
    buf = $0 "\n"

    # extract project from header
    entry_project = ""
    if (match($0, /project:[^ ]+/)) {
        entry_project = substr($0, RSTART + 8, RLENGTH - 8)
    }
    next
}

# non-header lines: accumulate into buffer or pass through
{
    if (in_entry) {
        buf = buf $0 "\n"
    } else {
        # lines before any entry (comments, blank lines at top)
        print
    }
}

function flush_entry() {
    if (entry_project == project) {
        # write to archive file
        printf "%s", buf >> archive_file
        matched++
    } else {
        # write to stdout (remaining)
        printf "%s", buf
        kept++
    }
    buf = ""
    entry_project = ""
    in_entry = 0
}

END {
    if (in_entry) flush_entry()
    close(archive_file)

    # summary to stderr
    printf "  archived: %d entries (project:%s)\n", matched, project > "/dev/stderr"
    printf "  remaining: %d entries\n", kept > "/dev/stderr"
}
