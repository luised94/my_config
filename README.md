# my_config

A personal bash and dotfiles framework for Linux and WSL. Configuration is
declared once in `bash/00_config.sh` and applied by a small, ordered chain of
sourced scripts; a single installer sets up symlinks and verifies the
environment.

## Layout

```
bash/        Numbered configuration chain (see bash/README.md)
lib/         Reusable libraries: message engine, config parser (see lib/README.md)
dotfiles/    Files symlinked into $HOME (bashrc.sh, vimrc.vim, ...)
scripts/     Tooling (lint, idempotency check, and standalone utilities)
docs/        Notes and development-environment guides
bootstrap.sh Installer (see below)
```

`dotfiles/bashrc.sh` is the entry point: it sets `MC_ROOT` and sources
`bash/[0-9][0-9]_*.sh` in order.

## Requirements

- bash 4.3+ (the `mc_config` command uses namerefs; the rest targets 4.0+).
- The programs listed in `MC_REQUIRED_PROGS` (currently `git`, `curl`, `wget`,
  `fzf`, `tput`). `mc_verify` reports any that are missing.

## Install

`bootstrap.sh` reads the single source of truth in `bash/00_config.sh` and sets
the machine up. It is dry-run by default:

```bash
./bootstrap.sh                 # show what would happen (no changes)
./bootstrap.sh --apply         # create MC_SYMLINKS links, then mc_verify --force
./bootstrap.sh --install-git-hook   # add a pre-commit hook that runs the linter
```

`--apply` creates the symlinks declared in `MC_SYMLINKS`, skips missing
sources, never clobbers an existing non-managed target, and finishes with an
authoritative `mc_verify --force`.

## Key commands

- `mc_verify` - check required programs and symlinks (cached; `--force` to rerun).
- `mc_reload` - re-source the environment after edits.
- `mc_config list|get|doc|dump` - inspect settings and their documentation.

Domain command groups (see `bash/README.md` for the full list): `job*`
(job-application workflow), `vim*` (file utilities), the multi-repo git helpers
and worktrees, and `friction_*`/`f*` (friction log).

## Configuration

Edit `bash/00_config.sh`. Each setting is an `MC_*` variable documented by a
`## ` line above it; `mc_config` surfaces those docs. See `bash/README.md` for
the convention and the per-file breakdown, and `lib/README.md` for the message
engine and parser.

## Development

```bash
bash scripts/lint.sh                  # shellcheck (warning severity) + non-ASCII scan
bash scripts/check_double_source.sh   # verify the chain is idempotent on re-source
bash lib/message.test.sh              # message engine tests
```

All three should exit 0. The pre-commit hook installed by
`bootstrap.sh --install-git-hook` runs `scripts/lint.sh`.
