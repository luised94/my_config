# bash/

The numbered shell configuration chain. `dotfiles/bashrc.sh` sources every file
matching `[0-9][0-9]_*.sh` in glob (numeric) order, so the two-digit prefix
controls load order. Each file is a plain sourced script (no shebang; a
`# shellcheck shell=bash` directive marks it as bash for the linter).

## Load order and contents

| File | Role |
|------|------|
| `00_config.sh` | All user settings: the `MC_*` arrays and scalars, plus the color palette. The single source of truth. |
| `01_activate.sh` | Applies `00_config`: PATH, aliases, environment variables, history, shell options, prompt, editor/browser selection. |
| `02_wsl.sh` | WSL interop. Detects the Windows user and Dropbox path; exports `MC_WINDOWS_USER` and `MC_DROPBOX_PATH`. Returns early when not on WSL. |
| `03_message.sh` | Thin shim that sources `lib/message.sh` (the `msg_*` engine). See `lib/README.md`. |
| `04_verify.sh` | `mc_verify` (health check of required programs and symlinks, with a success cache) and `mc_reload` (re-source the environment). |
| `06_usb.sh` | Sources the external `usb-sh` repo if present (USB detection for other modules); sets `GPG_TTY`. Degrades gracefully when absent. |
| `07_config_tools.sh` | `mc_config` - inspect settings and their docs (see below). |
| `10_vim_utils.sh` | File utilities: `vimall`, `vimpattern`, `vimconflict`, `vimmodified`, `vimstale`, `vimreverse`, `vimdiff`. |
| `11_git_utils.sh` | Multi-repo git helpers and worktrees: `status_all_repos`, `stash_report`, `pull_all_repos`, `push_all_repos`, `new_worktree`, `remove_worktree`, `rebase_worktrees_on_main`, `prune_merged_branches`. |
| `12_browser.sh` | `view_files` - open files in batches in the system browser (WSL). |
| `13_friction.sh` | Friction log: `friction_log`/`friction_show`/`friction_open`/`friction_archive`/`friction_undo` (aliases `flog`, `fshow`, `fopen`, `farchive`, `fundo`). |
| `14_c_utils.sh` | `cr` - compile and run a C file. |
| `15_job_hunt.sh` | Job-application workflow: the `job*` commands (`jobinit`, `jobinfo`, `jobsave`, `jobstatus`, ...) plus `jobcd`/`jobls` aliases. |
| `99_extensions.sh` | Loads optional user extensions: `mc_extensions_status`, `mc_link_extension`. |

## Settings and the `##` documentation convention

All settings live in `00_config.sh` as `MC_*` variables. A line beginning with
`## ` immediately above a setting documents it (a `# shellcheck` directive may
sit between the doc and the assignment). These docs are machine-readable:

```bash
mc_config list           # all setting names
mc_config get <name>     # live value (arrays: one element per line)
mc_config doc <name>     # the documentation string
mc_config dump           # every setting with type, doc, and value
```

`mc_config` uses namerefs to expand array settings, so it requires **bash
4.3+** (the rest of the chain targets 4.0+).

## Contracts

- **Idempotency.** Every file must be safe to source more than once (via
  `mc_reload`). `scripts/check_double_source.sh` enforces this.
- **Message API.** `msg_info` / `msg_warn` / `msg_error` / `msg_debug` are the
  stable logging interface (defined in `lib/message.sh`). Prefer them over
  ad-hoc `echo`/`printf`.
- **WSL exports.** `MC_WINDOWS_USER` and `MC_DROPBOX_PATH` (from `02_wsl.sh`)
  are the only variables other repositories depend on; treat their names as
  frozen.

## Linting

`scripts/lint.sh` runs `shellcheck -S warning` over the chain plus a non-ASCII
scan; `scripts/check_double_source.sh` verifies re-source idempotency. Both
should exit 0.
