return {
  {
    'quarto-dev/quarto-nvim',
    ft = { 'quarto' },
    dev = false,
    opts = {
      lspFeatures = {
        languages = { 'r', 'python', 'julia', 'bash', 'lua', 'html', 'dot', 'javascript', 'typescript', 'ojs' },
      },
      codeRunner = {
        enabled = true,
        default_method = 'slime',
      },
    },
    dependencies = {
      {
        'jmbuhr/otter.nvim',
        dev = false,
        dependencies = {
          { 'neovim/nvim-lspconfig' },
        },
        opts = {
          lsp = {
            hover = {
              border = "rounded",
            },
          },
          buffers = {
            set_filetype = true,
          },
          handle_leading_whitespace = true,
        },
      },
    },
  },
}
--  { -- Autoformat
--    'stevearc/conform.nvim',
--    enabled = true,
--    config = function()
--      require('conform').setup {
--        notify_on_error = false,
--        format_on_save = {
--          timeout_ms = 500,
--          lsp_fallback = true,
--        },
--        formatters_by_ft = {
--          lua = { 'mystylua' },
--          python = { 'isort', 'black' },
--        },
--        formatters = {
--          mystylua = {
--            command = 'stylua',
--            args = { '--indent-type', 'Spaces', '--indent-width', '2', '-' },
--          },
--        },
--      }
--      -- Customize the "injected" formatter
--      require('conform').formatters.injected = {
--        -- Set the options field
--        options = {
--          -- Set to true to ignore errors
--          ignore_errors = false,
--          -- Map of treesitter language to file extension
--          -- A temporary file name with this extension will be generated during formatting
--          -- because some formatters care about the filename.
--          lang_to_ext = {
--            bash = 'sh',
--            c_sharp = 'cs',
--            elixir = 'exs',
--            javascript = 'js',
--            julia = 'jl',
--            latex = 'tex',
--            markdown = 'md',
--            python = 'py',
--            ruby = 'rb',
--            rust = 'rs',
--            teal = 'tl',
--            r = 'r',
--            typescript = 'ts',
--          },
--          -- Map of treesitter language to formatters to use
--          -- (defaults to the value from formatters_by_ft)
--          lang_to_formatters = {},
--        },
--      }
--    end,
--  },
--
--
--      local has_words_before = function()
--        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
--        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match '%s' == nil
--      end
--
--  {
--    'jpalardy/vim-slime',
--    init = function()
--      vim.b['quarto_is_python_chunk'] = false
--      Quarto_is_in_python_chunk = function()
--        require('otter.tools.functions').is_otter_language_context 'python'
--      end
--
--      vim.cmd [[
--      let g:slime_dispatch_ipython_pause = 100
--      function SlimeOverride_EscapeText_quarto(text)
--      call v:lua.Quarto_is_in_python_chunk()
--      if exists('g:slime_python_ipython') && len(split(a:text,"\n")) > 1 && b:quarto_is_python_chunk && !(exists('b:quarto_is_r_mode') && b:quarto_is_r_mode)
--      return ["%cpaste -q\n", g:slime_dispatch_ipython_pause, a:text, "--", "\n"]
--      else
--      if exists('b:quarto_is_r_mode') && b:quarto_is_r_mode && b:quarto_is_python_chunk
--      return [a:text, "\n"]
--      else
--      return [a:text]
--      end
--      end
--      endfunction
--      ]]
--
--      local function mark_terminal()
--        vim.g.slime_last_channel = vim.b.terminal_job_id
--        vim.print(vim.g.slime_last_channel)
--      end
--
--      local function set_terminal()
--        vim.b.slime_config = { jobid = vim.g.slime_last_channel }
--      end
--
--      vim.g.slime_target = 'neovim'
--      vim.g.slime_python_ipython = 1
--
--      require('which-key').register {
--        ['<leader>cm'] = { mark_terminal, 'mark terminal' },
--        ['<leader>cs'] = { set_terminal, 'set terminal' },
--      }
--    end,
--  },
--
--  -- preview equations
--  {
--    'jbyuki/nabla.nvim',
--    keys = {
--      { '<leader>qm', ':lua require"nabla".toggle_virt()<cr>', desc = 'toggle [m]ath equations' },
--    },
--  },
