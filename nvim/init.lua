-- === GLOBALS ===
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.have_nerd_font = false

-- === OPTIONS ===
---@class OptionSpec
---@field key string
---@field value any

---@type OptionSpec[]
local OPTIONS = {
    { key = "hlsearch",       value = true },        -- moved from keymaps.lua
    { key = "number",         value = true },
    { key = "relativenumber", value = true },
    { key = "autoindent",     value = true },
    { key = "breakindent",    value = true },
    { key = "wrap",           value = true },
    { key = "showbreak",      value = "|" },
    { key = "linebreak",      value = true },
    { key = "tabstop",        value = 2 },
    { key = "shiftwidth",     value = 2 },
    { key = "expandtab",      value = true },
    { key = "smarttab",       value = true },
    { key = "ignorecase",     value = true },
    { key = "smartcase",      value = true },
    { key = "signcolumn",     value = "yes" },
    { key = "updatetime",     value = 250 },
    { key = "timeoutlen",     value = 1000 },
    { key = "splitright",     value = true },
    { key = "splitbelow",     value = true },
    { key = "list",           value = true },
    { key = "listchars", value = { tab = "> ", trail = "-", nbsp = "?" } },
    { key = "inccommand",     value = "split" },
    { key = "cursorline",     value = true },
    { key = "cursorlineopt",  value = "number" },
    { key = "scrolloff",      value = 10 },
    { key = "clipboard",      value = "unnamedplus" },
    { key = "mouse",          value = "a" },
    { key = "showmode",       value = false },
    { key = "termguicolors",  value = true },
}

for _, opt in ipairs(OPTIONS) do
    vim.opt[opt.key] = opt.value
end

vim.opt.fillchars:append({ eob = " " })
vim.cmd("filetype plugin indent on")
vim.cmd("syntax on")

-- === KEYMAPS ===
require('core.keymaps')

-- === CLIPBOARD ===
require('core.clipboard')

-- === UTILITIES ===
require('core.search_quickfix')

-- === AUTOCMDS ===
vim.api.nvim_create_autocmd('TextYankPost', {
    desc = 'Highlight when yanking (copying) text',
    group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
    callback = function()
        vim.highlight.on_yank()
    end,
})

-- === COMMANDS ===
vim.api.nvim_create_user_command('YankClean', function()
    vim.cmd('normal! gg')
    vim.cmd('normal! ggyG')
    local yanked_text = vim.fn.getreg('"')
    local cleaned_text = yanked_text:gsub('\n%s*\n', '\n')
                                    :gsub('%s+$', '')
                                    :gsub('^%s+', '')
    vim.fn.setreg('"', cleaned_text)
end, {})

vim.filetype.add({
    extension = {
        qmd = "markdown",
        quarto = "markdown",
    },
})
--[[
local function is_on_cluster()
  # Run print(vim.fn.hostname()) in linux cluster to set the variable appropriately.,
  return os.getenv("CLUSTER_ENV") == true or vim.fn.hostname():match("cluster") ~= nil
end 
--]]
-- Uncomment after enabling is_on_cluster
-- if not is_on_cluster() then
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },
            { "\nPress any ket to exit..." },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end
vim.opt.rtp:prepend(lazypath)

-- Load plugins in directory, that I can separate into functionality
-- Plugins are in the lua/plugins directory as lua file. The lua files must be return a table of tables. Each table element has to have the configuration for the given plugin I have separated them in terms of their functionality.
-- They are separated by plugin and should be self-contained for the most part. Only the breaking_bad_habits.lua  has two plugins but they serve the same purpose and dont have complicated setups.
--This loads all lua files in the plugins directory.

local DISABLED_BUILTIN_PLUGINS = {
    "gzip",
    "matchit",
    "matchparen",
    "netrwPlugin",
    "tarPlugin",
    "tohtml",
    "tutor",
    "zipPlugin",
}

require("lazy").setup({
    spec = {
        { import = "plugins" },
    },
    performance = {
        rtp = {
            disabled_plugins = DISABLED_BUILTIN_PLUGINS,
        },
    },
    install = {
        missing = true,
        colorscheme = { "habamax" },
    },
    checker = {
        enabled = true,
        notify = false,
    },
    change_detection = {
        notify = false,
    },
    ui = {
        border = "rounded",
    },
})

-- Plugins are loaded in the lazy-bootstrap file.
-- Extension loader for mc_extensions
-- Add to end of init.lua after lazy.nvim setup

local extensions_dir = os.getenv("MC_EXTENSIONS_DIR")

if extensions_dir == nil then
    extensions_dir = string.format("%s/.config/mc_extensions", os.getenv("HOME"))
end

local dir_exists = vim.fn.isdirectory(extensions_dir) == 1

if not dir_exists then
    local message = string.format("Extension loader: directory not found: %s", extensions_dir)
    vim.notify(message, vim.log.levels.WARN)
    return
end

local glob_pattern = string.format("%s/*.lua", extensions_dir)
local match_all = false
local return_list = true
local lua_files = vim.fn.glob(glob_pattern, match_all, return_list)

local file_count = #lua_files

if file_count == 0 then
    return
end

for _, filepath in ipairs(lua_files) do
    local load_success, error_message = pcall(dofile, filepath)
    if not load_success then
        local warning = string.format("Extension loader: failed to load %s\n%s", filepath, error_message)
        vim.notify(warning, vim.log.levels.WARN)
    end
end

-- Persistent terminal runner for executing current file with single keystroke
-- Maintains one reusable terminal buffer per Neovim session
-- Supports Python, R, C, Lua, and shell scripts

local api = vim.api
local fn = vim.fn
local keymap = vim.keymap

-- Build runner table, dropping any with missing executables
local base_runners = {
  python = { command = "uv run %s", executable = "uv" },
  r = { command = "Rscript --vanilla %s", executable = "Rscript" },
  c = { command = "gcc -Wall -Wextra %s -o /tmp/%s && /tmp/%s", executable = "gcc" },
  lua = { command = "lua %s", executable = "lua" },
  sh = { command = "bash %s", executable = "bash" },
}

local RUNNERS = {}
for filetype, config in pairs(base_runners) do
  if fn.executable(config.executable) == 1 then
    RUNNERS[filetype] = config
  else
    local message = string.format(
      "Runner for %s unavailable: %s not found in PATH",
      filetype,
      config.executable
    )
    vim.notify(message, vim.log.levels.WARN)
  end
end

---Execute current file in persistent terminal buffer
---@return nil
local function run_current_file()
  local current_filetype = vim.bo.filetype
  local current_filepath = fn.expand("%:p")

  -- Check if filetype has runner support
  if RUNNERS[current_filetype] == nil then
    local message = string.format("No runner configured for filetype: %s", current_filetype)
    vim.notify(message, vim.log.levels.WARN)
    return
  end

  -- Auto-save if buffer modified
  if vim.bo.modified then
    vim.cmd("write")
  end

  -- Resolve command string for this filetype
  local command
  if current_filetype == "c" and fn.filereadable("Makefile") == 1 then
    -- C with Makefile uses make workflow
    command = "make && ./a.out"
  else
    -- Standard case: substitute filepath into command template
    local config = RUNNERS[current_filetype]
    if current_filetype == "c" then
      local basename = fn.fnamemodify(current_filepath, ":t:r")
      command = string.format(config.command, current_filepath, basename, basename)
    else
      command = string.format(config.command, current_filepath)
    end
  end

  -- Get current terminal state
  local term_buf_id = vim.g.persistent_runner_term_buf_id
  local term_chan_id = vim.g.persistent_runner_term_chan_id

  -- Check if terminal is stale (buffer was wiped)
  if term_buf_id ~= nil and not api.nvim_buf_is_valid(term_buf_id) then
    -- Stale -> Cold: reset state
    vim.g.persistent_runner_term_buf_id = nil
    vim.g.persistent_runner_term_chan_id = nil
    term_buf_id = nil
    term_chan_id = nil
  end

  -- Create terminal if in Cold state
  if term_buf_id == nil then
    local origin_window = api.nvim_get_current_win()

    vim.cmd("split")
    vim.cmd("terminal")

    term_buf_id = api.nvim_get_current_buf()
    term_chan_id = vim.bo[term_buf_id].channel

    -- Configure buffer to wipe when hidden
    vim.bo[term_buf_id].bufhidden = "wipe"

    -- Buffer-local <Esc><Esc> exits terminal and closes split
    api.nvim_buf_set_keymap(
      term_buf_id,
      "t",
      "<Esc><Esc>",
      "<C-\\><C-n>:close<CR>",
      { noremap = true, silent = true }
    )

    -- Return focus to original window
    api.nvim_set_current_win(origin_window)

    -- Store new terminal state
    vim.g.persistent_runner_term_buf_id = term_buf_id
    vim.g.persistent_runner_term_chan_id = term_chan_id

    -- Notify user that terminal is initializing
    vim.notify("Terminal created - initializing shell", vim.log.levels.INFO)

    -- Delay command send to allow shell initialization (bashrc loading)
    vim.defer_fn(function()
      fn.chansend(term_chan_id, command .. "\n")
    end, 300)
  else
    -- Terminal already exists and ready - send command immediately
    fn.chansend(term_chan_id, command .. "\n")
  end
end

-- Set up keybinding
keymap.set("n", "<leader>r", run_current_file, {
  noremap = true,
  silent = true,
  desc = "Run current file in persistent terminal"
})
-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
-- end
