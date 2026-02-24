-- Disabled: vim-slime quarto integration
-- To re-enable: move spec into lua/plugins/quarto.lua and add slime to dependencies
return {
  {
    'jpalardy/vim-slime',
    init = function()
      vim.b['quarto_is_python_chunk'] = false

      Quarto_is_in_python_chunk = function()
        require('otter.tools.functions').is_otter_language_context 'python'
      end

      vim.cmd [[
        let g:slime_dispatch_ipython_pause = 100
        function SlimeOverride_EscapeText_quarto(text)
          call v:lua.Quarto_is_in_python_chunk()
          if exists('g:slime_python_ipython') && len(split(a:text,"\n")) > 1 && b:quarto_is_python_chunk && !(exists('b:quarto_is_r_mode') && b:quarto_is_r_mode)
            return ["%cpaste -q\n", g:slime_dispatch_ipython_pause, a:text, "--", "\n"]
          else
            if exists('b:quarto_is_r_mode') && b:quarto_is_r_mode && b:quarto_is_python_chunk
              return [a:text, "\n"]
            else
              return [a:text]
            end
          end
        endfunction
      ]]

      local function mark_terminal()
        vim.g.slime_last_channel = vim.b.terminal_job_id
        vim.print(vim.g.slime_last_channel)
      end

      local function set_terminal()
        vim.b.slime_config = { jobid = vim.g.slime_last_channel }
      end

      vim.g.slime_target = 'neovim'
      vim.g.slime_python_ipython = 1

      require('which-key').register {
        ['<leader>cm'] = { mark_terminal, 'mark terminal' },
        ['<leader>cs'] = { set_terminal, 'set terminal' },
      }
    end,
  },
}
