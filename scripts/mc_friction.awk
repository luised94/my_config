#!/usr/bin/awk -f
# mc_friction.awk -- parse and process @@ friction entries
#
# Modes (set via -v mode=show|archive):
#   show     filter and display entries, summary to stderr
#   archive  split entries: matched -> archive_file, remaining -> stdout
#
# Variables:
#   -v mode=show|archive          required
#   -v project=NAME               filter by project (optional in show, required in archive)
#   -v match_mode=exact|prefix    exact: project == NAME, prefix: project == NAME or starts with NAME-
#   -v before_date=YYYY-MM-DD    only match entries before this date (optional, archive mode)
#   -v archive_file=PATH          destination for matched entries (required in archive mode)
#   -v stale_before=YYYY-MM-DD   entries older than this are flagged stale (optional, show mode)
#   -v today=YYYY-MM-DD           current date for display (optional, show mode)
#
# Entry format:
#   @@ 2026-03-11 14:30 project:sm2 | description text here
#
# Non-@@ lines before the first entry are preamble (always passed through).
# Non-@@ lines after an entry are associated with that entry and travel with it.

BEGIN {
    entry_count = 0
    matched_count = 0
    kept_count = 0
    malformed_count = 0
    in_entry = 0
    in_preamble = 1
    entry_line = ""
    entry_body = ""
    entry_date = ""
    entry_time = ""
    entry_project = ""
    unique_dates = 0
    unique_projects = 0
    unique_domains = 0
}

# strip carriage returns
{ gsub(/\r$/, "") }

# --- entry header ---
/^@@ / {
    # flush previous entry
    if (in_entry) flush_entry()

    in_preamble = 0
    in_entry = 1
    entry_line = $0
    entry_body = ""

    # parse fields
    entry_date = $2
    entry_time = $3

    # extract project tag
    entry_project = ""
    if (match($0, /project:[^ ]+/)) {
        entry_project = substr($0, RSTART + 8, RLENGTH - 8)
    }

    # validate: date and project must be present
    if (entry_date !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ || entry_project == "") {
        printf "friction[WARN]: malformed entry: %s\n", $0 > "/dev/stderr"
        malformed_count++
    }

    # track unique dates
    if (!(entry_date in date_seen)) {
        date_seen[entry_date] = 1
        date_list[unique_dates++] = entry_date
    }
    date_count[entry_date]++

    # track unique projects
    if (!(entry_project in project_seen)) {
        project_seen[entry_project] = 1
        project_list[unique_projects++] = entry_project
    }
    project_count[entry_project]++

    # extract domain (segment before first hyphen)
    domain = entry_project
    hyphen_position = index(domain, "-")
    if (hyphen_position > 0) {
        domain = substr(domain, 1, hyphen_position - 1)
    }
    domain_count[domain]++
    if (!(domain in domain_seen)) {
        domain_seen[domain] = 1
        domain_list[unique_domains++] = domain
    }
    # track subtopics per domain
    if (entry_project != domain) {
        domain_subtopic_count[domain]++
    }

    # time-of-day tracking
    split(entry_time, time_parts, ":")
    hour_count[time_parts[1] + 0]++

    next
}

# --- non-entry lines ---
{
    if (in_preamble) {
        # lines before any entry: always pass through to stdout
        print
    } else if (in_entry) {
        # lines after an entry: accumulate in body buffer
        entry_body = entry_body $0 "\n"
    } else {
        # orphaned non-entry line between entries (edge case): pass through
        print
    }
}

# --- flush one entry: filter, route, track ---
function flush_entry() {
    if (!in_entry) return

    entry_count++

    # determine match
    is_match = 0
    if (project == "") {
        # no filter: everything matches
        is_match = 1
    } else if (match_mode == "exact") {
        is_match = (entry_project == project)
    } else {
        # prefix: matches project itself or any subtopic (project-*)
        is_match = (entry_project == project || index(entry_project, project "-") == 1)
    }

    # date filter (archive mode)
    if (is_match && before_date != "" && entry_date >= before_date) {
        is_match = 0
    }

    # track matched stats separately for summary
    if (is_match) {
        matched_count++
        matched_project_count[entry_project]++
        matched_date_count[entry_date]++
        if (!(entry_date in matched_date_seen)) {
            matched_date_seen[entry_date] = 1
            matched_date_list[matched_unique_dates++] = entry_date
        }
        # stale check
        if (stale_before != "" && entry_date < stale_before) {
            stale_count++
            stale_entry[stale_count] = entry_date " " entry_project
        }
    }

    # route output
    if (mode == "show") {
        if (is_match) {
            print entry_line
            if (entry_body != "") printf "%s", entry_body
        }
    } else if (mode == "archive") {
        if (is_match) {
            print entry_line >> archive_file
            if (entry_body != "") printf "%s", entry_body >> archive_file
        } else {
            kept_count++
            print entry_line
            if (entry_body != "") printf "%s", entry_body
        }
    }

    # reset
    in_entry = 0
    entry_line = ""
    entry_body = ""
    entry_date = ""
    entry_time = ""
    entry_project = ""
}

END {
    flush_entry()
    if (mode == "archive" && archive_file != "") close(archive_file)

    # --- sort helpers (insertion sort on string arrays) ---
    # sort project_list alphabetically
    for (i = 1; i < unique_projects; i++) {
        sort_key = project_list[i]; j = i - 1
        while (j >= 0 && project_list[j] > sort_key) {
            project_list[j + 1] = project_list[j]; j--
        }
        project_list[j + 1] = sort_key
    }
    # sort domain_list alphabetically
    for (i = 1; i < unique_domains; i++) {
        sort_key = domain_list[i]; j = i - 1
        while (j >= 0 && domain_list[j] > sort_key) {
            domain_list[j + 1] = domain_list[j]; j--
        }
        domain_list[j + 1] = sort_key
    }
    # sort date_list chronologically
    for (i = 1; i < unique_dates; i++) {
        sort_key = date_list[i]; j = i - 1
        while (j >= 0 && date_list[j] > sort_key) {
            date_list[j + 1] = date_list[j]; j--
        }
        date_list[j + 1] = sort_key
    }

    # --- summary to stderr ---
    if (mode == "show") {
        print "" > "/dev/stderr"
        if (project != "") {
            match_label = (match_mode == "exact") ? "=" : ""
            printf "friction: %d entries for project:%s%s\n", matched_count, match_label, project > "/dev/stderr"
        } else {
            printf "friction: %d entries total\n", entry_count > "/dev/stderr"
        }

        if (malformed_count > 0) {
            printf "friction[WARN]: %d malformed entries\n", malformed_count > "/dev/stderr"
        }

        # project breakdown
        if (unique_projects > 1 || project == "") {
            print "" > "/dev/stderr"
            print "  by project:" > "/dev/stderr"
            for (i = 0; i < unique_projects; i++) {
                current_project = project_list[i]
                # skip projects not in the matched set when filtering
                if (project != "" && !(current_project in matched_project_count)) continue
                display_count = (project != "") ? matched_project_count[current_project] : project_count[current_project]
                if (display_count + 0 == 0) continue
                display_total = (project != "") ? matched_count : entry_count
                percentage = (display_total > 0) ? (display_count * 100 / display_total) : 0
                printf "    %-24s  %3d  (%2.0f%%)\n", current_project, display_count, percentage > "/dev/stderr"
            }
        }

        # domain rollup (only when showing all or prefix match reveals multiple subtopics)
        if (unique_domains > 0 && (project == "" || unique_projects > 1)) {
            has_rollup = 0
            for (i = 0; i < unique_domains; i++) {
                if (domain_subtopic_count[domain_list[i]] + 0 > 0) { has_rollup = 1; break }
            }
            if (has_rollup) {
                print "" > "/dev/stderr"
                print "  by domain:" > "/dev/stderr"
                for (i = 0; i < unique_domains; i++) {
                    current_domain = domain_list[i]
                    subtopics = domain_subtopic_count[current_domain] + 0
                    if (subtopics > 0) {
                        printf "    %-24s  %3d  [%d subtopics]\n", current_domain, domain_count[current_domain], subtopics > "/dev/stderr"
                    }
                }
            }
        }

        # date range
        if (unique_dates > 0) {
            print "" > "/dev/stderr"
            printf "  date range: %s to %s (%d days)\n", date_list[0], date_list[unique_dates - 1], unique_dates > "/dev/stderr"
            if (unique_dates > 1) {
                printf "  avg per day: %.1f\n", entry_count / unique_dates > "/dev/stderr"
            }
        }

        # time of day
        has_hours = 0
        for (h = 0; h < 24; h++) {
            if (hour_count[h] + 0 > 0) { has_hours = 1; break }
        }
        if (has_hours) {
            print "" > "/dev/stderr"
            print "  time of day:" > "/dev/stderr"
            for (h = 0; h < 24; h++) {
                if (hour_count[h] + 0 > 0) {
                    bar = ""
                    for (b = 0; b < hour_count[h] && b < 40; b++) bar = bar "|"
                    printf "    %02d:xx  %3d  %s\n", h, hour_count[h], bar > "/dev/stderr"
                }
            }
        }

        # stale entries
        if (stale_count + 0 > 0) {
            print "" > "/dev/stderr"
            printf "  stale (>14 days): %d entries\n", stale_count > "/dev/stderr"
            for (s = 1; s <= stale_count && s <= 5; s++) {
                printf "    %s\n", stale_entry[s] > "/dev/stderr"
            }
            if (stale_count > 5) {
                printf "    ... and %d more\n", stale_count - 5 > "/dev/stderr"
            }
        }

        # flags: projects hitting 3x threshold
        print "" > "/dev/stderr"
        print "  flags:" > "/dev/stderr"
        flagged = 0
        for (i = 0; i < unique_projects; i++) {
            current_project = project_list[i]
            if (project_count[current_project] >= 3) {
                printf "    %-24s  %dx -- trigger: build a solution\n", current_project, project_count[current_project] > "/dev/stderr"
                flagged = 1
            }
        }
        if (!flagged) {
            print "    (no project hit 3x threshold)" > "/dev/stderr"
        }

    } else if (mode == "archive") {
        # archive summary
        printf "  archived: %d entries (project:%s", matched_count, project > "/dev/stderr"
        if (before_date != "") {
            printf ", before %s", before_date > "/dev/stderr"
        }
        printf ")\n" > "/dev/stderr"
        printf "  remaining: %d entries\n", kept_count > "/dev/stderr"

        # date range of archived entries
        if (matched_unique_dates + 0 > 0) {
            # sort matched dates
            for (i = 1; i < matched_unique_dates; i++) {
                sort_key = matched_date_list[i]; j = i - 1
                while (j >= 0 && matched_date_list[j] > sort_key) {
                    matched_date_list[j + 1] = matched_date_list[j]; j--
                }
                matched_date_list[j + 1] = sort_key
            }
            printf "  archived date range: %s to %s\n", matched_date_list[0], matched_date_list[matched_unique_dates - 1] > "/dev/stderr"
        }
    }
}
