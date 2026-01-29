vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.have_nerd_font = false
vim.o.termguicolors = true
require('core.options')
require('core.keymaps')
require('core.clipboard')
require('core.search_quickfix')

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Yank entire file and remove
vim.api.nvim_create_user_command('YankClean', function()
    -- Go to top of document
    vim.cmd('normal! gg')
    -- Yank entire document
    vim.cmd('normal! ggyG')
    -- Clean yanked text
    -- Remove newlines only, space only lines and trailing spaces.
    local yanked_text = vim.fn.getreg('"')
    local cleaned_text = yanked_text:gsub('\n%s*\n', '\n')
                                    :gsub('%s+$', '')
                                    :gsub('^%s+', '')

    -- Replace register with cleaned text
    vim.fn.setreg('"', cleaned_text)
end, {})

-- WORKAROUND: Fix for Neovim runtime syntax file bug
-- Issue: Built-in quarto.vim and rmd.vim syntax files have a circular dependency
-- that causes "Cannot redefine function IncludeLanguage: It is in use" error
-- Root cause: quarto.vim includes rmd.vim, which tries to redefine a function
-- while it's executing, creating a recursive loading conflict
-- Solution: Treat .qmd files as markdown instead of using problematic syntax files
-- Note: quarto-nvim plugin still provides LSP, code execution, and other features
-- This only affects syntax highlighting, and markdown highlighting works well for .qmd
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
require("lazy").setup({
    -- Load the plugins directory
    spec = {
        { import = "plugins" },
    },
    performance = {
        rtp = {
            disabled_plugins = {
                "gzip",
                "matchit",
                "matchparen",
                "netrwPlugin",
                "tarPlugin",
                "tohtml",
                "tutor",
                "zipPlugin",
            },
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
        notify = false, -- change to true if every time you modify configuration if you want notification.
    },
    ui = {
        border = "rounded",
    }
    --pkg = {
    --    sources = {
    --        "lua", "git" -- Add rockspecs here as "rockspecs" if you add a plugin that requires it.
    --    }
    --}
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

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
-- end
