--[[
Configuration was started from kickstart. I tried to keep comments of the guide that would help me and anybody else if they were to clone my configuration for any reason.

What is Kickstart?
Kickstart.nvim is *not* a distribution. Kickstart.nvim is a starting point for your own configuration. The goal is that you can read every line of code, top-to-bottom, understand what your configuration is doing, and modify it to suit your needs. Once you've done that, you can start exploring, configuring and tinkering to make Neovim your own! That might mean leaving Kickstart just the way it is for a while or immediately breaking it into modular pieces. It's up to you!

If you don't know anything about Lua:
https://learnxinyminutes.com/docs/lua/
`:help lua-guide`
https://neovim.io/doc/user/lua-guide.html

Kickstart Guide:
The very first thing you should do is to run the command `:Tutor` in Neovim.
Once you've completed that, you can continue working through **AND READING** the rest of the kickstart init.lua.
Next, run AND READ `:help`. This will open up a help window with some basic information about reading, navigating and searching the builtin help documentation. This should be the first place you go to look when you're stuck or confused with something. It's one of my favorite Neovim features.
MOST IMPORTANTLY, we provide a keymap "<space>sh" to [s]earch the [h]elp documentation, which is very useful when you're not exactly sure of what you're looking for.
If you experience any errors while trying to install kickstart, run `:checkhealth` for more info.
--]]
--[[
I use a modular organization to organize my neovim config. Inspiration comes from dam9000/kickstart.nvim and fzhnf/kickstart.nvim. They can be cloned instead of doing it manually. 
--]]
--
-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Set to true if you have a Nerd Font installed
vim.g.have_nerd_font = false

-- [[ Setting options ]]
-- See `:help vim.opt`
-- For more options, you can see `:help option-list`
require 'options'

-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`
-- Set highlight on search, but clear on pressing <Esc> in normal mode
require 'keymaps'

-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

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

-- [[ Install `lazy.nvim` plugin manager ]]
require 'lazy-bootstrap'

-- [[ Configure and install plugins ]]
require 'lazy-plugins'

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
