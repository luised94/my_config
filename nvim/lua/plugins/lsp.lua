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
        local lspconfig = require 'lspconfig'
        local lsputil = require 'lspconfig.util'
        --  This function gets run when an LSP attaches to a particular buffer.
        --    That is to say, every time a new file is opened that is associated with
        --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
        --    function will be executed to configure the current buffer
        vim.api.nvim_create_autocmd('LspAttach', {
          group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
          callback = function(event)
            -- We create a function that lets us more easily define mappings specific
            -- for LSP related items. It sets the mode, buffer and description for us each time.
            local map = function(keys, func, desc)
              vim.keymap.set('n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
            end

            -- Jump to the definition of the word under your cursor.
            --  To jump back, press <C-t>.
            map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')

            -- Find references for the word under your cursor.
            map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')

            -- Jump to the implementation of the word under your cursor.
            map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')

            -- Jump to the type of the word under your cursor.
            map('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')

            -- Fuzzy find all the symbols in your current document, things like variables, functions, types.
            map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')

            -- Fuzzy find all the symbols in your current workspace.
            map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

            -- Rename the variable under your cursor.
            --  Most Language Servers support renaming across files, etc.
            map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')

            -- Execute a code action, usually your cursor needs to be on top of an error
            -- or a suggestion from your LSP for this to activate.
            map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

            -- Opens a popup that displays documentation about the word under your cursor
            --  See `:help K` for why this keymap.
            map('K', vim.lsp.buf.hover, 'Hover Documentation')

            -- WARN: This is not Goto Definition, this is Goto Declaration.
            --  For example, in C this would take you to the header.
            map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

            -- The following two autocommands are used to highlight references of the
            -- word under your cursor when your cursor rests there for a little while.
            --    See `:help CursorHold` for information about when this is executed

            -- When you move your cursor, the highlights will be cleared (the second autocommand).
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
        local border = "rounded" -- other options are single, rounded, shadow, double, solid
        vim.lsp.handlers['textDocument/hover'] = vim.lsp.with(vim.lsp.handlers.hover, { border = border })
        vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = border })
        -- LSP servers and clients are able to communicate to each other what features they support.
        --  By default, Neovim doesn't support everything that is in the LSP specification.
        --  When you add nvim-cmp, luasnip, etc. Neovim now has *more* capabilities.
        --  So, we create new capabilities with nvim cmp, and then broadcast that to the servers.
        local capabilities = vim.lsp.protocol.make_client_capabilities()
        capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())
        -- Enable snippet support for lsp. Tell LSP that neovim can handle snippets in completion.
        capabilities.textDocument.completion.completionItem.snippetSupport = true
        -- Ensure capabilities are initialized.
        if capabilities.workspace == nil then
            capabilities.workspace = {}
        end
        if capabilities.workspace.didChangeWatchedFiles == nil then
            capabilities.workspace.didChangeWatchedFiles = {}
        end
        capabilities.workspace.didChangeWatchedFiles.dynamicRegistration = true

        local lsp_flags = {
            allow_incremental_sync = true, -- Send modified parts of document to LSP.
            debounce_text_changes = 150, -- millisecond delay to send text changes
        }
        local function strsplit(s, delimiter)
            local result = {}
            for match in (s .. delimiter):gmatch('(.-)' .. delimiter) do
                table.insert(result, match)
            end
            return result
        end

        -- Function to get Quarto resource path
        local function get_quarto_resource_path()
                local success, output = pcall(function()
                        local f = assert(io.popen('quarto --paths', 'r'))
                        local s = assert(f:read '*a')
                        f:close()
                        return s
                    end)
                if success then
                    local paths = strsplit(output, '\n')
                    return paths[2]
                else
                    vim.notify('Error getting Quarto path: ' .. tostring(output), vim.log.levels.WARN)
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

        -- Enable the following language servers
        --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
        --  Add any additional override configuration in the following tables. Available keys are:
        --  - cmd (table): Override the default command used to start the server
        --  - filetypes (table): Override the default list of associated filetypes for the server
        --  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
        --  - settings (table): Override the default settings passed when initializing the server.
        local servers = {
          -- Add more servers here. See `:help lspconfig-all` for a list of all the pre-configured LSPs
          bashls = {
                capabilities = capabilities,
                flags = lsp_flags,
                filetypes = { 'sh', 'bash' },
          },
          -- To tell marksman to work with Add to $HOME/.config/marksman the file config.toml with the following text:
          -- [core]
          -- markdown.file_extensions = ["md", "markdown", "qmd"]
          marksman = {
                    capabilities = capabilities,
                    filetypes = { 'markdown', 'quarto'},
                    root_dir = lsputil.root_pattern('.git', '.marksman.toml', '_quarto.yml'),
          },
          yamlls = {
                    capabilities = capabilities,
                    flags = lsp_flags,
                    settings = {
                        yaml = {
                            schemaStore = {
                                enable = true,
                                url ='',
                            },
                        },
                    },
          },
          lua_ls = {
            -- cmd = {...},
            -- filetypes = { ...},
            capabilities = capabilities,
            flags = lsp_flags,
            settings = {
              Lua = {
                completion = {
                  callSnippet = 'Replace',
                },
                runtime = {
                    version = 'LuaJIT',
                    plugin = lua_plugin_paths,
                },
                -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
                diagnostics = {
                    globals = { 'vim' , 'quarto', 'pandoc'}
                    --disable = { 'missing-fields' } 
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
        }

        -- Ensure the servers and tools above are installed
        --  To check the current status of installed tools and/or manually install
        --  other tools, you can run
        --    :Mason

        --  You can press `g?` for help in this menu.
        require('mason').setup()

        -- You can add other tools here that you want Mason to install
        -- for you, so that they are available from within Neovim.
        local ensure_installed = vim.tbl_keys(servers or {})
        vim.list_extend(ensure_installed, {
          'stylua', -- Used to format Lua code
          'shfmt', -- Used to format bash code
        })
        require('mason-tool-installer').setup { ensure_installed = ensure_installed }

        require('mason-lspconfig').setup {
          handlers = {
            function(server_name)
              local server = servers[server_name] or {}
              -- This handles overriding only values explicitly passed
              -- by the server configuration above. Useful when disabling
              -- certain features of an LSP (for example, turning off formatting for tsserver)
              server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
              require('lspconfig')[server_name].setup(server)
            end,
          },
        }
        -- R language setup. 
        -- Mason was unable to install r_language_server. After verifying that R and languageserver package are installed
        -- this runs an R command to run the languageserver::run() function.
        local r_language_server = {
                cmd = function()
                    -- Determine if R is installed or not.
                    if vim.fn.executable('R') == 0 then
                        vim.notify("R is not installed or not in PATH", vim.log.levels.WARN)
                        return nil
                    end
                -- Determine if languageserver package is installed.
                local check_languageserver = io.popen("R --slave -e if(!require('languageserver')) quit(status = 1)")
                local success, exit = check_languageserver:close() -- Ignore warning. If statement below checks close()
                if not success then
                        vim.notify("Error closing languageserver check: " .. tostring(exit), vim.log.levels.ERROR)
                        return nil
                end
                if exit ~= 0 then
                    vim.notify("R languageserver package not installed. Use install.packages.", vim.log.levels.WARN)
                    return nil
                end

                return { "R", "--slave", "-e", "languageserver::run()" }
            end,
            capabilities = capabilities,
            flags = lsp_flags,
            settings = {
                    r = {
                        lsp = {
                            rich_documentation = false
                        }
                    }
                }
            }
            if lspconfig.r_language_server then
                lspconfig.r_language_server.setup(r_language_server)
            else
                vim.notify("r_language_server is not available in lspconfig", vim.log.levels.WARN)
            end
      end,
    },
}

