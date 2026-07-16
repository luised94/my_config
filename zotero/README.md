# zotero/

Scripts, templates, and conventions for maintaining a ~60,000-item
Zotero library with linked-file attachments on Windows (development
happens in WSL).

Start here:

- MAINTENANCE_PLAN.md -- decisions, open questions, thread map for the
  ongoing maintenance effort.
- CONVENTIONS.md -- Part A: engineering conventions (script layout,
  safety defaults, scale patterns, JS style). Part B: library
  conventions (tag taxonomy, attachment naming, citation keys).
- handoff/ -- design documents for in-flight work (orphan pipeline,
  incoming-item automation, annotation export).

## Layout

- console_js/ -- scripts for Zotero's Run JavaScript console
  (Tools > Developer > Run JavaScript). The BBT export and citation
  key refresh scripts are the reference implementations of the
  conventions.
- plugin_actions_and_tag_js/ -- Actions & Tags plugin actions, one
  action per .js file. Repository .js files are canonical;
  actions-zotero.yml is an exported backup, refreshed after changes.
- powershell/ -- Windows-side tooling. Backup-ZoteroStorage.ps1 is the
  scaffold for new PS1 tools (validation, dry-run default, marker-file
  drive detection, reconciliation).
- better_notes_templates/ -- Better Notes templates.
- one-time-operations/ -- completed, non-maintained scripts kept for
  reference; each carries a STATUS header.

## Dependencies

- Zotero 7+ (console scripts use IOUtils/PathUtils; version guards
  with tested ceilings live in each script's CONFIG).
- Better BibTeX (bbt_* scripts).
- Actions & Tags (plugin_actions_and_tag_js/).
- Better Notes (better_notes_templates/).
- PowerShell 5+ and robocopy (powershell/).
- Environment: WINDOWS_USER (and Dropbox account name) parameterize
  Windows-side paths; see script headers.

## Usage cadence

- Backup: Backup-ZoteroStorage.ps1 (dry run by default; -Execute to
  copy; -Mirror to also delete extras from the destination).
- Bibliography export: console_js/bbt_export.js (full-library .bib to
  the Zotero data directory; weekly-full state machine).
- Citation key refresh: console_js/bbt_citation_key_refresh.js when
  BBT key format changes or keys drift.
- Path migration: console_js/adjust_attachment_paths.js when the
  linked-attachment base path changes (dry run first).
- Library-scale runs follow the validation ramp: 1000, 5000, 10000,
  full (CONVENTIONS.md A4/A5).

## WSL note

This repository lives in WSL; Zotero runs on Windows and cannot read
WSL paths conveniently. Scripts Zotero must load from disk are copied
manually to a Windows-side folder (MAINTENANCE_PLAN.md Q5 tracks a
better transport as a future feature). Sparse clone of just this
directory:

    git clone --filter=blob:none --sparse <repo-url>
    cd my_config
    git sparse-checkout set zotero
