# Neovim Config Guide

Personal Neovim config based on kickstart.nvim, refactored into a minimal
2-file core using data-oriented design. This document is the working reference
for modifying, extending, and maintaining the config.

---

## Architecture

```
~/.config/nvim/
  init.lua          Core config: options, keymaps, autocmds, utilities, plugin bootstrap
  lua/plugins.lua   All plugin specs with their configuration data

  lua/disabled/     Dead code holding area - valid Lua, not loaded
                    Re-enable by merging back into the appropriate file

$MC_EXTENSIONS_DIR/ (default: ~/.config/mc_extensions/)
  kbd.lua           Example extension - knowledge base keybindings
  *.lua             Any extension file; loaded after lazy.nvim setup
```

**The 2-file rule.** Everything lives in `init.lua` or `lua/plugins.lua`. A
`require()` to a local module is only valid when a file contains 3 or more
related data tables AND `init.lua` exceeds 400 lines without the split. Never
create `lua/core/`, `lua/utils.lua`, or one-file-per-plugin structures.

---

## init.lua - Section Map

| Section | What goes there |
|---|---|
| `GLOBALS` | `vim.g.*` globals: mapleader, maplocalleader, nerd font flag |
| `OPTIONS` | `vim.opt.*` entries via the `OPTIONS` table |
| `KEYMAPS` | Editor-wide keymaps via the `KEYMAPS` table |
| `CLIPBOARD` | Platform clipboard config (WSL, macOS, etc.) |
| `UTILITIES` | Self-contained tools: SearchQF, runner, etc. |
| `AUTOCMDS` | Global autocommands |
| `COMMANDS` | Global user commands |
| `LAZY BOOTSTRAP` | lazy.nvim install and setup - do not touch |
| `PLUGINS` | `require("lazy").setup(require("plugins"), ...)` |
| `EXTENSIONS` | Extension loader - do not touch |

---

## Adding and Modifying Things

### Options

Add an entry to the `OPTIONS` table. The applicator loop handles everything.

```lua
{ key = "colorcolumn", value = "80" },
{ key = "conceallevel", value = 2 },
```

For options that need special syntax (`:append`, `:prepend`), add a one-liner
after the applicator loop, where `vim.opt.fillchars` is currently set.

### Editor-wide keymaps

Add to the `KEYMAPS` table. `desc` is required; format is `"section: action"`.

```lua
{ mode = "n", lhs = "<leader>x", rhs = some_fn, opts = { desc = "editor: do thing" } },
```

For keymaps that are tightly coupled to a utility (runner, search), add them
inline next to the utility code rather than in the `KEYMAPS` table.

### Autocmds

Add `api.nvim_create_autocmd(...)` in the `=== AUTOCMDS ===` section. Group
every autocmd under a named augroup.

```lua
api.nvim_create_autocmd('BufWritePre', {
    group    = api.nvim_create_augroup('my-group', { clear = true }),
    pattern  = '*.lua',
    callback = my_callback_fn,
})
```

If the callback is more than 2-3 lines, extract it as a named function with
`---@param` / `---@return` annotations above the autocmd declaration.

### User commands

Add `api.nvim_create_user_command(...)` in the `=== COMMANDS ===` section.

---

## lua/plugins.lua - Adding a Plugin

Plugin specs follow a flat structure: all configuration data as named constants
at the top of the file, plugin specs below. The `config` callback is a thin
applicator only - no data inside it.

**Pattern for a plugin with configuration:**

```lua
-- 1. Named constant at file scope, before the spec that uses it
---@class MyPluginConfig
---@field option_a string
---@field option_b boolean
---@type MyPluginConfig
local MY_PLUGIN_CONFIG = {
    option_a = "value",
    option_b = true,
}

-- 2. Spec - config callback is a thin applicator
{
    "author/my-plugin",
    config = function()
        require("my-plugin").setup(MY_PLUGIN_CONFIG)
    end,
},
```

**Rules:**
- Any table with 3 or more entries passed to a `setup()` call must be a named
  constant at file scope - never inline data in `config` callbacks.
- If a `config` callback exceeds 10 lines, the data is in the wrong place.
- Keymaps set inside a plugin's `config` must use `keymap.set(...)` with a
  `desc` in `"section: action"` format.

---

## Extensions

Extensions are optional `.lua` files executed after lazy.nvim finishes loading.
They are the right place for personal tooling that builds on installed plugins
(e.g. telescope workflows, project-specific keymaps).

**Location:** `$MC_EXTENSIONS_DIR` (default: `~/.config/mc_extensions/`)

Each extension file is executed in isolation. To integrate with Neovim, the
file must return a spec table. The loader reads the table and applies it.

### Spec table contract

```lua
return {
    keymaps  = keymaps,   -- table[] | {}  applied via keymap.set
    autocmds = autocmds,  -- table[] | {}  applied via nvim_create_autocmd
    commands = commands,  -- table[] | {}  applied via nvim_create_user_command
    setup    = nil,       -- function | nil  called last, for anything not covered above
}
```

All four fields must be present. Use `{}` for empty lists and `nil` for setup
when not needed.

### Loader application

The loader applies each field in order:

```
keymaps   keymap.set(km[1], km[2], km[3], km[4])
autocmds  api.nvim_create_autocmd(ac.event, ac.opts)
commands  api.nvim_create_user_command(cmd.name, cmd.fn, cmd.opts)
setup     result.setup()
```

If the file returns nothing (or a non-table value), it is silently skipped.
If it fails to load, a WARN notification is shown and Neovim continues normally.

### Extension file template

```lua
-- my_extension.lua
-- One-line description of what this extension does.

-- === GUARDS ===
-- Hard dependencies. Return nil on failure - loader handles it gracefully.
if vim == nil then print("not running in neovim"); return end

local ok, some_plugin = pcall(require, "some.plugin")
if not ok then
    vim.notify("[my_ext] some.plugin unavailable", vim.log.levels.WARN)
    return nil
end

-- === CONFIGURATION ===
-- Aliases (sanctioned three only, at file scope)
local api    = vim.api
local fn     = vim.fn
local keymap = vim.keymap

-- Env/paths resolved once at load time. Never re-read inside functions.
local my_dir = fn.fnamemodify(
    os.getenv("MY_DIR") or string.format("%s/fallback", os.getenv("HOME") or ""),
    ":p"
):gsub("/$", "")

-- === CONSTANTS ===
---@class FileSpec
---@field key  string
---@field path string
---@field desc string

---@type FileSpec[]
local FILES = {
    { key = "a", path = my_dir .. "/file-a.md", desc = "open file a" },
    { key = "b", path = my_dir .. "/file-b.md", desc = "open file b" },
}

---@type string
local MODE_NORMAL = "n"

---@type string
local LEADER_PREFIX = "<leader>m"

-- === FUNCTIONS ===

---@param path string
---@return function
local function make_open_fn(path)
    return function()
        vim.cmd(string.format("edit %s", path))
    end
end

-- === DECLARATIONS ===
-- Build the spec tables from constants. No direct API calls here.

---@type table[]
local keymaps = {}
for _, f in ipairs(FILES) do
    table.insert(keymaps, {
        MODE_NORMAL,
        LEADER_PREFIX .. f.key,
        make_open_fn(f.path),
        { desc = "my_ext: " .. f.desc },
    })
end

---@type table[]
local autocmds = {}  -- empty

---@type table[]
local commands = {}  -- empty

return {
    keymaps  = keymaps,
    autocmds = autocmds,
    commands = commands,
    setup    = nil,
}
```

---

## Disabling Without Deleting

Move the code to `lua/disabled/` as a standalone `.lua` file. The file must
remain valid Lua but is never loaded. To re-enable, merge the contents back
into the appropriate file.

```
lua/disabled/
  slime.lua             disabled vim-slime plugin spec
  search_qf_float.lua   disabled floating quickfix implementation
```

Never leave commented-out code blocks in `init.lua`, `lua/plugins.lua`, or
extension files.

---

## Phase 1 - Quick Reference Checklist

Apply these every time you write or modify Lua in this config. They are
non-negotiable.

**Data**
- [ ] Named constants in `UPPER_SNAKE_CASE`, declared before any function that uses them
- [ ] Any table with 3+ entries passed to `setup()` is a named constant at file scope
- [ ] No `vim.g.*` for module state - use module-local upvalues
- [ ] `---@type` (or `---@class`) on every named constant with 3+ fields

**Functions**
- [ ] `---@param` and `---@return` on every named function
- [ ] `config` callbacks are thin applicators - 10 lines max
- [ ] No metatables, no `__index` OOP, no `function obj:method()`
- [ ] No input table mutation

**Require and aliases**
- [ ] Full module require only: `local m = require("module.name")`
- [ ] Three sanctioned aliases only, at file scope: `api`, `fn`, `keymap`
- [ ] Everything else (`vim.opt`, `vim.cmd`, `vim.notify`, `vim.g`, `vim.bo`) always in full

**Control flow**
- [ ] Early returns over nesting
- [ ] No `x and y or z` ternary - write `if/else`
- [ ] Explicit nil checks: `if value == nil then`, not `if not value`
- [ ] `pcall` at every external boundary (channel sends, dynamic requires, fallible API calls)

**Strings and style**
- [ ] `string.format` for strings with 2+ embedded values
- [ ] `..` only for trivial two-value joins
- [ ] ASCII only - no Unicode, box-drawing characters, or non-ASCII symbols anywhere
- [ ] No commented-out code blocks - use `lua/disabled/` or delete

**Keymaps**
- [ ] Every keymap has a `desc` in `"section: action"` format

---

## Reference: Key Decisions

| Topic | Decision | Rationale |
|---|---|---|
| File count | 2 core files max | Discoverability - one place for everything |
| Plugin config data | Named constants at file scope | Data before behavior; auditable |
| Dead code | `lua/disabled/` or delete | No commented-out blocks in active files |
| Runtime state | Module-local upvalues | Explicit ownership, no global side-effects |
| String content | ASCII only | Encoding-safe across all terminals and tools |
| Extension interface | Spec table (4 fields) | Declarative; loader owns the API calls |
