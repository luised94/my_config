#!/usr/bin/env bash
# ==================================================================
# 15_job_hunt.sh -- Job search pipeline for WSL
# ==================================================================
# Author:  Luis E. Martinez-Rodriguez
# Created: 2026-06-05
# License: Personal use
#
# PURPOSE:
#   Reduce friction between spotting a job posting and submitting
#   a tailored application. Provides aliases and functions for
#   saving postings, copying prompt templates to clipboard,
#   accessing portal-ready info, logging applications, and
#   batch-opening career pages.
#
# SETUP:
#   Run `jobhelp` for setup prerequisites and the full command
#   reference; run `jobinit` once to create the directory structure.
#   (The authoritative setup steps live in the jobhelp SETUP section
#   so they are accessible at runtime and documented in one place.)
#
# LAYOUT (two roots, since 2026-06-23):
#   CONFIG (kbd, version-controlled): alerts/, bookmarks/, prompts/,
#     portal-ready-info.txt  -> $JOB_CONFIG_DIR
#   DATA (Dropbox, not committed): postings/, tracker.tsv
#     -> $JOB_DATA_DIR
#
# QUICK WORKFLOW:
#   # Monday morning -- scan career pages
#   $ jobcheck                    # opens bookmarked pages in browser
#
#   # Spot a good posting at Beam
#   $ jobsave beam scientist-crispr-screening
#   # -> paste the posting text into the file that opens
#
#   # Prepare application materials
#   $ jobclip                     # copies prompt+CV to clipboard
#   # -> paste into Claude, add posting text, get tailored outputs
#
#   # Fill out the portal
#   $ jobinfo                     # prints portal-ready info
#
#   # After submitting
#   $ joblog beam 'Scientist, CRISPR Screening' 2
#
#   # Check your progress anytime
#   $ jobstatus
#
# DEPENDENCIES:
#   Required:  bash >= 4.0, coreutils (date, mkdir, cat, grep, ls,
#              column, printf, wc)
#   Optional:  clip.exe (WSL clipboard), wslview (WSL browser),
#              xdg-open (fallback browser)
#
# SEE ALSO: README.md in the job_applications directory.
# ==================================================================

# ------------------------------------------------------------------
# ENVIRONMENT VALIDATION
# ------------------------------------------------------------------
# Guard: MC_WINDOWS_USER must be set. Without it, every path is
# wrong and the user gets silent failures or writes to the wrong
# location. We warn loudly but don't exit (this is sourced, not
# executed -- exiting would kill the shell).

if [ -z "${MC_WINDOWS_USER}" ]; then
    echo "[15_job_hunt.sh] WARNING: MC_WINDOWS_USER is not set." >&2
    echo "  Job search commands will not work." >&2
    echo "  Add to your bashrc: export MC_WINDOWS_USER=\"YourUsername\"" >&2
    # Define a stub so commands fail with a clear message instead
    # of cryptic path errors.
    jobhelp() { echo "ERROR: MC_WINDOWS_USER not set. See bashrc." >&2; return 1; }
    return 0 2>/dev/null || exit 0
fi

# ------------------------------------------------------------------
# PATHS
# ------------------------------------------------------------------
# Paths derive from TWO roots, by design (changed 2026-06-23):
#
#   JOB_CONFIG_DIR  Version-controlled text config + knowledge that
#                   lives in the kbd repo. Small, diffable, worth
#                   committing: alerts/, bookmarks/, prompts/,
#                   portal-ready-info.txt. Edit it, commit it, and
#                   it follows you to any machine via git.
#
#   JOB_DATA_DIR    Bulky or machine-/account-specific artifacts that
#                   stay in Dropbox: postings/ (raw posting text +
#                   tailored docs), tracker.tsv (working application
#                   log). Not committed to kbd.
#
# Why split: config is knowledge you want under version control and
# portable across machines; data is working output that is large,
# changes constantly, or you simply do not want in a git history.
#
# To relocate either root, change only the one line below.

# kbd config root. Uses $HOME so it resolves on any machine where the
# repo is cloned to the same relative path.
JOB_CONFIG_DIR="${MC_REPOS_ROOT}/usb-repos/kbd/docs/job_applications"

# Dropbox data root (postings + tracker live here). Derived from MC_DROPBOX_PATH
# (exported by 02_wsl.sh in WSL); falls back to the literal path when unset.
JOB_DATA_DIR="${MC_DROPBOX_PATH:-/mnt/c/Users/${MC_WINDOWS_USER}/MIT Dropbox/Luis Martinez}/Personal/job_applications"

# Config paths (kbd).
JOB_PROMPTS="${JOB_CONFIG_DIR}/prompts"
JOB_BOOKMARKS="${JOB_CONFIG_DIR}/bookmarks"
JOB_ALERTS="${JOB_CONFIG_DIR}/alerts"
JOB_PORTAL="${JOB_CONFIG_DIR}/portal-ready-info.txt"

# Data paths (Dropbox).
JOB_POSTINGS="${JOB_DATA_DIR}/postings"
JOB_TRACKER="${JOB_DATA_DIR}/tracker.tsv"

# Default prompt file name (must exist in $JOB_PROMPTS/).
# Change this if you create a new primary prompt variant.
JOB_DEFAULT_PROMPT="industry.txt"

# ------------------------------------------------------------------
# ROOT DIRECTORY VALIDATION
# ------------------------------------------------------------------
# Either root may be missing: kbd may not be cloned yet, or Dropbox
# may not be mounted/synced. Warn early on either so the user does
# not discover it mid-workflow.

if [ ! -d "${JOB_CONFIG_DIR}" ]; then
    echo "[15_job_hunt.sh] WARNING: Config directory (kbd) not found:" >&2
    echo "  ${JOB_CONFIG_DIR}" >&2
    echo "  Is the kbd repo cloned? Run 'jobinit' to create it." >&2
fi

if [ ! -d "${JOB_DATA_DIR}" ]; then
    echo "[15_job_hunt.sh] WARNING: Data directory (Dropbox) not found:" >&2
    echo "  ${JOB_DATA_DIR}" >&2
    echo "  Is Dropbox synced? Is MC_WINDOWS_USER correct?" >&2
    echo "  Run 'jobinit' after fixing to create subdirectories." >&2
fi

# ------------------------------------------------------------------
# INITIALIZATION
# ------------------------------------------------------------------
# jobinit: Create the full directory structure and starter files.
# Safe to run multiple times (idempotent). Run once on a new
# machine or after a fresh Dropbox sync.

jobinit() {
    echo "Initializing job search directory structure..."

    # --- kbd config root ---
    if [ ! -d "${JOB_CONFIG_DIR}" ]; then
        echo "  Config root does not exist: ${JOB_CONFIG_DIR}"
        echo "  Attempting to create..."
        mkdir -p "${JOB_CONFIG_DIR}" 2>/dev/null
        if [ ! -d "${JOB_CONFIG_DIR}" ]; then
            echo "  ERROR: Cannot create config root." >&2
            echo "  Is the kbd repo path correct and writable?" >&2
            return 1
        fi
    fi

    # --- Dropbox data root ---
    if [ ! -d "${JOB_DATA_DIR}" ]; then
        echo "  Data root does not exist: ${JOB_DATA_DIR}"
        echo "  Attempting to create..."
        mkdir -p "${JOB_DATA_DIR}" 2>/dev/null
        if [ ! -d "${JOB_DATA_DIR}" ]; then
            echo "  ERROR: Cannot create data root." >&2
            echo "  Check that the Dropbox path is correct and writable." >&2
            return 1
        fi
    fi

    # Create subdirectories. Config subdirs in kbd, data subdirs in
    # Dropbox.
    mkdir -p "${JOB_PROMPTS}" "${JOB_BOOKMARKS}" "${JOB_ALERTS}" 2>/dev/null
    mkdir -p "${JOB_POSTINGS}" 2>/dev/null

    # Create starter alerts files if they don't exist.
    # PURPOSE: Document all active alerts and monitoring prompts
    # in one place so you can audit, update, and not forget what
    # you set up. External services (Google Alerts, LinkedIn, etc.)
    # are configured in those platforms -- these files are your
    # local record of what's active and why.
    if [ ! -f "${JOB_ALERTS}/google-alerts.txt" ]; then
        cat > "${JOB_ALERTS}/google-alerts.txt" << 'GALERTS'
# google-alerts.txt -- Google Alert queries
# ==========================================
# Configure these at: https://google.com/alerts
# Settings: once a day, only best results, deliver to email.
#
# PURPOSE: Google Alerts catch hiring signals and industry news
# that job boards miss. A company raising money or announcing
# an expansion will start hiring 2-4 weeks later. Catching
# that signal early puts you ahead of the posting.
#
# STRATEGY:
#   - Group 1: Target company hiring signals. Use company
#     names + hiring/scientist/careers keywords.
#   - Group 2: Market and trend tracking. Catch funding rounds,
#     expansions, layoffs in your target geography.
#   - Group 3: Technology-specific hiring. Match your skill
#     areas to active hiring keywords.
#
# MAINTENANCE: Review monthly. Remove companies you've lost
# interest in. Add companies discovered through networking.
# If an alert produces zero useful results for 4 weeks,
# adjust the query or delete it.
#
# FORMAT: One alert per block. Include the exact query string
# you entered in Google Alerts and a note about its purpose.
#
# EXAMPLE:
# --- Alert: Tier 1 company hiring signals ---
# Query: "Company A" OR "Company B" hiring OR scientist
# Purpose: Catch job postings and hiring news at top targets
# Status: active
# Last reviewed: YYYY-MM-DD
GALERTS
        echo "  Created: alerts/google-alerts.txt"
    fi

    if [ ! -f "${JOB_ALERTS}/linkedin-alerts.txt" ]; then
        cat > "${JOB_ALERTS}/linkedin-alerts.txt" << 'LALERTS'
# linkedin-alerts.txt -- LinkedIn job alert configurations
# ========================================================
# Configure these at: linkedin.com/jobs
# Set each to daily email notification.
#
# PURPOSE: LinkedIn alerts are your primary job discovery
# channel. Each alert maps to one of your skill-profile
# buckets so you see relevant postings grouped by fit type.
#
# STRATEGY:
#   - One alert per active bucket. Buckets 1-5 are live; bucket 6
#     (strategic/non-bench) is dormant -- add an alert only when a
#     posting activates it. As of 2026-06-23: Alerts 1-4 cover
#     buckets 1-4, Alert 5 covers bucket 5 (non-research PhD roles).
#   - Use specific keywords that match how companies write
#     job postings, not how academics describe skills.
#   - Filter by location, experience level, job type, and
#     industry to reduce noise.
#   - Also follow target companies directly on LinkedIn so
#     their postings appear in your feed even if keywords
#     don't match.
#
# MAINTENANCE: Review biweekly. If an alert produces too
# much noise, tighten the keywords or add industry filters.
# If it produces nothing, broaden or check that the keywords
# match how industry actually phrases these roles.
#
# FORMAT: One alert per block. Include keywords, filters,
# and which bucket it serves.
#
# EXAMPLE:
# --- Alert: Bucket 1 (Protein biochemistry) ---
# Keywords: Scientist protein biochemistry
# Location: Boston, MA + Cambridge, MA (25 mi)
# Filters: Full-time + Contract, On-site + Hybrid
# Industry: Biotechnology Research, Pharmaceutical Manufacturing
# Experience: Entry level + Associate + Mid-Senior level
# Salary: $80,000+
# Frequency: Daily
# Status: active
# Last reviewed: YYYY-MM-DD
#
# Also document your LinkedIn Job Preferences here:
# Job titles: (list the titles you've set)
# Location types: (on-site/hybrid/remote)
# Locations: (cities)
# Employment types: (full-time, contract, etc.)
LALERTS
        echo "  Created: alerts/linkedin-alerts.txt"
    fi

    if [ ! -f "${JOB_ALERTS}/other-alerts.txt" ]; then
        cat > "${JOB_ALERTS}/other-alerts.txt" << 'OALERTS'
# other-alerts.txt -- BioSpace, Indeed, and other platform alerts
# ===============================================================
# Document any additional job alert services here.
#
# PURPOSE: Aggregator sites (BioSpace, Indeed, Glassdoor) cast
# a wider net than company career pages. They have 1-3 day lag
# compared to direct postings, but catch companies you haven't
# bookmarked.
#
# STRATEGY: Keep these broad. Use 1-2 saved searches per
# platform. The goal is to catch things your LinkedIn alerts
# and career page bookmarks miss, not to duplicate them.
#
# FORMAT: One platform per block. Include the search terms,
# filters, and email frequency.
#
# EXAMPLE:
# --- BioSpace ---
# URL: https://jobs.biospace.com
# Search: Scientist, Boston/Cambridge
# Filters: Biotechnology, PhD, Full-time
# Frequency: Weekly email
# Status: active
# Last reviewed: YYYY-MM-DD
#
# --- Indeed ---
# Search 1: "Scientist PhD biochemistry" Cambridge MA 25mi
# Search 2: "Scientist PhD genomics CRISPR" Cambridge MA 25mi
# Frequency: Daily email
# Status: active
# Last reviewed: YYYY-MM-DD
OALERTS
        echo "  Created: alerts/other-alerts.txt"
    fi

    if [ ! -f "${JOB_ALERTS}/perplexity-prompts.txt" ]; then
        cat > "${JOB_ALERTS}/perplexity-prompts.txt" << 'PPROMPTS'
# perplexity-prompts.txt -- AI-assisted market intelligence prompts
# =================================================================
# Run these manually in Perplexity, Claude, or similar tools.
# They are not automated -- you copy-paste and read the output.
#
# PURPOSE: Job boards show you what's posted. These prompts
# show you what's about to be posted. Funding rounds, expansions,
# and leadership hires are leading indicators of scientist-level
# hiring 2-8 weeks later.
#
# CADENCE:
#   Weekly (every Monday, 2 min): market scan
#   Biweekly: industry temperature check
#   Monthly (rotate): deep dives by topic
#   Ad hoc: before networking events or interviews
#
# STRATEGY: Don't just read the output -- act on it. If a
# company raised a round, check their careers page. If a
# company announced layoffs, remove them from your active
# monitoring. If a new startup launched in your space, add
# them to your bookmark file.
#
# MAINTENANCE: Update prompts when your target geography,
# skill areas, or companies change. Add new prompts when
# you discover useful angles. Remove prompts that
# consistently produce nothing actionable.
#
# FORMAT: One prompt per block. Include the cadence, the
# full prompt text, and notes on what to do with the output.
#
# EXAMPLE:
# --- Weekly market scan (every Monday) ---
# Prompt:
# What Boston/Cambridge biotech companies announced new
# funding rounds, expansions, or significant hires in the
# past 7 days? Focus on companies working in [your areas].
# List company name, what happened, and whether they appear
# to be hiring.
#
# Action: Check careers pages of any company mentioned.
# Add new companies to bookmarks if relevant.
PPROMPTS
        echo "  Created: alerts/perplexity-prompts.txt"
    fi

    # Create starter portal-ready-info.txt if it doesn't exist.
    # PURPOSE: A single file you can copy-paste from when filling
    # out job application portals. Every portal asks for the same
    # info (name, education, references, skills). Having it in one
    # place eliminates re-typing and ensures consistency.
    #
    # MINDSET: Think of this as your "application clipboard." When
    # a portal asks for your LinkedIn URL or reference phone number,
    # you open this file and copy the answer. The goal is zero
    # recall -- everything is written down.
    if [ ! -f "${JOB_PORTAL}" ]; then
        cat > "${JOB_PORTAL}" << 'PORTAL'
# portal-ready-info.txt
# =====================
# PURPOSE: Copy-paste source for job application portals.
# Every portal asks for the same fields. Keep this file
# current so you never have to recall info mid-application.
#
# HOW TO USE: Run `jobinfo` to print this to terminal.
# Copy the fields you need into the portal form.
#
# MAINTENANCE: Update whenever info changes (new reference
# confirmed, new phone number, salary expectations shift).
# Run `jobinfoedit` to open in your editor.
#
# Fill in every section below. Remove these instructions
# once the file is populated.

=== PERSONAL ===
Name: 
Email: 
Phone: 
Address: 
LinkedIn: 
GitHub: 
# Add other profile URLs as needed (ORCID, portfolio, etc.)

=== WORK AUTHORIZATION ===
# Most US portals ask: "Are you authorized to work in the US?"
# and "Will you now or in the future require sponsorship?"
US Work Authorized: 
Require sponsorship: 

=== EDUCATION ===
# Format: Degree, Institution, Year
# List highest degree first. Portals often want these as
# separate fields -- having them pre-formatted saves time.

=== START DATE ===
# When can you start? Use a specific month/year or
# "within 2 weeks of offer" if flexible.

=== SALARY ===
# Your target range. Some portals require a number.
# Research the market range for your target roles and
# geography. Adjust per role level (Scientist I vs II).
Expected range: 

=== REFERENCES ===
# Most portals ask for 2-3 references with full contact info.
# IMPORTANT: Confirm with each person BEFORE listing them.
# Include: name, title, organization, email, phone, relationship.
#
# 1. [Primary reference -- typically your advisor/PI]
#    Name: 
#    Title: 
#    Organization: 
#    Email: 
#    Phone: 
#    Relationship: 
#
# 2. [Second reference -- different context, e.g., internship]
#    Name: 
#    Title: 
#    Organization: 
#    Email: 
#    Phone: 
#    Relationship: 
#
# 3. [Third reference -- committee member, collaborator, etc.]
#    Name: 
#    Title: 
#    Organization: 
#    Email: 
#    Phone: 
#    Relationship: 

=== MASTER SKILLS KEYWORDS ===
# PURPOSE: A comprehensive list of your skills phrased in
# multiple ways. Portals often have a free-text "skills" field
# that feeds keyword-matching algorithms. Copy the version
# that echoes the posting language.
#
# HOW TO BUILD: List every technique, tool, method, platform,
# and language you can honestly claim. Include both the full
# name and common abbreviation (e.g., "chromatin
# immunoprecipitation" and "ChIP-seq"). Group by category
# for easy scanning.
#
# MAINTENANCE: Add new skills as you learn them. When a posting
# uses a term you recognize but haven't listed, add the
# posting's phrasing as an alias.
PORTAL
        echo "  Created: portal-ready-info.txt"
        echo "    ACTION REQUIRED: Fill in all sections."
        echo "    Edit with: jobinfoedit"
    fi

    # Create starter bookmark file if it doesn't exist.
    # PURPOSE: A flat list of career page URLs that jobcheck opens
    # in your browser. Organizing by tier/category lets you do
    # partial scans (e.g., just Tier 1 on busy days).
    #
    # MINDSET: Your bookmark file is your fishing net. Cast it
    # wide initially, then prune URLs that never produce relevant
    # postings. Add new companies as you discover them through
    # networking, alerts, or conference conversations.
    #
    # HOW TO FIND URLS: Go to a company's website, find their
    # "Careers" or "Join Us" page, and look for the job board URL.
    # Common platforms: Workday (myworkdayjobs.com), Greenhouse
    # (greenhouse.io), Lever (lever.co), Workable (workable.com),
    # Avature, Rippling (rippling.com). The direct board URL is
    # better than the company's marketing careers page because it
    # loads faster and shows actual postings.
    #
    # MAINTENANCE: URLs go stale (companies switch platforms,
    # startups shut down). If jobcheck opens a dead page, update
    # or remove it. Check quarterly.
    if [ ! -f "${JOB_BOOKMARKS}/career_pages.txt" ]; then
        cat > "${JOB_BOOKMARKS}/career_pages.txt" << 'BOOKMARKS'
# career_pages.txt -- Career page URLs for batch browsing
# ===========================================================
# One URL per line. Lines starting with # are comments.
# Blank lines are ignored.
#
# Edit with: jobbookmarkedit
# Open all with: jobcheck
# Open specific file with: jobcheck <filename> [batch-size]
#
# ORGANIZATION SUGGESTIONS:
# Group URLs by priority tier so you can scan the most
# important companies first. Suggested categories:
#
#   TIER 1 -- Companies you'd accept an offer from tomorrow.
#   Check every Monday and Thursday.
#
#   TIER 2 -- Strong interest but not top choice.
#   Check weekly.
#
#   SECONDARY TRACK -- Different role types (e.g., application
#   scientist, staff scientist). Check biweekly.
#
#   AGGREGATORS -- Sites that collect postings from many
#   companies (BioSpace, MassBio, Indeed). Check weekly.
#   These have lag vs. direct career pages.
#
#   EXPLORATORY -- Interesting leads, networking-sourced,
#   long shots. Check when time permits.
#
# HOW TO FIND THE RIGHT URL:
#   - Workday portals: look for myworkdayjobs.com in the URL
#   - Greenhouse: job-boards.greenhouse.io/<company>
#   - Lever: jobs.lever.co/<company>
#   - Workable: apply.workable.com/<company>
#   - Some companies embed listings on their own /careers page
#
# Add your URLs below. Example format:
#
# # --- TIER 1: Primary targets ---
# https://apply.workable.com/example-company/
# https://example.wd5.myworkdayjobs.com/en-US/Careers
#
# # --- TIER 2 ---
# https://job-boards.greenhouse.io/anothercompany
#
# # --- AGGREGATORS ---
# https://careers.massbio.org/

BOOKMARKS
        echo "  Created: bookmarks/career_pages.txt"
        echo "    ACTION REQUIRED: Add your target company career page URLs."
        echo "    Edit with: jobbookmarkedit"
    fi

    # Create tracker with header if it doesn't exist.
    if [ ! -f "${JOB_TRACKER}" ]; then
        printf "Company\tRole\tDate\tBucket\tStatus\tFollow-up\n" > "${JOB_TRACKER}"
        echo "  Created: tracker.tsv"
    fi

    # Remind about prompt file.
    if [ ! -f "${JOB_PROMPTS}/${JOB_DEFAULT_PROMPT}" ]; then
        echo ""
        echo "  ACTION REQUIRED: No prompt file found."
        echo "  Place your prompt template at:"
        echo "    ${JOB_PROMPTS}/${JOB_DEFAULT_PROMPT}"
        echo "  Or create one with: jobpromptedit"
    fi

    echo ""
    echo "Directory structure:"
    echo "  CONFIG (kbd, version-controlled):"
    echo "  ${JOB_CONFIG_DIR}/"
    echo "  |-- prompts/            $(ls "${JOB_PROMPTS}" 2>/dev/null | wc -l) prompt(s)"
    echo "  |-- bookmarks/          $(ls "${JOB_BOOKMARKS}" 2>/dev/null | wc -l) file(s)"
    echo "  |-- alerts/             $(ls "${JOB_ALERTS}" 2>/dev/null | wc -l) file(s)"
    echo "  \-- portal-ready-info.txt"
    echo ""
    echo "  DATA (Dropbox):"
    echo "  ${JOB_DATA_DIR}/"
    echo "  |-- postings/           $(ls "${JOB_POSTINGS}" 2>/dev/null | wc -l) posting(s)"
    echo "  \-- tracker.tsv         $(( $(wc -l < "${JOB_TRACKER}" 2>/dev/null || echo 1) - 1 )) application(s)"
    echo ""
    echo "Run 'jobhelp' for available commands."
}

# ------------------------------------------------------------------
# INTERNAL HELPERS
# ------------------------------------------------------------------
# Prefixed with _ to signal they are not user-facing commands.
# No abstraction layers -- each helper does exactly one thing.

# _job_assert_dir: Check that a directory exists. Print a
# contextual error message if not. Returns 1 on failure.
_job_assert_dir() {
    local dir="$1"
    local name="$2"  # Human-readable name for error message.
    if [ ! -d "${dir}" ]; then
        echo "ERROR: ${name} directory not found: ${dir}" >&2
        echo "  Run 'jobinit' to create the directory structure." >&2
        return 1
    fi
    return 0
}

# _job_assert_file: Check that a file exists. Print a contextual
# error message if not. Returns 1 on failure.
_job_assert_file() {
    local file="$1"
    local name="$2"  # Human-readable name for error message.
    if [ ! -f "${file}" ]; then
        echo "ERROR: ${name} not found: ${file}" >&2
        echo "  Run 'jobinit' to create starter files." >&2
        return 1
    fi
    return 0
}

# _job_assert_writable: Check that a path is writable.
_job_assert_writable() {
    local path="$1"
    local name="$2"
    if [ ! -w "${path}" ]; then
        echo "ERROR: ${name} is not writable: ${path}" >&2
        echo "  Check file permissions and Dropbox sync status." >&2
        return 1
    fi
    return 0
}

# _job_get_editor: Return the editor command to use.
# Checks EDITOR, VISUAL, then falls back to common editors.
_job_get_editor() {
    if [ -n "${EDITOR}" ] && command -v "${EDITOR}" > /dev/null 2>&1; then
        echo "${EDITOR}"
    elif [ -n "${VISUAL}" ] && command -v "${VISUAL}" > /dev/null 2>&1; then
        echo "${VISUAL}"
    elif command -v vim > /dev/null 2>&1; then
        echo "vim"
    elif command -v nano > /dev/null 2>&1; then
        echo "nano"
    elif command -v vi > /dev/null 2>&1; then
        echo "vi"
    else
        echo "ERROR: No text editor found." >&2
        echo "  Set EDITOR in your bashrc (e.g., export EDITOR=vim)" >&2
        return 1
    fi
}

# _job_open_url: Open a URL in the default Windows/Linux browser.
_job_open_url() {
    local url="$1"
    if command -v wslview > /dev/null 2>&1; then
        wslview "${url}" 2>/dev/null &
    elif command -v xdg-open > /dev/null 2>&1; then
        xdg-open "${url}" 2>/dev/null &
    else
        # Last resort: print the URL so the user can copy it.
        echo "  No browser opener found. Copy this URL:" >&2
        echo "  ${url}" >&2
    fi
}

# _job_read_urls: Read URLs from a bookmark file.
# Strips comment lines (# ...) and blank lines.
# Arg 1: filename (relative to $JOB_BOOKMARKS/).
_job_read_urls() {
    local file="${JOB_BOOKMARKS}/$1"
    _job_assert_file "${file}" "Bookmark file '$1'" || return 1

    local urls
    urls=$(grep -v '^\s*#' "${file}" | grep -v '^\s*$')

    if [ -z "${urls}" ]; then
        echo "WARNING: Bookmark file '$1' contains no URLs." >&2
        echo "  Edit with: jobbookmarkedit $1" >&2
        return 1
    fi

    echo "${urls}"
}

# _job_sanitize_name: Lowercase, replace spaces with hyphens,
# strip characters that are dangerous in filenames.
# Used to normalize company/role names for directory creation.
_job_sanitize_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9_-'
}

# ------------------------------------------------------------------
# NAVIGATION
# ------------------------------------------------------------------

# jobcd  -> kbd config root (alerts/bookmarks/prompts/portal info)
# jobcddata -> Dropbox data root (postings/tracker)
alias jobcd='cd "${JOB_CONFIG_DIR}" && pwd'
alias jobcddata='cd "${JOB_DATA_DIR}" && pwd'

# List recent posting directories, most recent first.
# Shows directory names only (not contents).
alias jobls='ls -dt "${JOB_POSTINGS}"/*/ 2>/dev/null | head -20 | xargs -I{} basename {} || echo "No postings yet. Use jobsave to create one."'

# ------------------------------------------------------------------
# PORTAL INFO
# ------------------------------------------------------------------

# Print portal-ready info to terminal for copy-pasting.
jobinfo() {
    _job_assert_file "${JOB_PORTAL}" "Portal info" || return 1
    cat "${JOB_PORTAL}"
}

# Edit portal-ready info.
jobinfoedit() {
    _job_assert_file "${JOB_PORTAL}" "Portal info" || return 1
    local editor
    editor=$(_job_get_editor) || return 1
    ${editor} "${JOB_PORTAL}"
}

# ------------------------------------------------------------------
# PROMPT MANAGEMENT
# ------------------------------------------------------------------

# jobclip [prompt-name]
# Copy a prompt file to the clipboard, ready to paste into Claude.
# Defaults to $JOB_DEFAULT_PROMPT (industry.txt).
# After pasting, you add the job posting text at the end.
jobclip() {
    _job_assert_dir "${JOB_PROMPTS}" "Prompts" || return 1

    local prompt_name="${1:-${JOB_DEFAULT_PROMPT}}"
    local prompt_file="${JOB_PROMPTS}/${prompt_name}"

    if [ ! -f "${prompt_file}" ]; then
        echo "ERROR: Prompt file not found: ${prompt_name}" >&2
        echo "Available prompts:" >&2
        ls -1 "${JOB_PROMPTS}/" 2>/dev/null >&2
        if [ "$(ls -1 "${JOB_PROMPTS}/" 2>/dev/null | wc -l)" -eq 0 ]; then
            echo "  (none -- create one with jobpromptedit)" >&2
        fi
        return 1
    fi

    if command -v clip.exe > /dev/null 2>&1; then
        cat "${prompt_file}" | clip.exe
        local line_count
        line_count=$(wc -l < "${prompt_file}")
        echo "Copied to clipboard: ${prompt_name} (${line_count} lines)"
        echo ""
        echo "Next steps:"
        echo "  1. Paste into Claude"
        echo "  2. Add the job posting text at the end"
        echo "  3. Send and review the tailored outputs"
    else
        echo "WARNING: clip.exe not available (not in WSL?)." >&2
        echo "Printing prompt to terminal instead. Copy manually." >&2
        echo "---" >&2
        cat "${prompt_file}"
    fi
}

# List available prompt files.
jobprompts() {
    _job_assert_dir "${JOB_PROMPTS}" "Prompts" || return 1
    echo "Available prompts (default: ${JOB_DEFAULT_PROMPT}):"
    ls -1 "${JOB_PROMPTS}/" 2>/dev/null
    if [ "$(ls -1 "${JOB_PROMPTS}/" 2>/dev/null | wc -l)" -eq 0 ]; then
        echo "  (none yet -- create one with jobpromptedit)"
    fi
}

# Edit a prompt file. Creates the file if it doesn't exist.
# Usage: jobpromptedit [prompt-name]
jobpromptedit() {
    _job_assert_dir "${JOB_PROMPTS}" "Prompts" || return 1
    local prompt_name="${1:-${JOB_DEFAULT_PROMPT}}"
    local prompt_file="${JOB_PROMPTS}/${prompt_name}"
    local editor
    editor=$(_job_get_editor) || return 1

    if [ ! -f "${prompt_file}" ]; then
        echo "Creating new prompt: ${prompt_name}"
    fi
    ${editor} "${prompt_file}"
}

# ------------------------------------------------------------------
# POSTING MANAGEMENT
# ------------------------------------------------------------------

# jobsave <company> <role-description>
# Creates a dated directory under postings/ with a posting.txt
# stub, then opens it for pasting the job posting text.
#
# The directory can hold additional files: tailored resume,
# cover letter, confirmation screenshot, notes, etc.
#
# Company and role are sanitized: lowercased, spaces to hyphens,
# special characters stripped. This prevents path issues.
#
# Example: jobsave beam scientist-crispr-screening
# Creates: postings/2026-06-05_beam_scientist-crispr-screening/
jobsave() {
    _job_assert_dir "${JOB_POSTINGS}" "Postings" || return 1

    if [ -z "$1" ] || [ -z "$2" ]; then
        {
            echo "Usage: jobsave <company> <role-description>"
            echo ""
            echo "Examples:"
            echo "  jobsave beam scientist-crispr-screening"
            echo "  jobsave foghorn scientist-protein-biochem"
            echo "  jobsave broad staff-scientist-genomics"
            echo ""
            echo "Tip: Keep role-description short and hyphenated."
        } >&2
        return 1
    fi

    local company
    company=$(_job_sanitize_name "$1")
    local role
    role=$(_job_sanitize_name "$2")
    local today
    today=$(date +%Y-%m-%d)
    local dirname="${today}_${company}_${role}"
    local dirpath="${JOB_POSTINGS}/${dirname}"
    local posting_file="${dirpath}/posting.txt"

    mkdir -p "${dirpath}" 2>/dev/null
    if [ ! -d "${dirpath}" ]; then
        echo "ERROR: Could not create directory: ${dirpath}" >&2
        echo "  Check disk space and permissions." >&2
        return 1
    fi

    if [ ! -f "${posting_file}" ]; then
        cat > "${posting_file}" << EOF
# ===================================================
# POSTING: ${company} -- ${role}
# ===================================================
# Date found:    ${today}
# Bucket:        [1-6, fill in after analysis]
# URL:           [paste the posting URL here]
# Salary range:  [from posting, if listed]
# Portal:        [workday/greenhouse/lever/other]
# Req ID:        [if visible, e.g., REQ-28437]
# Cover letter:  [yes/no -- does the portal accept one?]
# Status:        saved
# Notes:         
# ===================================================
# Paste the full posting text below this line.
# Include: title, responsibilities, requirements,
# preferred qualifications, salary, benefits, etc.
# ===================================================

EOF
        echo "Created: ${dirname}/"
        echo "  Paste the posting text into the file that opens."
    else
        echo "Already exists: ${dirname}/"
        echo "  Opening for editing."
    fi

    local editor
    editor=$(_job_get_editor) || return 1
    ${editor} "${posting_file}"
}

# jobopen <partial-name>
# Open the most recent posting directory matching a partial name.
# Useful when you want to revisit a posting or add files to it.
# Example: jobopen vertex  -> opens most recent vertex posting
jobopen() {
    _job_assert_dir "${JOB_POSTINGS}" "Postings" || return 1

    if [ -z "$1" ]; then
        {
            echo "Usage: jobopen <partial-name>"
            echo "  Opens the most recent posting matching the name."
            echo ""
            echo "Examples:"
            echo "  jobopen vertex"
            echo "  jobopen beam"
            echo "  jobopen 2026-06-05"
            echo ""
            echo "Recent postings:"
            ls -dt "${JOB_POSTINGS}"/*/ 2>/dev/null | head -10 | while read -r d; do
                basename "${d}"
            done
            if [ "$(ls -d "${JOB_POSTINGS}"/*/ 2>/dev/null | wc -l)" -eq 0 ]; then
                echo "  (none yet -- use jobsave to create one)"
            fi
        } >&2
        return 1
    fi

    # Find most recent directory matching the partial name.
    local match
    match=$(ls -dt "${JOB_POSTINGS}"/*"$1"* 2>/dev/null | head -1)

    if [ -z "${match}" ]; then
        echo "No posting found matching: $1" >&2
        echo "Available postings:" >&2
        ls -dt "${JOB_POSTINGS}"/*/ 2>/dev/null | head -10 | while read -r d; do
            echo "  $(basename "${d}")"
        done >&2
        return 1
    fi

    local posting_file="${match}/posting.txt"
    echo "Opening: $(basename "${match}")"

    # List other files in the directory so user remembers what's there.
    local -a other_files=()
    local candidate_file
    for candidate_file in "${match}"/*; do
        [[ -e "$candidate_file" ]] || continue
        [[ "${candidate_file##*/}" == "posting.txt" ]] && continue
        other_files+=("${candidate_file##*/}")
    done
    if [[ "${#other_files[@]}" -gt 0 ]]; then
        echo "Also in this directory:"
        printf '  %s\n' "${other_files[@]}"
    fi

    local editor
    editor=$(_job_get_editor) || return 1

    if [ -f "${posting_file}" ]; then
        ${editor} "${posting_file}"
    else
        echo "WARNING: posting.txt not found in ${match}." >&2
        echo "  Opening directory listing instead." >&2
        ls -la "${match}"
    fi
}

# jobdir <partial-name>
# Print the full path of a posting directory (for cd-ing or
# copying files into). Does not open anything.
jobdir() {
    _job_assert_dir "${JOB_POSTINGS}" "Postings" || return 1

    if [ -z "$1" ]; then
        {
            echo "Usage: jobdir <partial-name>"
            echo "  Prints the path to cd into or copy files to."
            echo "  Example: cd \$(jobdir vertex)"
        } >&2
        return 1
    fi

    local match
    match=$(ls -dt "${JOB_POSTINGS}"/*"$1"* 2>/dev/null | head -1)

    if [ -z "${match}" ]; then
        echo "No posting found matching: $1" >&2
        return 1
    fi

    echo "${match}"
}

# ------------------------------------------------------------------
# TRACKER
# ------------------------------------------------------------------

# joblog <company> <role> <bucket>
# Append an application record to the TSV tracker.
# Bucket: 1-6. Status defaults to "applied".
# Follow-up date: automatically set to 14 days from today.
#
# Creates the tracker with a header row if it doesn't exist.
#
# Example: joblog vertex 'Research Scientist, Structural Bio' 1
joblog() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        {
            echo "Usage: joblog <company> <role> <bucket>"
            echo ""
            echo "  company  Company name (e.g., vertex, beam, foghorn)"
            echo "  role     Full role title in quotes"
            echo "  bucket   1-6 (see bucket definitions in jobhelp)"
            echo ""
            echo "Example:"
            echo "  joblog vertex 'Research Scientist, Structural Bio' 1"
        } >&2
        return 1
    fi

    # Validate bucket is 1-6.
    local bucket="$3"
    if ! echo "${bucket}" | grep -qE '^[1-6]$'; then
        echo "ERROR: Bucket must be 1-6. Got: ${bucket}" >&2
        echo "  1 = Protein biochemistry / mechanistic" >&2
        echo "  2 = Genetics / screening / functional genomics" >&2
        echo "  3 = Hybrid biochem + genomics (strongest fit)" >&2
        echo "  4 = Science-adjacent / application scientist" >&2
        echo "  5 = Non-research PhD (field app sci, tech support," >&2
        echo "      QC scientist, process development scientist)" >&2
        echo "  6 = Strategic / non-bench (PM, sci writer, MSL)" >&2
        return 1
    fi

    local company="$1"
    local role="$2"
    local today
    today=$(date +%Y-%m-%d)

    # Calculate follow-up date. GNU date (-d) and BSD date (-v)
    # have different syntax; try both. Fall back to "TBD".
    local followup
    followup=$(date -d "+14 days" +%Y-%m-%d 2>/dev/null \
        || date -v+14d +%Y-%m-%d 2>/dev/null \
        || echo "TBD")

    # Create tracker with header if it doesn't exist.
    if [ ! -f "${JOB_TRACKER}" ]; then
        printf "Company\tRole\tDate\tBucket\tStatus\tFollow-up\n" \
            > "${JOB_TRACKER}"
        echo "Created tracker: tracker.tsv"
    fi

    _job_assert_writable "${JOB_TRACKER}" "Tracker" || return 1

    # Guard the append: a failed write (full disk, Dropbox perms,
    # lost mount between the writable-check and here) must NOT be
    # followed by a "Logged" confirmation. Silent-bad-state class:
    # without this, the count below re-reads the file, looks
    # plausible, and you trust a record that was never written.
    if ! printf "%s\t%s\t%s\t%s\tapplied\t%s\n" \
        "${company}" "${role}" "${today}" "${bucket}" "${followup}" \
        >> "${JOB_TRACKER}"; then
        echo "ERROR: Failed to write to tracker: ${JOB_TRACKER}" >&2
        echo "  Application was NOT logged. Check disk space and" >&2
        echo "  Dropbox sync, then re-run." >&2
        return 1
    fi

    # Confirm with a count so user knows the log is growing.
    local total
    total=$(( $(wc -l < "${JOB_TRACKER}") - 1 ))
    echo "Logged (#${total}): ${company} | ${role} | B${bucket} | Follow-up: ${followup}"
}

# Print tracker as an aligned table.
jobstatus() {
    _job_assert_file "${JOB_TRACKER}" "Tracker" || return 1

    local total
    total=$(( $(wc -l < "${JOB_TRACKER}") - 1 ))

    if [ "${total}" -le 0 ]; then
        echo "No applications logged yet."
        echo "  Use 'joblog <company> <role> <bucket>' after submitting."
        return 0
    fi

    echo "Applications: ${total}"
    echo ""
    column -t -s "$(printf '\t')" "${JOB_TRACKER}"
}

# Open tracker in editor for manual status updates.
jobtrackedit() {
    _job_assert_file "${JOB_TRACKER}" "Tracker" || return 1
    local editor
    editor=$(_job_get_editor) || return 1
    ${editor} "${JOB_TRACKER}"
}

# jobdue: Show applications with follow-up dates that are today
# or overdue. Useful for weekly check-ins.
jobdue() {
    _job_assert_file "${JOB_TRACKER}" "Tracker" || return 1

    local today
    today=$(date +%Y-%m-%d)
    local header
    header=$(head -1 "${JOB_TRACKER}")

    # Find rows where the follow-up date (field 6) is <= today.
    # Uses string comparison which works for YYYY-MM-DD format.
    local due_rows
    due_rows=$(awk -F'\t' -v today="${today}" \
        'NR > 1 && $6 != "TBD" && $6 <= today && $5 == "applied"' \
        "${JOB_TRACKER}")

    if [ -z "${due_rows}" ]; then
        echo "No follow-ups due. Next check: $(awk -F'\t' \
            'NR > 1 && $6 != "TBD" && $5 == "applied" { print $6 }' \
            "${JOB_TRACKER}" | sort | head -1)"
        return 0
    fi

    echo "Follow-ups due (as of ${today}):"
    echo ""
    printf "%s\n%s\n" "${header}" "${due_rows}" \
        | column -t -s "$(printf '\t')"
}

# ------------------------------------------------------------------
# BOOKMARK-BASED BROWSING
# ------------------------------------------------------------------

# jobcheck [bookmark-file] [batch-size]
# Open career page URLs from a bookmark file in your browser.
# Defaults: career_pages.txt, opens 5 at a time.
# Pauses between batches so your browser doesn't choke on 20+
# tabs opening simultaneously.
#
# Example:
#   jobcheck                     # default file, 5 per batch
#   jobcheck career_pages.txt 8  # custom batch size
#   jobcheck aggregators.txt     # different bookmark file
jobcheck() {
    _job_assert_dir "${JOB_BOOKMARKS}" "Bookmarks" || return 1

    local bookmark_file="${1:-career_pages.txt}"
    local batch_size="${2:-5}"

    # Validate batch_size is a positive integer.
    if ! echo "${batch_size}" | grep -qE '^[0-9]+$' || [ "${batch_size}" -eq 0 ]; then
        echo "ERROR: Batch size must be a positive integer. Got: ${batch_size}" >&2
        return 1
    fi

    # Read URLs into an array.
    local url_text
    url_text=$(_job_read_urls "${bookmark_file}") || return 1

    local urls=()
    while IFS= read -r line; do
        urls+=("${line}")
    done <<< "${url_text}"

    local total=${#urls[@]}
    if [ "${total}" -eq 0 ]; then
        echo "No URLs found in ${bookmark_file}."
        return 1
    fi

    echo "Opening ${total} career pages from ${bookmark_file}"
    echo "(${batch_size} at a time -- press Enter between batches)"
    echo ""

    local count=0
    for url in "${urls[@]}"; do
        _job_open_url "${url}"
        count=$((count + 1))

        # Show which URL was opened (truncated for readability).
        local display_url
        display_url=$(echo "${url}" | cut -c1-60)
        echo "  [${count}/${total}] ${display_url}..."

        # Pause between batches. Skip pause after the last URL.
        if [ $((count % batch_size)) -eq 0 ] && [ ${count} -lt ${total} ]; then
            echo ""
            echo "  --- Batch ${count}/${total} done. Press Enter for next batch ---"
            read -r
        fi

        # Small delay between individual opens to avoid race conditions.
        sleep 0.5
    done

    echo ""
    echo "Done. Opened ${count} pages."
    echo "If something fits: jobsave <company> <role>"
}

# List available bookmark files.
jobbookmarks() {
    _job_assert_dir "${JOB_BOOKMARKS}" "Bookmarks" || return 1
    echo "Available bookmark files:"
    ls -1 "${JOB_BOOKMARKS}/" 2>/dev/null
    if [ "$(ls -1 "${JOB_BOOKMARKS}/" 2>/dev/null | wc -l)" -eq 0 ]; then
        echo "  (none -- run jobinit to create the default)"
    fi
}

# Edit a bookmark file.
jobbookmarkedit() {
    _job_assert_dir "${JOB_BOOKMARKS}" "Bookmarks" || return 1
    local file="${1:-career_pages.txt}"
    local editor
    editor=$(_job_get_editor) || return 1
    ${editor} "${JOB_BOOKMARKS}/${file}"
}

# ------------------------------------------------------------------
# ALERT MANAGEMENT
# ------------------------------------------------------------------

# jobalerts: List alert documentation files and their last-modified
# dates. Helps you remember what's configured and when you last
# reviewed it.
jobalerts() {
    _job_assert_dir "${JOB_ALERTS}" "Alerts" || return 1

    local count
    count=$(ls -1 "${JOB_ALERTS}" 2>/dev/null | wc -l)

    if [ "${count}" -eq 0 ]; then
        echo "No alert files found. Run jobinit to create templates."
        return 0
    fi

    echo "Alert documentation files:"
    echo ""
    ls -lt "${JOB_ALERTS}"/ 2>/dev/null | tail -n +2 | while read -r line; do
        echo "  ${line}"
    done
    echo ""
    echo "Edit with: jobalertedit <filename>"
    echo "Files: google-alerts.txt, linkedin-alerts.txt,"
    echo "       other-alerts.txt, perplexity-prompts.txt"
}

# jobalertedit [filename]
# Edit an alert documentation file. Defaults to google-alerts.txt.
jobalertedit() {
    _job_assert_dir "${JOB_ALERTS}" "Alerts" || return 1
    local file="${1:-google-alerts.txt}"
    local filepath="${JOB_ALERTS}/${file}"
    local editor
    editor=$(_job_get_editor) || return 1

    if [ ! -f "${filepath}" ]; then
        echo "Alert file not found: ${file}" >&2
        echo "Available files:" >&2
        ls -1 "${JOB_ALERTS}/" 2>/dev/null >&2
        if [ "$(ls -1 "${JOB_ALERTS}/" 2>/dev/null | wc -l)" -eq 0 ]; then
            echo "  (none -- run jobinit to create templates)" >&2
        fi
        return 1
    fi

    ${editor} "${filepath}"
}

# ------------------------------------------------------------------
# DIAGNOSTICS
# ------------------------------------------------------------------

# jobdiag: Print a diagnostic summary of the job search setup.
# Useful when something feels broken or on a new machine.
jobdiag() {
    echo "Job Search Pipeline Diagnostics"
    echo "================================"
    echo ""
    echo "Environment:"
    echo "  MC_WINDOWS_USER:  ${MC_WINDOWS_USER:-NOT SET}"
    echo "  EDITOR:           ${EDITOR:-not set (will auto-detect)}"
    echo "  Detected editor:  $(_job_get_editor 2>/dev/null || echo 'NONE FOUND')"
    echo "  clip.exe:         $(command -v clip.exe > /dev/null 2>&1 && echo 'available' || echo 'NOT FOUND')"
    echo "  wslview:          $(command -v wslview > /dev/null 2>&1 && echo 'available' || echo 'NOT FOUND')"
    echo "  bash version:     ${BASH_VERSION}"
    echo ""
    echo "Directories:"
    echo "  Config root (kbd):  $([ -d "${JOB_CONFIG_DIR}" ] && echo 'OK' || echo 'MISSING') -- ${JOB_CONFIG_DIR}"
    echo "  Data root (Dropbox):$([ -d "${JOB_DATA_DIR}" ] && echo ' OK' || echo ' MISSING') -- ${JOB_DATA_DIR}"
    echo "  Prompts:    $([ -d "${JOB_PROMPTS}" ] && echo 'OK' || echo 'MISSING')"
    echo "  Bookmarks:  $([ -d "${JOB_BOOKMARKS}" ] && echo 'OK' || echo 'MISSING')"
    echo "  Alerts:     $([ -d "${JOB_ALERTS}" ] && echo 'OK' || echo 'MISSING')"
    echo "  Postings:   $([ -d "${JOB_POSTINGS}" ] && echo 'OK' || echo 'MISSING')"
    echo ""
    echo "Files:"
    echo "  Portal info:     $([ -f "${JOB_PORTAL}" ] && echo 'OK' || echo 'MISSING')"
    echo "  Tracker:         $([ -f "${JOB_TRACKER}" ] && echo 'OK' || echo 'MISSING')"
    echo "  Default prompt:  $([ -f "${JOB_PROMPTS}/${JOB_DEFAULT_PROMPT}" ] && echo 'OK' || echo 'MISSING') (${JOB_DEFAULT_PROMPT})"
    echo "  Bookmark file:   $([ -f "${JOB_BOOKMARKS}/career_pages.txt" ] && echo 'OK' || echo 'MISSING')"
    echo ""
    echo "Counts:"
    echo "  Postings saved:  $(ls -d "${JOB_POSTINGS}"/*/ 2>/dev/null | wc -l)"
    echo "  Prompts:         $(ls "${JOB_PROMPTS}" 2>/dev/null | wc -l)"
    echo "  Bookmark files:  $(ls "${JOB_BOOKMARKS}" 2>/dev/null | wc -l)"
    echo "  Alert files:     $(ls "${JOB_ALERTS}" 2>/dev/null | wc -l)"
    echo "  Applications:    $(( $(wc -l < "${JOB_TRACKER}" 2>/dev/null || echo 1) - 1 ))"
    echo ""

    # Check for common issues.
    local issues=0
    if [ ! -f "${JOB_PROMPTS}/${JOB_DEFAULT_PROMPT}" ]; then
        echo "ISSUE: Default prompt file missing. Create with: jobpromptedit"
        issues=$((issues + 1))
    fi
    if [ -f "${JOB_PORTAL}" ]; then
        # Detect unfilled portal info: lines like "Name: " with
        # nothing after the colon, or leftover template markers.
        local empty_fields
        empty_fields=$(grep -cE '^(Name|Email|Phone|Address|LinkedIn): *$' \
            "${JOB_PORTAL}" 2>/dev/null || echo 0)
        if [ "${empty_fields}" -gt 0 ]; then
            echo "ISSUE: portal-ready-info.txt has ${empty_fields} unfilled field(s). Edit with: jobinfoedit"
            issues=$((issues + 1))
        fi
    fi
    if [ -f "${JOB_BOOKMARKS}/career_pages.txt" ]; then
        local url_count
        url_count=$(grep -cvE '^\s*#|^\s*$' "${JOB_BOOKMARKS}/career_pages.txt" 2>/dev/null || echo 0)
        if [ "${url_count}" -eq 0 ]; then
            echo "ISSUE: career_pages.txt has no URLs. Edit with: jobbookmarkedit"
            issues=$((issues + 1))
        fi
    fi
    if [ "${issues}" -eq 0 ]; then
        echo "No issues found."
    fi
}

# ------------------------------------------------------------------
# HELP
# ------------------------------------------------------------------

jobhelp() {
    cat << 'HELP'
JOB SEARCH PIPELINE -- COMMAND REFERENCE
========================================

SETUP (run once)
  Prerequisites (before jobinit):
    1. export MC_WINDOWS_USER="YourUsername" in your bashrc/profile
    2. Clone the kbd repo so the config root exists:
         $MC_REPOS_ROOT/usb-repos/kbd/docs/job_applications/
    3. Source this file from bashrc so the commands are available
  Then:
  jobinit             Create directory structure and starter files
  jobdiag             Check setup, find issues
  jobcd               cd to kbd config root
  jobcddata           cd to Dropbox data root

DAILY ROUTINE
  jobcheck [file] [n] Open career pages in browser
                      (default: career_pages.txt, 5 per batch)

APPLYING (the core loop)
  jobsave co role     Create posting dir + open for paste
  jobclip [prompt]    Copy prompt+CV to clipboard
                      (default: industry.txt)
  jobinfo             Print portal-ready info to terminal
  joblog co role N    Log application to tracker (N = bucket 1-6)

REVIEWING
  jobls               List recent postings
  jobopen <name>      Open most recent matching posting
  jobdir <name>       Print posting dir path (for cd or cp)
  jobstatus           Print application tracker as table
  jobdue              Show overdue follow-ups

EDITING
  jobpromptedit [name]  Edit a prompt (default: industry.txt)
  jobprompts            List available prompts
  jobinfoedit           Edit portal-ready info
  jobtrackedit          Edit tracker manually
  jobbookmarkedit [f]   Edit a bookmark file
  jobbookmarks          List bookmark files

ALERTS
  jobalerts             List alert documentation files
  jobalertedit [file]   Edit an alert file
                        (google-alerts.txt, linkedin-alerts.txt,
                        other-alerts.txt, perplexity-prompts.txt)

WORKFLOW EXAMPLE
  1. jobcheck                              # scan career pages
  2. jobsave beam scientist-crispr         # save posting text
  3. jobclip                               # copy prompt to clipboard
  4. [paste into Claude, add posting, iterate on outputs]
  5. [save tailored resume/letter in posting dir]
  6. jobinfo                               # fill portal fields
  7. [submit application]
  8. joblog beam 'Scientist, CRISPR' 2     # log it

DIRECTORY LAYOUT (two roots as of 2026-06-23)
  CONFIG -- kbd repo, version-controlled:
    $MC_REPOS_ROOT/usb-repos/kbd/docs/job_applications/
      prompts/*.txt                  Prompt templates with CV
      bookmarks/*.txt                URL lists for jobcheck
      alerts/*.txt                   Alert configs and prompts
      portal-ready-info.txt          Copy-paste form fields
  DATA -- Dropbox, not committed:
    .../job_applications/
      postings/YYYY-MM-DD_company_role/  One dir per application
        \-- posting.txt              Raw posting + metadata
      tracker.tsv                    Application log (TSV)

BUCKET REFERENCE
  1 = Protein biochemistry / mechanistic
  2 = Genetics / screening / functional genomics
  3 = Hybrid biochem + genomics (strongest fit)
  4 = Science-adjacent / application scientist
  5 = Non-research PhD (field app scientist, technical support
      scientist, QC scientist, process development scientist)
  6 = Strategic / non-bench, DORMANT (product manager, scientific
      writer, MSL -- activate when a posting triggers it)
HELP
}
