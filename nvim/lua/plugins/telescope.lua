return {

    { -- Fuzzy Finder (files, lsp, etc)
      'nvim-telescope/telescope.nvim',
      event = 'VimEnter',
      branch = '0.1.x',
      dependencies = {
        'nvim-lua/plenary.nvim',
        { -- If encountering errors, see telescope-fzf-native README for installation instructions
          'nvim-telescope/telescope-fzf-native.nvim',

          -- Build is only run upon installation, not everytime Neovim starts.
          build = 'make',

          -- `cond` is a condition used to determine whether this plugin should be
          -- installed and loaded.
          cond = function()
            return vim.fn.executable 'make' == 1
          end,
        },
        { 'nvim-telescope/telescope-ui-select.nvim' },
      --{ jmbuhr/telescope-zotero.nvim,
            --enabled = true,
            --dev = false,
            --dependencies = {
            -- { 'kkharji/sqlite.lua' },
            --},
            --config = function()
                --vim.keymap.set('n', '<leader>fz', ':Telescope zotero<cr>', {desc = '[z]otero'})
        --}
        -- Useful for getting pretty icons, but requires a Nerd Font.
        { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
        'nvim-telescope/telescope-bibtex.nvim',
      },
      config = function()
        -- Telescope is a fuzzy finder that comes with a lot of different things that
        -- it can fuzzy find! It's more than just a "file finder", it can search
        -- many different aspects of Neovim, your workspace, LSP, and more!

        -- The easiest way to use Telescope, is to start by doing something like:
        --  :Telescope help_tags

        -- After running this command, a window will open up and you're able to
        -- type in the prompt window. You'll see a list of `help_tags` options and
        -- a corresponding preview of the help.

        -- Two important keymaps to use while in Telescope are:
        --  - Insert mode: <c-/>
        --  - Normal mode: ?

        -- This opens a window that shows you all of the keymaps for the current
        -- Telescope picker. This is really useful to discover what Telescope can
        -- do as well as how to actually do it!

        -- [[ Configure Telescope ]]
        -- See `:help telescope` and `:help telescope.setup()`
        require('telescope').setup {
          -- You can put your default mappings / updates / etc. in here
          --  All the info you're looking for is in `:help telescope.setup()`
          -- defaults = {
          --    file_sorter = require('telescope.sorters').get_fzy_sorter,
          --    generic_sorter = require('telescope.sorters').get_generic_fuzzy_sorter,
          -- file_previewer = require('telescope.previewers').vim_buffer_cat.new,
          -- grep_previewer = require('telescope.previewers').vim_buffer_vimgrep.new,
          -- qflist_previewer = require('telescope.previewers').vim_buffer_qflist.new,
          -- },
          --   mappings = {
          --     i = { ['<c-enter>'] = 'to_fuzzy_refine' },
          --   },
          -- },
          -- pickers = {}
          extensions = {
            ['ui-select'] = { require('telescope.themes').get_dropdown(), },
            bibtex = {
                        depth = 1,
                        global_files = { '~/mylibrary.bib'},
                        search_keys = { 'author', 'year', 'title', 'citekey' },
                        citation_format = '@{{citekey}}',
                        citation_trim_firstname = true,
                        citation_max_auth = 2,
                        custom_formats = {
                    { id = 'qcite', cite_maker = '@{{citekey}}' },
                    { id = 'qcites', cite_maker = '[@{{citekey}}; @{{citekey}}]' },

                        },
                    },
                        format = 'qcite',
                        context = false,
                        context_fallback = false,
                        wrap = false,
          },
        }
        -- Enable Telescope extensions if they are installed
        pcall(require('telescope').load_extension, 'fzf')
        pcall(require('telescope').load_extension, 'ui-select')
        pcall(require('telescope').load_extension, 'bibtex')
        -- Define functions
function CitePicker()
  -- Adjust the path to your actual Zotero library bib file
  local bib_file = vim.fn.expand('~/mylibrary.bib')
  -- Use grep instead of rg and avoid piping to fzf
  local command = string.format("grep -oP '@[^{]+\\{\\K[^,]+' %s", bib_file)
  local citations = vim.fn.system(command)
  -- Split the output into a table of citations
  local citation_list = vim.split(citations, "\n")
  -- Use vim.ui.select for interactive selection
  vim.ui.select(citation_list, {
    prompt = "Select citation:",
    format_item = function(item)
      return "@" .. item
    end,
  }, function(choice)
    if choice then
      -- Insert the selected citation at the cursor position
      vim.api.nvim_put({"@" .. choice}, 'c', true, true)
    else
      print("No citation selected")
    end
  end)
end

        -- See `:help telescope.builtin`
        local builtin = require 'telescope.builtin'
        vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
        vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
        vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
        vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
        vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
        vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
        vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
        vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
        vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
        vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })
        --vim.keymap.set('n', '<leader>fc', '<cmd>Telescope bibtex<cr>', { desc = 'Find citation' })
        vim.keymap.set('n', '<leader>fc', CitePicker, { desc = 'Find citation' })
        -- Slightly advanced example of overriding default behavior and theme
        vim.keymap.set('n', '<leader>/', function()
          -- You can pass additional configuration to Telescope to change the theme, layout, etc.
          builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
            winblend = 10,
            previewer = false,
          })
        end, { desc = '[/] Fuzzily search in current buffer' })

        -- It's also possible to pass additional configuration options.
        --  See `:help telescope.builtin.live_grep()` for information about particular keys
        vim.keymap.set('n', '<leader>s/', function()
          builtin.live_grep {
            grep_open_files = true,
            prompt_title = 'Live Grep in Open Files',
          }
        end, { desc = '[S]earch [/] in Open Files' })

        -- Shortcut for searching your Neovim configuration files
        vim.keymap.set('n', '<leader>sn', function()
          builtin.find_files { cwd = vim.fn.stdpath 'config' }
        end, { desc = '[S]earch [N]eovim files' })
      end,
    },
}

