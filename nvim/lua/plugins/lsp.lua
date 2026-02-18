
return {
    { -- LSP Configuration & Plugins
      'neovim/nvim-lspconfig',
      dependencies = {
        -- Automatically install LSPs and related tools to stdpath for Neovim
        'williamboman/mason.nvim',
        'williamboman/mason-lspconfig.nvim',
        'WhoIsSethDaniel/mason-tool-installer.nvim',
        { 'j-hui/fidget.nvim', opts = {} }, -- Useful status updates for LSP.
        { 'folke/neodev.nvim', opts = {}, enabled = false }, -- `neodev` configures Lua LSP for your Neovim config, runtime and plugins
        { 'folke/neoconf.nvim', opts = {}, enabled = false }, -- used for completion, annotations and signatures of Neovim apis
      },
      config = function()
        local lsputil = require 'lspconfig.util'

        --  This function gets run when an LSP attaches to a particular buffer.
        vim.api.nvim_create_autocmd('LspAttach', {
          group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
          callback = function(event)
            local map = function(keys, func, desc)
              vim.keymap.set('n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
            end

            map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
            map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
            map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
            map('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
            map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
            map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')
            map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
            map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')
            map('K', vim.lsp.buf.hover, 'Hover Documentation')
            map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

            local client = vim.lsp.get_client_by_id(event.data.client_id)
            if client and client.server_capabilities.documentHighlightProvider then
              vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
                buffer = event.buf,
                callback = vim.lsp.buf.document_highlight,
              })
              vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
                buffer = event.buf,
                callback = vim.lsp.buf.clear_references,
              })
            end
          end,
        })

        -- Add borders to floating windows.
        local border = "rounded"
        vim.lsp.handlers['textDocument/hover'] = vim.lsp.with(vim.lsp.handlers.hover, { border = border })
        vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = border })

        -- LSP servers and clients capabilities
        local capabilities = vim.lsp.protocol.make_client_capabilities()
        capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())
        capabilities.textDocument.completion.completionItem.snippetSupport = true

        if capabilities.workspace == nil then
            capabilities.workspace = {}
        end
        if capabilities.workspace.didChangeWatchedFiles == nil then
            capabilities.workspace.didChangeWatchedFiles = {}
        end
        capabilities.workspace.didChangeWatchedFiles.dynamicRegistration = true

        -- FIXED: More robust Quarto resource path detection
        local function get_quarto_resource_path()
            -- First check if quarto is in PATH
            local quarto_path = vim.fn.exepath('quarto')
            if quarto_path == '' then
                vim.notify('Quarto executable not found in PATH', vim.log.levels.WARN)
                return nil
            end

            -- Try to get quarto paths
            local handle = io.popen('quarto --paths 2>&1', 'r')
            if not handle then
                vim.notify('Failed to execute quarto --paths', vim.log.levels.ERROR)
                return nil
            end

            local result = handle:read('*a')
            local success = handle:close()

            if not success then
                vim.notify('quarto --paths command failed', vim.log.levels.ERROR)
                return nil
            end

            -- Parse output: quarto --paths returns multiple lines
            -- Line 1: Installation directory
            -- Line 2: Share directory (what we need)
            -- Line 3: Binary path
            local lines = {}
            for line in result:gmatch('[^\r\n]+') do
                table.insert(lines, line)
            end

            -- The share path is typically the second line
            local resource_path = lines[2]

            if resource_path and vim.fn.isdirectory(resource_path) == 1 then
                return resource_path
            else
                vim.notify('Quarto share directory not found in output', vim.log.levels.WARN)
                return nil
            end
        end

        -- Gather Neovim runtime files and prepare for Quarto integration
        local lua_library_files = vim.api.nvim_get_runtime_file('', true)
        local lua_plugin_paths = {}
        local resource_path = get_quarto_resource_path()

        if resource_path then
            table.insert(lua_library_files, resource_path .. '/lua-types')
            table.insert(lua_plugin_paths, resource_path .. '/lua-plugin/plugin.lua')
        else
            vim.notify('Quarto not found or error occurred, lua library files not loaded', vim.log.levels.WARN)
        end

        -- [[ SERVER CONFIGURATION ]]
        local servers = {
          bashls = {
                capabilities = capabilities,
                filetypes = { 'sh', 'bash' },
          },
          marksman = {
                    capabilities = capabilities,
                    filetypes = { 'markdown', 'quarto'},
                    root_dir = lsputil.root_pattern('.git', '.marksman.toml', '_quarto.yml'),
          },
          yamlls = {
                    capabilities = capabilities,
                    settings = {
                        yaml = {
                            schemaStore = {
                                enable = true,
                                url = '',
                            },
                        },
                    },
          },
          lua_ls = {
            capabilities = capabilities,
            settings = {
              Lua = {
                completion = {
                  callSnippet = 'Replace',
                },
                runtime = {
                    version = 'LuaJIT',
                    plugin = lua_plugin_paths,
                },
                diagnostics = {
                    globals = { 'vim' , 'quarto', 'pandoc'}
                },
                workspace = {
                    library = lua_library_files,
                    checkThirdParty = false,
                },
                telemetry = {
                    enable = false,
                },
              },
            },
          },
          zls = {
              capabilities = capabilities,
              filetypes = { 'zig' },
              settings = {
                zls = {
                  enable_snippets = true,
                  enable_autofix = true,
                },
              },
          },
        }

        require('mason').setup()

        local ensure_installed = vim.tbl_keys(servers or {})
        vim.list_extend(ensure_installed, {
          'zls',
        })

        require('mason-tool-installer').setup {
          ensure_installed = ensure_installed
        }

        -- MIGRATION: New vim.lsp.config API for Neovim 0.11+
        require('mason-lspconfig').setup {
          ensure_installed = ensure_installed,
          handlers = {
            -- Default handler using new API
            function(server_name)
              local server = servers[server_name] or {}
              server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})

              -- Use new vim.lsp.config API
              vim.lsp.config(server_name, server)
              vim.lsp.enable(server_name)
            end,
          },
        }

        -- R language server setup (not managed by Mason)
        -- MIGRATION: Using new API for r_language_server
        vim.lsp.config('r_language_server', {
            cmd = { "R", "--slave", "-e", "languageserver::run()" },
            capabilities = capabilities,
            filetypes = { 'r', 'rmd', 'quarto' },
            root_dir = function(fname)
                return lsputil.root_pattern('.git', '_quarto.yml', '.Rproj.user')(fname)
                    or lsputil.find_git_ancestor(fname)
                    or vim.fn.fnamemodify(fname, ':p:h')
            end,
            settings = {
                r = {
                    lsp = {
                        rich_documentation = false
                    }
                }
            }
        })

        -- Enable R language server for its filetypes
        vim.lsp.enable('r_language_server')
      end,
    },
}
