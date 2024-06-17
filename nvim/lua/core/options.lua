-- [[ Setting options ]]
-- :help vim.opt OR :help option-list
-- Also see :help '<vim-option>' to see entry for a particular option
-- loaded using require 'options'
-- Add number lines and show as relative.
vim.opt.number = true
vim.opt.relativenumber = true

-- vim.opt.showmode = false

-- Set autoindent explicilty
vim.opt.autoindent = true

-- Detect filetype automatically
vim.cmd('filetype plugin indent on')

-- Enable syntax highlighting
vim.cmd('syntax on')

-- Lines will wrap with indent if the original line is indented. 
vim.opt.breakindent = true

-- Keeps undo files across sessions in project_undodir
-- Modified undofile option but kept commented since I am not sure if it will be super useful to me.
-- local project_undodir = vim.fn.expand("./.vimundo//")
-- vim.opt.undofile = true
-- vim.opt.undodir = project_undodir
-- -- Ensure the undo directory exists
-- if vim.fn.isdirectory(vim.opt.undodir:get()) == 0 then
--   vim.fn.mkdir(vim.opt.undodir:get(), "p")
-- end
-- -- find ~/.vim/undo -type f -mtime +30 -delete --Useful for managing undo files to prevent clutteror persistence.

-- Add tab setting to make it 4 spaces.
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smarttab = true
-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Keep signcolumn on by default, used to show results of LSPs for example
vim.opt.signcolumn = 'yes'

-- Decrease update time, used for crash recovery
vim.opt.updatetime = 250

-- Modify time neovim waits for keypresses to create commands. Left as default since I am not that fast.
-- Displays which-key popup sooner
vim.opt.timeoutlen = 1000

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.opt.inccommand = 'split'

-- Show which line your cursor is on
vim.opt.cursorline = true
vim.opt.cursorlineopt = "number"

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 10

-- Remove the ~ that fill the lines below
vim.opt.fillchars:append(',eob: ')

-- Tells me if line is wrapped 
-- vim.g.showbreak = ' '

-- Enable copy/pasting from mouse
vim.opt.clipboard = "unnamedplus"
vim.opt.mouse = "a"

vim.opt.showmode = false
