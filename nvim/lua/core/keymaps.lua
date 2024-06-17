-- [[ Basic Keymaps ]] 
vim.opt.hlsearch = true
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous [D]iagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next [D]iagnostic message' })
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic [E]rror messages' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- This is already set with hardtime plugin.
-- TIP: Disable arrow keys in normal mode
--vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
--vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
--vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
--vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

-- Commented out since I dont want to modify most of the default behavior yet.
-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
--vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
--vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
--vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
--vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })
