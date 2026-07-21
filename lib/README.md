# lib/

Reusable, self-contained libraries used by the bash framework. Unlike the
numbered files in `bash/`, these are not sourced automatically by `bashrc`;
they are pulled in explicitly where needed (for example `bash/03_message.sh`
sources `message.sh`).

## message.sh

The message engine: level-filtered, colorized logging. This is the single
source of the public logging API used across the whole framework.

Public functions:

- `msg_error "..."` - level 1
- `msg_warn  "..."` - level 2
- `msg_info  "..."` - level 3
- `msg_debug "..."` - level 4

All four print to **stderr** and are gated by `MC_VERBOSITY` (higher shows
more): a message prints only when `MC_VERBOSITY` is greater than or equal to
its level. Verbosity 5 adds a caller trace. `_msg` is the internal engine; call
the `msg_*` wrappers instead.

Properties:

- **Self-contained.** It defaults `MC_VERBOSITY` to 3 and defines its own color
  palette (only if not already set), so it works when sourced on its own -
  it does not require `00_config.sh` to have run.
- **Idempotent.** A `_MC_LIB_MESSAGE_LOADED` guard makes a second source a
  no-op.
- Carries a `# VERSION:` marker at the top.

Usage:

```bash
source "$MC_ROOT/lib/message.sh"
MC_VERBOSITY=3 msg_info "hello"
```

## message.test.sh

Standalone tests for `message.sh`. Run directly; exits nonzero on any failure:

```bash
bash lib/message.test.sh
```

Covers function existence, verbosity gating, stderr routing, output content,
and the double-source no-op.

## config_inspect.awk

Parser for the `##` settings-documentation convention in `bash/00_config.sh`
(see `bash/README.md`). Emits one tab-separated record per `MC_*` setting:

```
NAME <TAB> TYPE(scalar|array) <TAB> DOC
```

A `# shellcheck` directive sitting between a `##` doc line and its assignment
is tolerated. Values are intentionally not emitted; the `mc_config` command
(`bash/07_config_tools.sh`) reads live values from the sourced environment.

```bash
awk -f lib/config_inspect.awk bash/00_config.sh
```
