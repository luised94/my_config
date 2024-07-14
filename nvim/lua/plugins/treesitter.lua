return {
    { -- Highlight, edit, and navigate code
      'nvim-treesitter/nvim-treesitter',
      build = ':TSUpdate',
      dependencies = {
            { 'nvim-treesitter/nvim-treesitter-textobjects'},
        },
      opts = {
        ensure_installed = {
                'bash',
                'c',
                'html',
                'lua',
                'markdown',
                'vim',
                'vimdoc',
                'r',
                'markdown_inline',
                'yaml',
                'vimdoc',
                'css',
                'dot',
                'mermaid',
                'python',
                'latex'

            },
        auto_install = true,
        highlight = {
          enable = true,
          -- Some languages depend on vim's regex highlighting system (such as Ruby) for indent rules.
          --  Add them to additional_vim_regex_highlighting and indent if you have problems.
          additional_vim_regex_highlighting = { 'ruby' },
        },
        indent = { enable = true,
                   disable = { 'ruby'
                   }
        },
        incremental_selection = {
                enable = true,
                keymaps = {
                    init_selection = 'gnn',
                    node_incremental = 'grn',
                    scope_incremental = 'grc',
                    node_decremental = 'grm',
                }
            },
        textobjects = {
                select = {
                    enable = true,
                    lookahead = true,
                    keymaps = {
                        ['af'] = '@function.outer',
                        ['if'] = '@function.inner',
                        ['ac'] = '@class.outer',
                        ['ic'] = '@class.inner',
                    }

                },
                move = {
                    enable = true,
                    set_jumps = true,
                    goto_next_start = {
                        [']m'] = '@function.outer',
                        [']]'] = '@class.inner',
                    },
                    goto_next_end = {
                        [']m'] = '@function.outer',
                        [']]'] = '@class.outer',
                    },
                    goto_previous_start = {
                        ['[m'] = '@function.outer',
                        ['[['] = '@class.inner',
                    },
                    goto_previous_end = {
                        ['[M'] = '@function.outer',
                        ['[]'] = '@class.outer',
                }
            },
      },
    },
      config = function(_, opts)
        -- [[ Configure Treesitter ]] See `:help nvim-treesitter`

        ---@diagnostic disable-next-line: missing-fields
        require('nvim-treesitter.configs').setup(opts)

        -- There are additional nvim-treesitter modules that you can use to interact
        -- with nvim-treesitter. See textobjects and context.
      end,
    },
}

