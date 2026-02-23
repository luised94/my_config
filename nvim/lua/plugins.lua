-- lua/plugins.lua
local api     = vim.api
local fn      = vim.fn
local keymap  = vim.keymap

-- =============================================================================
-- CONSTANTS
-- =============================================================================

---@type string[]
local TREESITTER_LANGUAGES = {
    'bash', 'c', 'html', 'lua', 'markdown', 'vim', 'r',
    'markdown_inline', 'yaml', 'vimdoc', 'css', 'dot',
    'mermaid', 'python', 'latex',
}

---@class CompletionSource
---@field name string
---@field keyword_length integer|nil
---@field max_item_count integer|nil

---@type CompletionSource[]
local COMPLETION_SOURCES = {
    { name = 'nvim_lsp' },
    { name = 'buffer',            keyword_length = 5, max_item_count = 5 },
    { name = 'luasnip' },
    { name = 'path' },
    { name = 'pandoc_references' },
    { name = 'otter' },
    { name = 'nvim_lsp_signature_help' },
}

---@class CompletionWindow
---@field documentation table
local COMPLETION_WINDOW = {
    documentation = { border = "rounded" },
}

---@class SnippetFiletypeExtend
---@field ft string
---@field extends string[]

---@type SnippetFiletypeExtend[]
local SNIPPET_FILETYPE_EXTENDS = {
    { ft = 'quarto',    extends = { 'markdown' } },
    { ft = 'rmarkdown', extends = { 'markdown' } },
}

---@class BibtexCustomFormat
---@field id string
---@field cite_maker string

---@class BibtexConfig
---@field depth integer
---@field global_files string[]
---@field search_keys string[]
---@field citation_format string
---@field citation_trim_firstname boolean
---@field citation_max_auth integer
---@field custom_formats BibtexCustomFormat[]
---@field format string
---@field context boolean
---@field context_fallback boolean
---@field wrap boolean
local BIBTEX_CONFIG = {
    depth                  = 1,
    global_files           = { '~/mylibrary.bib' },
    search_keys            = { 'author', 'year', 'title', 'citekey' },
    citation_format        = '@{{citekey}}',
    citation_trim_firstname = true,
    citation_max_auth      = 2,
    custom_formats = {
        { id = 'qcite',  cite_maker = '@{{citekey}}' },
        { id = 'qcites', cite_maker = '[@{{citekey}}; @{{citekey}}]' },
    },
    format           = 'qcite',
    context          = false,
    context_fallback = false,
    wrap             = false,
}

-- =============================================================================
-- FILE-SCOPE HELPERS
-- =============================================================================

---@return string|nil
local function get_quarto_resource_path()
    local quarto_path = fn.exepath('quarto')
    if quarto_path == '' then
        vim.notify('[lsp] quarto executable not found in PATH', vim.log.levels.WARN)
        return nil
    end
    local handle = io.popen('quarto --paths 2>&1', 'r')
    if handle == nil then
        vim.notify('[lsp] failed to execute quarto --paths', vim.log.levels.ERROR)
        return nil
    end
    local result = handle:read('*a')
    local success = handle:close()
    if not success then
        vim.notify('[lsp] quarto --paths command failed', vim.log.levels.ERROR)
        return nil
    end
    local lines = {}
    for line in result:gmatch('[^\r\n]+') do
        table.insert(lines, line)
    end
    local resource_path = lines[2]
    if resource_path ~= nil and fn.isdirectory(resource_path) == 1 then
        return resource_path
    end
    vim.notify('[lsp] quarto share directory not found in output', vim.log.levels.WARN)
    return nil
end

-- =============================================================================
-- PLUGIN SPECS
-- =============================================================================

return {

    -- -------------------------------------------------------------------------
    -- Colorscheme
    -- -------------------------------------------------------------------------
    {
        'folke/tokyonight.nvim',
        priority = 1000,
        init = function()
            vim.cmd.colorscheme('tokyonight-night')
            vim.cmd.hi('Comment gui=none')
        end,
    },

    -- -------------------------------------------------------------------------
    -- Which-key
    -- -------------------------------------------------------------------------
    {
        'folke/which-key.nvim',
        event = 'VeryLazy',
        opts = {},
        keys = {
            {
                '<leader>?',
                function()
                    require('which-key').show({ global = false })
                end,
                desc = 'which-key: show buffer local keymaps',
            },
        },
    },

    -- -------------------------------------------------------------------------
    -- Habit breaking
    -- -------------------------------------------------------------------------
    {
        'm4xshen/hardtime.nvim',
        dependencies = { 'MunifTanjim/nui.nvim', 'nvim-lua/plenary.nvim' },
        opts = {},
    },
    {
        'tris203/precognition.nvim',
        event = 'VeryLazy',
        opts = {},
    },

    -- -------------------------------------------------------------------------
    -- Autopairs
    -- -------------------------------------------------------------------------
    {
        'echasnovski/mini.pairs',
        version = '*',
        config = function()
            require('mini.pairs').setup()
        end,
    },

    -- -------------------------------------------------------------------------
    -- Treesitter
    -- -------------------------------------------------------------------------
    {
        'nvim-treesitter/nvim-treesitter',
        build = ':TSUpdate',
        dependencies = {
            { 'nvim-treesitter/nvim-treesitter-textobjects' },
        },
        opts = {
            ensure_installed = TREESITTER_LANGUAGES,
            auto_install = true,
            highlight = {
                enable = true,
                additional_vim_regex_highlighting = { 'ruby' },
            },
            indent = {
                enable = true,
                disable = { 'ruby' },
            },
            incremental_selection = {
                enable = true,
                keymaps = {
                    init_selection    = 'gnn',
                    node_incremental  = 'grn',
                    scope_incremental = 'grc',
                    node_decremental  = 'grm',
                },
            },
            textobjects = {
                select = {
                    enable    = true,
                    lookahead = true,
                    keymaps = {
                        ['af'] = '@function.outer',
                        ['if'] = '@function.inner',
                        ['ac'] = '@class.outer',
                        ['ic'] = '@class.inner',
                    },
                },
                move = {
                    enable     = true,
                    set_jumps  = true,
                    goto_next_start = {
                        [']m'] = '@function.outer',
                        [']]'] = '@class.inner',
                    },
                    goto_next_end = {
                        [']m'] = '@function.outer',  -- NOTE: duplicates goto_next_start key
                        [']]'] = '@class.outer',     -- NOTE: duplicates goto_next_start key
                    },
                    goto_previous_start = {
                        ['[m'] = '@function.outer',
                        ['[['] = '@class.inner',
                    },
                    goto_previous_end = {
                        ['[M'] = '@function.outer',
                        ['[]'] = '@class.outer',
                    },
                },
            },
        },
        config = function(_, opts)
            ---@diagnostic disable-next-line: missing-fields
            require('nvim-treesitter.configs').setup(opts)
        end,
    },

    -- -------------------------------------------------------------------------
    -- Telescope
    -- -------------------------------------------------------------------------
    {
        'nvim-telescope/telescope.nvim',
        event  = 'VimEnter',
        branch = '0.1.x',
        dependencies = {
            'nvim-lua/plenary.nvim',
            {
                'nvim-telescope/telescope-fzf-native.nvim',
                build = 'make',
                cond  = function()
                    return fn.executable('make') == 1
                end,
            },
            { 'nvim-telescope/telescope-ui-select.nvim' },
            { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
            'nvim-telescope/telescope-bibtex.nvim',
        },
        config = function()
            require('telescope').setup({
                extensions = {
                    ['ui-select'] = { require('telescope.themes').get_dropdown() },
                    bibtex        = BIBTEX_CONFIG,
                },
            })

            pcall(require('telescope').load_extension, 'fzf')
            pcall(require('telescope').load_extension, 'ui-select')
            pcall(require('telescope').load_extension, 'bibtex')

            local builtin = require('telescope.builtin')

            ---@class TelescopeKeymapSpec
            ---@field lhs string
            ---@field rhs function
            ---@field opts table

            ---@type TelescopeKeymapSpec[]
            local TELESCOPE_KEYMAPS = {
                { lhs = '<leader>sh',       rhs = builtin.help_tags,   opts = { desc = 'telescope: search help' } },
                { lhs = '<leader>sk',       rhs = builtin.keymaps,     opts = { desc = 'telescope: search keymaps' } },
                { lhs = '<leader>sf',       rhs = builtin.find_files,  opts = { desc = 'telescope: search files' } },
                { lhs = '<leader>ss',       rhs = builtin.builtin,     opts = { desc = 'telescope: select picker' } },
                { lhs = '<leader>sw',       rhs = builtin.grep_string, opts = { desc = 'telescope: search current word' } },
                { lhs = '<leader>sg',       rhs = builtin.live_grep,   opts = { desc = 'telescope: search by grep' } },
                { lhs = '<leader>sd',       rhs = builtin.diagnostics, opts = { desc = 'telescope: search diagnostics' } },
                { lhs = '<leader>sr',       rhs = builtin.resume,      opts = { desc = 'telescope: search resume' } },
                { lhs = '<leader>s.',       rhs = builtin.oldfiles,    opts = { desc = 'telescope: search recent files' } },
                { lhs = '<leader><leader>', rhs = builtin.buffers,     opts = { desc = 'telescope: find existing buffers' } },
                {
                    lhs = '<leader>/',
                    rhs = function()
                        builtin.current_buffer_fuzzy_find(
                            require('telescope.themes').get_dropdown({ winblend = 10, previewer = false })
                        )
                    end,
                    opts = { desc = 'telescope: fuzzy search current buffer' },
                },
                {
                    lhs = '<leader>s/',
                    rhs = function()
                        builtin.live_grep({ grep_open_files = true, prompt_title = 'Live Grep in Open Files' })
                    end,
                    opts = { desc = 'telescope: search in open files' },
                },
                {
                    lhs = '<leader>sn',
                    rhs = function()
                        builtin.find_files({ cwd = fn.stdpath('config') })
                    end,
                    opts = { desc = 'telescope: search neovim files' },
                },
            }

            for _, km in ipairs(TELESCOPE_KEYMAPS) do
                keymap.set('n', km.lhs, km.rhs, km.opts)
            end
        end,
    },

    -- -------------------------------------------------------------------------
    -- LSP
    -- -------------------------------------------------------------------------
    {
        'neovim/nvim-lspconfig',
        dependencies = {
            'williamboman/mason.nvim',
            'williamboman/mason-lspconfig.nvim',
            'WhoIsSethDaniel/mason-tool-installer.nvim',
            { 'j-hui/fidget.nvim',  opts = {} },
            { 'folke/neodev.nvim',  opts = {}, enabled = false },
            { 'folke/neoconf.nvim', opts = {}, enabled = false },
        },
        config = function()
            local lsputil = require('lspconfig.util')

            api.nvim_create_autocmd('LspAttach', {
                group    = api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
                callback = function(event)
                    ---@param keys string
                    ---@param func function
                    ---@param desc string
                    ---@return nil
                    local function map(keys, func, desc)
                        keymap.set('n', keys, func, {
                            buffer = event.buf,
                            desc   = string.format('lsp: %s', desc),
                        })
                    end

                    local builtin = require('telescope.builtin')
                    map('gd',         builtin.lsp_definitions,               'go to definition')
                    map('gr',         builtin.lsp_references,                'go to references')
                    map('gI',         builtin.lsp_implementations,           'go to implementation')
                    map('<leader>D',  builtin.lsp_type_definitions,          'type definition')
                    map('<leader>ds', builtin.lsp_document_symbols,          'document symbols')
                    map('<leader>ws', builtin.lsp_dynamic_workspace_symbols, 'workspace symbols')
                    map('<leader>rn', vim.lsp.buf.rename,                    'rename')
                    map('<leader>ca', vim.lsp.buf.code_action,               'code action')
                    map('K',          vim.lsp.buf.hover,                     'hover documentation')
                    map('gD',         vim.lsp.buf.declaration,               'go to declaration')

                    local client = vim.lsp.get_client_by_id(event.data.client_id)
                    if client ~= nil and client.server_capabilities.documentHighlightProvider then
                        api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
                            buffer   = event.buf,
                            callback = vim.lsp.buf.document_highlight,
                        })
                        api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
                            buffer   = event.buf,
                            callback = vim.lsp.buf.clear_references,
                        })
                    end
                end,
            })

            local border = "rounded"
            vim.lsp.handlers['textDocument/hover'] = vim.lsp.with(
                vim.lsp.handlers.hover, { border = border }
            )
            vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.with(
                vim.lsp.handlers.signature_help, { border = border }
            )

            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities = vim.tbl_deep_extend(
                'force', capabilities, require('cmp_nvim_lsp').default_capabilities()
            )
            capabilities.textDocument.completion.completionItem.snippetSupport = true
            if capabilities.workspace == nil then
                capabilities.workspace = {}
            end
            if capabilities.workspace.didChangeWatchedFiles == nil then
                capabilities.workspace.didChangeWatchedFiles = {}
            end
            capabilities.workspace.didChangeWatchedFiles.dynamicRegistration = true

            local lua_library_files = api.nvim_get_runtime_file('', true)
            local lua_plugin_paths  = {}
            local resource_path     = get_quarto_resource_path()
            if resource_path ~= nil then
                table.insert(lua_library_files, resource_path .. '/lua-types')
                table.insert(lua_plugin_paths,  resource_path .. '/lua-plugin/plugin.lua')
            else
                vim.notify('[lsp] quarto not found, lua library files not loaded', vim.log.levels.WARN)
            end

            ---@class LspServerConfig
            ---@field filetypes string[]|nil
            ---@field settings table|nil
            ---@field root_dir function|nil

            ---@type table<string, LspServerConfig>
            local LSP_SERVERS = {
                bashls = {
                    filetypes = { 'sh', 'bash' },
                },
                marksman = {
                    filetypes = { 'markdown', 'quarto' },
                    root_dir  = lsputil.root_pattern('.git', '.marksman.toml', '_quarto.yml'),
                },
                yamlls = {
                    settings = {
                        yaml = {
                            schemaStore = { enable = true, url = '' },
                        },
                    },
                },
                lua_ls = {
                    settings = {
                        Lua = {
                            completion  = { callSnippet = 'Replace' },
                            runtime     = { version = 'LuaJIT', plugin = lua_plugin_paths },
                            diagnostics = { globals = { 'vim', 'quarto', 'pandoc' } },
                            workspace   = { library = lua_library_files, checkThirdParty = false },
                            telemetry   = { enable = false },
                        },
                    },
                },
                zls = {
                    filetypes = { 'zig' },
                    settings  = {
                        zls = { enable_snippets = true, enable_autofix = true },
                    },
                },
            }

            require('mason').setup()

            local ensure_installed = vim.tbl_keys(LSP_SERVERS)
            require('mason-tool-installer').setup({ ensure_installed = ensure_installed })

            require('mason-lspconfig').setup({
                ensure_installed = ensure_installed,
                handlers = {
                    function(server_name)
                        local server = LSP_SERVERS[server_name] or {}
                        server.capabilities = vim.tbl_deep_extend(
                            'force', {}, capabilities, server.capabilities or {}
                        )
                        vim.lsp.config(server_name, server)
                        vim.lsp.enable(server_name)
                    end,
                },
            })

            vim.lsp.config('r_language_server', {
                cmd          = { 'R', '--slave', '-e', 'languageserver::run()' },
                capabilities = capabilities,
                filetypes    = { 'r', 'rmd', 'quarto' },
                root_dir     = function(fname)
                    return lsputil.root_pattern('.git', '_quarto.yml', '.Rproj.user')(fname)
                        or lsputil.find_git_ancestor(fname)
                        or fn.fnamemodify(fname, ':p:h')
                end,
                settings = { r = { lsp = { rich_documentation = false } } },
            })
            vim.lsp.enable('r_language_server')
        end,
    },

    -- -------------------------------------------------------------------------
    -- Autocompletion
    -- -------------------------------------------------------------------------
    {
        'hrsh7th/nvim-cmp',
        event = 'InsertEnter',
        dependencies = {
            {
                'L3MON4D3/LuaSnip',
                version = 'v2.*',
                build   = 'make install_jsregexp',
                dependencies = {
                    'rafamadriz/friendly-snippets',
                    'benfowler/telescope-luasnip.nvim',
                },
            },
            'hrsh7th/cmp-buffer',
            'onsails/lspkind-nvim',
            'jmbuhr/cmp-pandoc-references',
            'saadparwaiz1/cmp_luasnip',
            'hrsh7th/cmp-nvim-lsp',
            'hrsh7th/cmp-path',
            'hrsh7th/cmp-cmdline',
            'jmbuhr/otter.nvim',
        },
        config = function()
            local cmp      = require('cmp')
            local luasnip  = require('luasnip')
            local lspkind  = require('lspkind')

            require('luasnip.loaders.from_vscode').lazy_load()
            require('luasnip.loaders.from_vscode').lazy_load({
                paths = { fn.stdpath('config') .. '/snippets' },
            })

            luasnip.config.setup({})

            for _, ext in ipairs(SNIPPET_FILETYPE_EXTENDS) do
                luasnip.filetype_extend(ext.ft, ext.extends)
            end

            cmp.setup({
                snippet = {
                    expand = function(args)
                        luasnip.lsp_expand(args.body)
                    end,
                },
                completion = { completeopt = 'menu,menuone,noinsert' },
                mapping    = cmp.mapping.preset.insert({
                    ['<C-n>']     = cmp.mapping.select_next_item(),
                    ['<C-p>']     = cmp.mapping.select_prev_item(),
                    ['<C-b>']     = cmp.mapping.scroll_docs(-4),
                    ['<C-f>']     = cmp.mapping.scroll_docs(4),
                    ['<C-y>']     = cmp.mapping.confirm({
                                        behavior = cmp.ConfirmBehavior.Replace,
                                        select   = true,
                                    }),
                    ['<C-Space>'] = cmp.mapping.complete({}),
                    ['<C-l>']     = cmp.mapping(function()
                                        if luasnip.expand_or_locally_jumpable() then
                                            luasnip.expand_or_jump()
                                        end
                                    end, { 'i', 's' }),
                    ['<C-h>']     = cmp.mapping(function()
                                        if luasnip.locally_jumpable(-1) then
                                            luasnip.jump(-1)
                                        end
                                    end, { 'i', 's' }),
                }),
                sources = COMPLETION_SOURCES,
                formatting = {
                    format = lspkind.cmp_format({
                        mode         = 'symbol_text',
                        maxwidth     = 50,
                        ellipsis_char = '...',
                        menu = {
                            nvim_lsp          = '[LSP]',
                            luasnip           = '[Snippet]',
                            buffer            = '[Buffer]',
                            path              = '[Path]',
                            pandoc_references = '[Ref]',
                            otter             = '[otter]',
                        },
                    }),
                },
                window = COMPLETION_WINDOW,
            })

            cmp.setup.cmdline(':', {
                mapping = cmp.mapping.preset.cmdline(),
                sources = cmp.config.sources({
                    { name = 'path' },
                    { name = 'cmdline' },
                }),
            })

            cmp.setup.cmdline('/', {
                mapping = cmp.mapping.preset.cmdline(),
                sources = { { name = 'buffer' } },
            })

            cmp.setup.filetype({ 'sh', 'bash' }, {
                sources = cmp.config.sources({
                    { name = 'nvim_lsp' },
                    { name = 'luasnip' },
                    { name = 'buffer' },
                    { name = 'path' },
                }),
            })
        end,
    },

    -- -------------------------------------------------------------------------
    -- Quarto
    -- -------------------------------------------------------------------------
    {
        'quarto-dev/quarto-nvim',
        ft  = { 'quarto' },
        dev = false,
        opts = {
            lspFeatures = {
                languages = {
                    'r', 'python', 'julia', 'bash', 'lua',
                    'html', 'dot', 'javascript', 'typescript', 'ojs',
                },
            },
            codeRunner = {
                enabled        = true,
                default_method = 'slime',
            },
        },
        dependencies = {
            {
                'jmbuhr/otter.nvim',
                dev          = false,
                dependencies = { { 'neovim/nvim-lspconfig' } },
                opts = {
                    lsp     = { hover = { border = "rounded" } },
                    buffers = { set_filetype = true },
                    handle_leading_whitespace = true,
                },
            },
        },
    },

}
