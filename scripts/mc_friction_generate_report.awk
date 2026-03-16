#!/usr/bin/awk -f
# mc_friction_generate_report.awk -- parse structured friction entries
# Usage: awk -f mc_friction_generate_report.awk FRICTION.md
#
# Expected format:
#   ## YYYY-MM-DD HH:MM  project:name
#   What I was trying to do.
#   What actually happened or what annoyed me.
#   ?: idea or fix if one comes to mind

BEGIN {
    n_entries = 0
    n_proj = 0
    n_dates = 0
}

function flush_entry() {
    # store entry data
    e_date[n_entries]    = date
    e_time[n_entries]    = time
    e_project[n_entries] = project
    e_body[n_entries]    = body
    e_hasfix[n_entries]  = has_fix
    e_fix[n_entries]     = fix_text

    # tallies
    proj_count[project]++
    date_count[date]++
    if (has_fix) proj_fixes[project]++

    # index entries per project for grouping
    proj_idx[project, proj_count[project]] = n_entries

    # track hour for time-of-day distribution
    split(time, hm, ":")
    hour_count[hm[1] + 0]++
}

# skip blank lines and comment/header lines
/^$/ || /^#[^#]/ || /^Format:/ || /^Operations:/ { next }

# --- header line: start new entry ---
/^## [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
    # flush previous entry
    if (n_entries > 0) flush_entry()

    n_entries++

    # parse fields
    date = $2
    time = $3

    # extract project
    project = ""
    match($0, /project:[^ ]+/)
    if (RSTART > 0) {
        project = substr($0, RSTART + 8, RLENGTH - 8)
    } else {
        project = "(none)"
    }

    # reset body collectors
    body = ""
    n_body = 0
    has_fix = 0
    fix_text = ""

    # track unique dates and projects
    if (!(date in date_seen)) { date_seen[date] = 1; dates[n_dates++] = date }
    if (!(project in proj_seen)) { proj_seen[project] = 1; projs[n_proj++] = project }

    next
}

# --- body lines ---
n_entries > 0 && !/^## / && !/^$/ {
    line = $0
    gsub(/^[ \t]+|[ \t]+$/, "", line)

    if (line ~ /^\?:/) {
        has_fix = 1
        sub(/^\?:[ \t]*/, "", line)
        fix_text = fix_text (fix_text ? " | " : "") line
    } else {
        n_body++
        body = body (body ? "\n" : "") line
    }
}

END {
    # flush last entry
    if (n_entries > 0) flush_entry()

    # sort projects alphabetically
    for (i = 1; i < n_proj; i++) {
        key = projs[i]; j = i - 1
        while (j >= 0 && projs[j] > key) { projs[j+1] = projs[j]; j-- }
        projs[j+1] = key
    }

    # sort dates chronologically
    for (i = 1; i < n_dates; i++) {
        key = dates[i]; j = i - 1
        while (j >= 0 && dates[j] > key) { dates[j+1] = dates[j]; j-- }
        dates[j+1] = key
    }

    # --- header ---
    print "Friction Report"
    print "Generated: " strftime("%Y-%m-%d")
    if (n_dates > 0) print "Period:    " dates[0] " to " dates[n_dates - 1]
    print ""

    # --- summary ---
    print "-- SUMMARY --"
    printf "  Total entries:    %d\n", n_entries
    printf "  Date range:       %d days\n", n_dates
    printf "  Projects:         %d\n", n_proj
    if (n_dates > 0)
        printf "  Avg per day:      %.1f\n", n_entries / n_dates

    # count entries with fixes
    total_fixes = 0
    for (p = 0; p < n_proj; p++)
        total_fixes += proj_fixes[projs[p]] + 0
    printf "  With ?: ideas:    %d (%2.0f%%)\n", total_fixes,
        (n_entries > 0 ? total_fixes * 100 / n_entries : 0)
    print ""

    # --- by project ---
    print "-- BY PROJECT --"
    for (p = 0; p < n_proj; p++) {
        proj = projs[p]
        fixes = proj_fixes[proj] + 0
        pct = (n_entries > 0) ? (proj_count[proj] * 100 / n_entries) : 0
        printf "  %-20s  %3d entries  %2d with ?:  (%2.0f%%)\n",
            proj, proj_count[proj], fixes, pct
    }
    print ""

    # --- by date ---
    print "-- BY DATE --"
    for (d = 0; d < n_dates; d++)
        printf "  %s  %3d\n", dates[d], date_count[dates[d]]
    print ""

    # --- time of day ---
    print "-- TIME OF DAY --"
    for (h = 0; h < 24; h++) {
        if (hour_count[h] > 0)
            printf "  %02d:xx  %3d  %s\n", h, hour_count[h],
                substr("||||||||||||||||||||||||||||||||||||||||", 1, hour_count[h])
    }
    print ""

    # --- entries grouped by project, sorted by date ---
    print "-- ENTRIES BY PROJECT --"
    for (p = 0; p < n_proj; p++) {
        proj = projs[p]
        n = proj_count[proj]

        printf "\n[%s] (%d entries)\n", proj, n

        # gather indices for this project
        for (i = 1; i <= n; i++)
            s_idx[i] = proj_idx[proj, i]

        # sort by date+time (insertion sort on indices)
        for (i = 2; i <= n; i++) {
            ki = s_idx[i]
            kv = e_date[ki] e_time[ki]
            j = i - 1
            while (j >= 1 && (e_date[s_idx[j]] e_time[s_idx[j]]) > kv) {
                s_idx[j+1] = s_idx[j]
                j--
            }
            s_idx[j+1] = ki
        }

        for (i = 1; i <= n; i++) {
            idx = s_idx[i]
            printf "\n  %s %s\n", e_date[idx], e_time[idx]

            # print body lines indented
            split(e_body[idx], blines, "\n")
            for (b in blines)
                printf "    %s\n", blines[b]

            if (e_hasfix[idx])
                printf "    ?: %s\n", e_fix[idx]
        }
    }

    # --- flags ---
    print ""
    print "-- FLAGS --"
    flagged = 0
    for (p = 0; p < n_proj; p++) {
        proj = projs[p]
        if (proj_count[proj] >= 3) {
            printf "  %-20s  %dx -- trigger: build a solution\n", proj, proj_count[proj]
            flagged = 1
        }
    }
    if (!flagged) print "  (no project hit 3x threshold yet)"

    # unresolved: no ideas
    print ""
    print "-- UNRESOLVED (no ?: idea) --"
    unresolved = 0
    for (i = 1; i <= n_entries; i++) {
        if (!e_hasfix[i]) {
            printf "  %s %s  %-16s  %s\n",
                e_date[i], e_time[i], e_project[i],
                substr(e_body[i], 1, 60)
            unresolved = 1
        }
    }
    if (!unresolved) print "  (all entries have ideas -- nice)"
}
