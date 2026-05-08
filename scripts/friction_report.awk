#!/usr/bin/awk -f
# friction_report.awk -- reorganize friction log by category, then date
# Usage: awk -f friction_report.awk _friction.txt
#    or: awk -f friction_report.awk _friction.txt > _friction_report.txt

BEGIN {
    total = 0
    n_dates = 0
    n_cats = 0
}

# skip blank lines and comment/header lines
/^$/ || /^#/ || /^Format:/ || /^Operations:/ { next }

# parse entry lines
# handles both "2026-02-04 write:" and "2026-02-04: write:"
/^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
    date = $1
    sub(/:$/, "", date)           # strip trailing colon from date if present

    # rebuild rest of line after date field
    rest = ""
    for (i = 2; i <= NF; i++) rest = rest (i > 2 ? " " : "") $i

    # extract category: first word, strip trailing colon
    split(rest, parts, ":")
    cat = parts[1]
    gsub(/^[ \t]+|[ \t]+$/, "", cat)
    cat = tolower(cat)

    # extract description: everything after first colon
    desc = ""
    for (i = 2; i <= length(parts); i++) {
        desc = desc (i > 2 ? ":" : "") parts[i]
    }
    gsub(/^[ \t]+|[ \t]+$/, "", desc)

    # store entry
    total++
    cat_count[cat]++
    date_count[date]++

    # track unique dates and categories for ordering
    if (!(date in date_seen)) { date_seen[date] = 1; dates[n_dates++] = date }
    if (!(cat in cat_seen))   { cat_seen[cat] = 1;   cats[n_cats++] = cat }

    # store entries keyed by category, then index within category
    idx = cat_count[cat]
    entry_date[cat, idx] = date
    entry_desc[cat, idx] = desc
}

END {
    # sort category names alphabetically (insertion sort)
    for (i = 1; i < n_cats; i++) {
        key = cats[i]
        j = i - 1
        while (j >= 0 && cats[j] > key) {
            cats[j + 1] = cats[j]
            j--
        }
        cats[j + 1] = key
    }

    # sort dates chronologically (insertion sort)
    for (i = 1; i < n_dates; i++) {
        key = dates[i]
        j = i - 1
        while (j >= 0 && dates[j] > key) {
            dates[j + 1] = dates[j]
            j--
        }
        dates[j + 1] = key
    }

    # --- header ---
    print "Friction Report"
    print "Generated: " strftime("%Y-%m-%d")
    if (n_dates > 0) print "Period:    " dates[0] " to " dates[n_dates - 1]
    print ""

    # --- summary ---
    print "-- SUMMARY --"
    printf "  Total entries:  %d\n", total
    printf "  Date range:     %d days\n", n_dates
    printf "  Categories:     %d\n", n_cats
    if (n_dates > 0)
        printf "  Avg per day:    %.1f\n", total / n_dates
    print ""

    # --- category breakdown ---
    print "-- BY CATEGORY --"
    for (c = 0; c < n_cats; c++) {
        cat = cats[c]
        pct = (total > 0) ? (cat_count[cat] * 100 / total) : 0
        printf "  %-12s  %3d  (%2.0f%%)\n", cat, cat_count[cat], pct
    }
    print ""

    # --- date breakdown ---
    print "-- BY DATE --"
    for (d = 0; d < n_dates; d++) {
        printf "  %s  %3d\n", dates[d], date_count[dates[d]]
    }
    print ""

    # --- entries grouped by category, sorted by date within ---
    print "-- ENTRIES BY CATEGORY --"
    for (c = 0; c < n_cats; c++) {
        cat = cats[c]
        printf "\n[%s] (%d entries)\n", cat, cat_count[cat]

        # collect this category's entries, sort by date
        n = cat_count[cat]

        # copy into sortable arrays
        for (i = 1; i <= n; i++) {
            s_date[i] = entry_date[cat, i]
            s_desc[i] = entry_desc[cat, i]
        }

        # insertion sort by date
        for (i = 2; i <= n; i++) {
            kd = s_date[i]; kx = s_desc[i]
            j = i - 1
            while (j >= 1 && s_date[j] > kd) {
                s_date[j + 1] = s_date[j]
                s_desc[j + 1] = s_desc[j]
                j--
            }
            s_date[j + 1] = kd
            s_desc[j + 1] = kx
        }

        for (i = 1; i <= n; i++) {
            printf "  %s  %s\n", s_date[i], s_desc[i]
        }
    }

    # --- flags ---
    print ""
    print "-- FLAGS --"
    flagged = 0
    for (c = 0; c < n_cats; c++) {
        cat = cats[c]
        if (cat_count[cat] >= 3) {
            printf "  %-12s  %dx -- trigger: build a solution\n", cat, cat_count[cat]
            flagged = 1
        }
    }
    if (!flagged) print "  (no category hit 3x threshold yet)"
}
