local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
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
    }, {
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
    },
    pkg = {
        sources = {
            "lua", "git" -- Add rockspecs here as "rockspecs" if you add a plugin that requires it.
        }
    }
})
