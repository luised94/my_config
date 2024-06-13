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

--This loads all lua files in the plugins directory.
require("lazy").setup("plugins")
