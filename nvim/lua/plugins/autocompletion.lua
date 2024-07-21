return {

  { -- Autocompletion
    'hrsh7th/nvim-cmp',
    event = 'InsertEnter',
    dependencies = {
      -- Snippet Engine & its associated nvim-cmp source
      {
        'L3MON4D3/LuaSnip',
        build = 'make install_jsregexp',
          -- Build Step is needed for regex support in snippets.
          -- This step is not supported in many windows environments.
          -- Remove the below condition to re-enable on windows.
         -- if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
         --   return
         -- end
        dependencies = {
           {
            "rafamadriz/friendly-snippets",
            "benfowler/telescope-luasnip.nvim",
           },
        },
      },
      'hrsh7th/cmp-buffer',
      'onsails/lspkind-nvim',
      'jmbuhr/cmp-pandoc-references', -- For quarto and markdown
      'jalvesaq/cmp-nvim-r', -- For R
      'saadparwaiz1/cmp_luasnip',
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-cmdline', -- For command line mode and bash files
    },
    config = function()
        require('luasnip.loaders.from_vscode').lazy_load()
      -- See `:help cmp`
      local cmp = require 'cmp'
      local luasnip = require 'luasnip'
      local lspkind = require 'lspkind'
      luasnip.config.setup {}

      cmp.setup {
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        completion = { completeopt = 'menu,menuone,noinsert' },

        -- For an understanding of why these mappings were
        -- chosen, you will need to read `:help ins-completion`
        mapping = cmp.mapping.preset.insert {
          ['<C-n>'] = cmp.mapping.select_next_item(), -- Select the [n]ext item
          ['<C-p>'] = cmp.mapping.select_prev_item(), -- Select the [p]revious item
          -- Scroll the documentation window [b]ack / [f]orward
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-y>'] = cmp.mapping.confirm {
                        behavior = cmp.ConfirmBehavior.Replace,
                        select = true, }, -- Accept ([y]es) the completion. This will expand snippets if the LSP sent a snippet.
          ['<C-Space>'] = cmp.mapping.complete {}, -- Manually trigger a completion from nvim-cmp

          -- Moved to the right or left of the expansion in the snippet.
          ['<C-l>'] = cmp.mapping(function()
            if luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            end
          end, { 'i', 's' }),
          ['<C-h>'] = cmp.mapping(function()
            if luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            end
          end, { 'i', 's' }),

          -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
          --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
        },
        sources = {
          { name = 'nvim_lsp' },
          { name = 'buffer' },
          { name = 'luasnip' },
          { name = 'path' },
          { name = 'pandoc_references' },
          { name = 'cmp_nvim_r' },
        },
        formatting = {
                    format = lspkind.cmp_format({
                        mode = 'symbol_text',
                        maxwidth = 50,
                        ellipsis_char = '...',
                        menu = {
                            nvim_lsp = '[LSP]',
                            luasnip = '[Snippet]',
                            buffer = '[Buffer]',
                            path = '[Path]',
                            pandoc_references = '[Ref]',
                            cmp_nvim_r = '[R]',
                        }
                    })
                },
      }
            -- Command Line completion setup
      cmp.setup.cmdline(':', {
                mapping = cmp.mapping.preset.cmdline(),
                sources = cmp.config.sources({
                    { name = 'path' },
                    { name = 'cmdline' }
                })
            })
      -- Load snippets from snippets directory
      require('luasnip.loaders.from_vscode').lazy_load()
      require('luasnip.loaders.from_vscode').lazy_load { paths = { vim.fn.stdpath 'config' .. '/snippets' } }

      -- Extend filetypes
      luasnip.filetype_extend('quarto', { 'markdown' })
      luasnip.filetype_extend('rmarkdown', { 'markdown' })

      -- Setup cmp specifically for R
        require('cmp_nvim_r').setup({
                filetypes = {'r', 'rmd', 'quarto'},
                doc_width = 58
            })

            -- Setup for bash files
            cmp.setup.filetype({ 'sh', 'bash' }, {
                sources = cmp.config.sources({
                        { name = 'nvim_lsp' },
                        { name = 'luasnip' },
                        { name = 'buffer' },
                        { name = 'path' },
                })
            })
    end,
  },
}
