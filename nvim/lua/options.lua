-- [[ Setting options ]]
-- :help vim.opt OR :help option-list
-- loaded using require 'options'
-- Add number lines and show as relative.
vim.opt.number = true
vim.opt.relativenumber = true

-- vim.opt.showmode = false

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
