-- === GLOBALS ===
vim.g.mapleader    = " "
vim.g.maplocalleader = "\\"
vim.g.have_nerd_font = false

local api    = vim.api
local fn     = vim.fn
local keymap = vim.keymap

-- === OPTIONS ===
---@class OptionSpec
---@field key   string
---@field value any

---@type OptionSpec[]
local OPTIONS = {
    { key = "hlsearch",       value = true },
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
    { key = "listchars",      value = { tab = "> ", trail = "-", nbsp = "?" } },
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
---@class KeymapSpec
---@field mode string
---@field lhs  string
---@field rhs  string|function
---@field opts table

---@type KeymapSpec[]
local KEYMAPS = {
    { mode = "n", lhs = "<Esc>",     rhs = "<cmd>nohlsearch<CR>",    opts = { desc = "editor: clear search highlight" } },
    { mode = "n", lhs = "[d",        rhs = vim.diagnostic.goto_prev, opts = { desc = "diagnostic: go to previous" } },
    { mode = "n", lhs = "]d",        rhs = vim.diagnostic.goto_next, opts = { desc = "diagnostic: go to next" } },
    { mode = "n", lhs = "<leader>e", rhs = vim.diagnostic.open_float, opts = { desc = "diagnostic: show errors" } },
    { mode = "n", lhs = "<leader>q", rhs = vim.diagnostic.setloclist, opts = { desc = "diagnostic: open quickfix list" } },
}

for _, km in ipairs(KEYMAPS) do
    keymap.set(km.mode, km.lhs, km.rhs, km.opts)
end

-- === CLIPBOARD ===
if fn.has('wsl') == 1 then
    ---@class ClipboardConfig
    ---@field name          string
    ---@field copy          table<string, string>
    ---@field paste         table<string, string>
    ---@field cache_enabled integer

    ---@type ClipboardConfig
    local CLIPBOARD_CONFIG = {
        name = 'WslClipboard',
        copy = {
            ['+'] = 'clip.exe',
            ['*'] = 'clip.exe',
        },
        paste = {
            ['+'] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
            ['*'] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
        },
        cache_enabled = 0,
    }
    vim.g.clipboard = CLIPBOARD_CONFIG
end

-- === UTILITIES ===

---@class SearchQFWindow
---@field width   integer
---@field height  integer
---@field padding integer
---@field blend   integer

---@class SearchQFConfig
---@field window SearchQFWindow

---@type SearchQFConfig
local SEARCH_QF_CONFIG = {
    window = {
        width   = 80,
        height  = 20,
        padding = 2,
        blend   = 10,
    },
}

---@param search_string string
---@return boolean
local function validate_search(search_string)
    if search_string == nil or search_string == "" then
        vim.notify("[search_qf] search string cannot be empty", vim.log.levels.ERROR)
        return false
    end
    return true
end

---@return nil
local function reset_quickfix_list()
    vim.cmd("silent! call setqflist([])")
end

---@class UserLocation
---@field winnr  integer
---@field buffer integer
---@field cursor integer[]

---@return UserLocation
local function save_user_location()
    return {
        winnr  = api.nvim_get_current_win(),
        buffer = api.nvim_get_current_buf(),
        cursor = api.nvim_win_get_cursor(0),
    }
end

---@param location UserLocation
---@return nil
local function restore_user_location(location)
    if location == nil or location.buffer == nil or location.cursor == nil then return end
    if not api.nvim_buf_is_valid(location.buffer) then return end
    if api.nvim_win_is_valid(location.winnr) then
        api.nvim_set_current_win(location.winnr)
    end
    local line_count  = api.nvim_buf_line_count(location.buffer)
    local cursor_line = math.min(location.cursor[1], line_count)
    local line_text   = api.nvim_buf_get_lines(location.buffer, cursor_line - 1, cursor_line, false)[1]
    local cursor_col  = math.min(location.cursor[2], line_text ~= nil and #line_text or 0)
    api.nvim_set_current_buf(location.buffer)
    api.nvim_win_set_cursor(0, { cursor_line, cursor_col })
end

---@param search_string string
---@return nil
local function search_buffers(search_string)
    reset_quickfix_list()
    vim.cmd(string.format([[
        silent! bufdo if filereadable(expand('%%:p')) | vimgrepadd /%s/ %% | endif
    ]], fn.escape(search_string, '/')))
end

---@return boolean, integer|nil
local function is_quickfix_open()
    for _, win in ipairs(api.nvim_list_wins()) do
        local buf = api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == 'quickfix' then
            return true, win
        end
    end
    return false, nil
end

---@return nil
local function close_quickfix_if_empty()
    local qf_list = fn.getqflist({ size = 0 })
    if qf_list.size == 0 then
        local qf_open, qf_win = is_quickfix_open()
        if qf_open and qf_win ~= nil then
            if #api.nvim_tabpage_list_wins(0) == 1 then
                for _, buf in ipairs(api.nvim_list_bufs()) do
                    if api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == '' then
                        api.nvim_set_current_buf(buf)
                        break
                    end
                end
            end
            vim.cmd('cclose')
        end
    end
end

---@param search_string string
---@param floating      boolean
---@return nil
local function search_and_show(search_string, floating)
    if not validate_search(search_string) then return end
    local user_location = save_user_location()
    local ok, result = pcall(function()
        search_buffers(search_string)
        if fn.getqflist({ size = 0 }).size == 0 then
            restore_user_location(user_location)
            vim.notify(
                string.format("[search_qf] no matches found for: %s", search_string),
                vim.log.levels.WARN
            )
            close_quickfix_if_empty()
            return
        end
        if floating then
            vim.notify("[search_qf] floating window is currently disabled", vim.log.levels.INFO)
            restore_user_location(user_location)
        else
            local qf_open, qf_win = is_quickfix_open()
            if qf_open and qf_win ~= nil and api.nvim_win_is_valid(qf_win) then
                local current_win = api.nvim_get_current_win()
                api.nvim_set_current_win(qf_win)
                vim.cmd('cbottom')
                api.nvim_set_current_win(current_win)
            else
                vim.cmd('botright copen')
            end
            restore_user_location(user_location)
        end
        close_quickfix_if_empty()
    end)
    if not ok then
        restore_user_location(user_location)
        vim.notify(
            string.format("[search_qf] search failed: %s", tostring(result)),
            vim.log.levels.ERROR
        )
    end
end

api.nvim_create_user_command('SearchQF', function(opts)
    local args        = opts.fargs
    local floating    = false
    local search_term = ""
    if #args > 0 then
        if args[1] == "float" then
            floating    = true
            search_term = table.concat(args, " ", 2)
        else
            search_term = table.concat(args, " ")
        end
    end
    search_and_show(search_term, floating)
end, {
    nargs    = "+",
    complete = function(_, _, _)
        return { "float" }
    end,
})

---@type integer|nil
local terminal_buffer_id = nil

---@type integer|nil
local terminal_channel_id = nil

---@class TerminalStateConstants
---@field COLD  string
---@field STALE string
---@field READY string

---@type TerminalStateConstants
local TERMINAL_STATE = {
    COLD  = "cold",
    STALE = "stale",
    READY = "ready",
}

---@class RunnerSpec
---@field command    string
---@field executable string

---@type table<string, RunnerSpec>
local RUNNER_SPECS = {
    python = { command = "uv run %s",                                  executable = "uv" },
    r      = { command = "Rscript --vanilla %s",                       executable = "Rscript" },
    c      = { command = "gcc -Wall -Wextra %s -o /tmp/%s && /tmp/%s", executable = "gcc" },
    lua    = { command = "lua %s",                                     executable = "lua" },
    sh     = { command = "bash %s",                                    executable = "bash" },
}

---@type table<string, RunnerSpec>
local RUNNERS = {}
for filetype, spec in pairs(RUNNER_SPECS) do
    if fn.executable(spec.executable) == 1 then
        RUNNERS[filetype] = spec
    else
        vim.notify(
            string.format("[runner] %s unavailable: %s not found in PATH", filetype, spec.executable),
            vim.log.levels.WARN
        )
    end
end

---@return string
local function get_terminal_state()
    if terminal_buffer_id == nil then return TERMINAL_STATE.COLD end
    if not api.nvim_buf_is_valid(terminal_buffer_id) then return TERMINAL_STATE.STALE end
    return TERMINAL_STATE.READY
end

---@param channel_id integer
---@param command    string
---@return nil
local function send_to_terminal(channel_id, command)
    local ok, err = pcall(fn.chansend, channel_id, command .. "\n")
    if not ok then
        vim.notify(
            string.format("[runner] failed to send command: %s", tostring(err)),
            vim.log.levels.ERROR
        )
    end
end

---@param filetype string
---@param filepath string
---@return string|nil
local function resolve_command(filetype, filepath)
    local spec = RUNNERS[filetype]
    if spec == nil then return nil end
    if filetype == "c" and fn.filereadable("Makefile") == 1 then
        return "make && ./a.out"
    end
    if filetype == "c" then
        local basename = fn.fnamemodify(filepath, ":t:r")
        return string.format(spec.command, filepath, basename, basename)
    end
    return string.format(spec.command, filepath)
end

---@return nil
local function run_current_file()
    local current_filetype = vim.bo.filetype
    local current_filepath = fn.expand("%:p")

    if RUNNERS[current_filetype] == nil then
        vim.notify(
            string.format("[runner] no runner configured for filetype: %s", current_filetype),
            vim.log.levels.WARN
        )
        return
    end

    if vim.bo.modified then
        vim.cmd("write")
    end

    local command = resolve_command(current_filetype, current_filepath)
    if command == nil then return end

    local state = get_terminal_state()

    if state == TERMINAL_STATE.STALE then
        terminal_buffer_id  = nil
        terminal_channel_id = nil
    end

    if terminal_buffer_id == nil then
        local origin_window = api.nvim_get_current_win()
        vim.cmd("split")
        vim.cmd("terminal")
        terminal_buffer_id  = api.nvim_get_current_buf()
        terminal_channel_id = vim.bo[terminal_buffer_id].channel
        vim.bo[terminal_buffer_id].bufhidden = "wipe"
        api.nvim_buf_set_keymap(
            terminal_buffer_id, "t", "<Esc><Esc>", "<C-\\><C-n>:close<CR>",
            { noremap = true, silent = true }
        )
        api.nvim_set_current_win(origin_window)
        vim.notify("[runner] terminal created - initializing shell", vim.log.levels.INFO)
        vim.defer_fn(function()
            if terminal_channel_id ~= nil then
                send_to_terminal(terminal_channel_id, command)
            end
        end, 300)
    else
        if terminal_channel_id ~= nil then
            send_to_terminal(terminal_channel_id, command)
        end
    end
end

keymap.set("n", "<leader>r", run_current_file, {
    noremap = true,
    silent  = true,
    desc    = "runner: run current file",
})

-- === AUTOCMDS ===
api.nvim_create_autocmd('TextYankPost', {
    desc     = 'Highlight when yanking (copying) text',
    group    = api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
    callback = function()
        vim.highlight.on_yank()
    end,
})

-- === COMMANDS ===
api.nvim_create_user_command('YankClean', function()
    vim.cmd('normal! gg')
    vim.cmd('normal! ggyG')
    local yanked_text  = fn.getreg('"')
    local cleaned_text = yanked_text:gsub('\n%s*\n', '\n')
                                    :gsub('%s+$', '')
                                    :gsub('^%s+', '')
    fn.setreg('"', cleaned_text)
end, {})

vim.filetype.add({
    extension = {
        qmd    = "markdown",
        quarto = "markdown",
    },
})

-- === LAZY BOOTSTRAP ===
---@type string
local lazypath = fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = fn.system({
        "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath,
    })
    if vim.v.shell_error ~= 0 then
        api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out,                             "WarningMsg" },
            { "\nPress any key to exit..." },
        }, true, {})
        fn.getchar()
        os.exit(1)
    end
end
vim.opt.rtp:prepend(lazypath)

-- === PLUGINS ===
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

require("lazy").setup(require("plugins"), {
    performance = {
        rtp = { disabled_plugins = DISABLED_BUILTIN_PLUGINS },
    },
    install = {
        missing    = true,
        colorscheme = { "habamax" },
    },
    checker = {
        enabled = true,
        notify  = false,
    },
    change_detection = { notify = false },
    ui               = { border = "rounded" },
})

-- === EXTENSIONS ===
---@type string
local extensions_dir = os.getenv("MC_EXTENSIONS_DIR") or
    string.format("%s/.config/mc_extensions", os.getenv("HOME"))

if fn.isdirectory(extensions_dir) ~= 1 then
    vim.notify(
        string.format("[extensions] directory not found: %s", extensions_dir),
        vim.log.levels.WARN
    )
else
    ---@type string[]
    local lua_files = fn.glob(string.format("%s/*.lua", extensions_dir), false, true)

    for _, filepath in ipairs(lua_files) do
        local ok, err = pcall(dofile, filepath)
        if not ok then
            vim.notify(
                string.format("[extensions] failed to load %s: %s", filepath, err),
                vim.log.levels.WARN
            )
        end
    end
end

-- vim: ts=2 sts=2 sw=2 et
