local pid = vim.fn.getpid()

-- Mappings.
-- See `:help vim.diagnostic.*` for documentation on any of the below functions
local opts = { noremap = true, silent = true }
vim.keymap.set('n', '<space>e', vim.diagnostic.open_float, opts)
vim.keymap.set('n', '<C-p>', function()
    vim.diagnostic.goto_prev({ float = false })
end, opts)
vim.keymap.set('n', '<C-n>', function()
    vim.diagnostic.goto_next({ float = false })
end, opts)
vim.keymap.set('n', '<space>q', vim.diagnostic.setloclist, opts)

local signs = { Error = " ", Warn = " ", Hint = " ", Info = " " }
for type, icon in pairs(signs) do
    local hl = "DiagnosticSign" .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end

--  Rounded borders
vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
    border = "rounded",
})
vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
    border = "rounded",
})

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach = function(client, bufnr)
    -- Enable completion triggered by <c-x><c-o>
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- Mappings.
    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local bufopts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, bufopts)
    vim.keymap.set('n', '<space>wa', vim.lsp.buf.add_workspace_folder, bufopts)
    vim.keymap.set('n', '<space>wr', vim.lsp.buf.remove_workspace_folder, bufopts)
    vim.keymap.set('n', '<space>wl', function()
        print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, bufopts)
    vim.keymap.set('n', '<space>D', vim.lsp.buf.type_definition, bufopts)
    vim.keymap.set('n', '<space>rn', vim.lsp.buf.rename, bufopts)
    vim.keymap.set('n', '<space>ca', vim.lsp.buf.code_action, bufopts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
    vim.keymap.set('n', '<space>f', vim.lsp.buf.format, bufopts)
end

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach_omnisharp = function(client, bufnr)
    -- Enable completion triggered by <c-x><c-o>
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- Mappings.
    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local bufopts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
    -- vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
    -- vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, bufopts)
    vim.keymap.set('n', '<space>wa', vim.lsp.buf.add_workspace_folder, bufopts)
    vim.keymap.set('n', '<space>wr', vim.lsp.buf.remove_workspace_folder, bufopts)
    vim.keymap.set('n', '<space>wl', function()
        print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, bufopts)
    -- vim.keymap.set('n', '<space>D', vim.lsp.buf.type_definition, bufopts)
    vim.keymap.set('n', '<space>rn', vim.lsp.buf.rename, bufopts)
    vim.keymap.set('n', '<space>ca', vim.lsp.buf.code_action, bufopts)
    -- vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
    vim.keymap.set('n', '<space>f', vim.lsp.buf.format, bufopts)

    -- replaces vim.lsp.buf.definition()
    vim.keymap.set('n', 'gd', '<cmd>lua require("omnisharp_extended").lsp_definition()<cr>', bufopts)

    -- replaces vim.lsp.buf.type_definition()
    vim.keymap.set('n', '<space>D', '<cmd>lua require("omnisharp_extended").lsp_type_definition()<cr>', bufopts)

    -- replaces vim.lsp.buf.references()
    vim.keymap.set('n', 'gr', '<cmd>lua require("omnisharp_extended").lsp_references()<cr>', bufopts)

    -- replaces vim.lsp.buf.implementation()
    vim.keymap.set('n', 'gi', '<cmd>lua require("omnisharp_extended").lsp_implementation()<cr>', bufopts)
end

local lsp_flags = {
    -- This is the default in Nvim 0.7+
    debounce_text_changes = 150,
}
require('lspconfig')['ts_ls'].setup {
    on_attach = on_attach,
    flags = lsp_flags,
}
require('lspconfig')['lemminx'].setup {
    on_attach = on_attach,
    flags = lsp_flags,
}
require('lspconfig')['pyright'].setup {
    on_attach = on_attach,
    flags = lsp_flags,
}
-- require('lspconfig')['pylsp'].setup {
--     on_attach = on_attach,
--     flags = lsp_flags,
-- }
-- require('lspconfig')['gopls'].setup {
--     on_attach = on_attach,
--     flags = lsp_flags,
-- }
require('lspconfig')['omnisharp'].setup {
    cmd = { "OmniSharp", "--languageserver", "--hostPID", tostring(pid) },
    on_attach = on_attach_omnisharp,
    flags = lsp_flags,
    settings = {
        FormattingOptions = {
            --         -- Enables support for reading code style, naming convention and analyzer
            --         -- settings from .editorconfig.
            EnableEditorConfigSupport = false,
            --         -- Specifies whether 'using' directives should be grouped and sorted during
            --         -- document formatting.
            -- OrganizeImports = true,
        },
        --     MsBuild = {
        --         -- If true, MSBuild project system will only load projects for files that
        --         -- were opened in the editor. This setting is useful for big C# codebases
        --         -- and allows for faster initialization of code navigation features only
        --         -- for projects that are relevant to code that is being edited. With this
        --         -- setting enabled OmniSharp may load fewer projects and may thus display
        --         -- incomplete reference lists for symbols.
        --         LoadProjectsOnDemand = nil,
        --     },
        --     RoslynExtensionsOptions = {
        --         -- Enables support for roslyn analyzers, code fixes and rulesets.
        --         EnableAnalyzersSupport = nil,
        --         -- Enables support for showing unimported types and unimported extension
        --         -- methods in completion lists. When committed, the appropriate using
        --         -- directive will be added at the top of the current file. This option can
        --         -- have a negative impact on initial completion responsiveness,
        --         -- particularly for the first few completion sessions after opening a
        --         -- solution.
        --         EnableImportCompletion = nil,
        --         -- Only run analyzers against open files when 'enableRoslynAnalyzers' is
        --         -- true
        --         AnalyzeOpenDocumentsOnly = nil,
        --     },
        Sdk = {
            --         -- Specifies whether to include preview versions of the .NET SDK when
            --         -- determining which version to use for project loading.
            IncludePrereleases = false,
        },
    },
}
require('lspconfig')['lua_ls'].setup {
    on_attach = on_attach,
    flags = lsp_flags,
    settings = {
        Lua = {
            runtime = {
                -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
                version = 'LuaJIT',
            },
            diagnostics = {
                -- Get the language server to recognize the `vim` global
                globals = { 'vim' },
            },
            workspace = {
                -- Make the server aware of Neovim runtime files
                library = vim.api.nvim_get_runtime_file("", true),
            },
            -- Do not send telemetry data containing a randomized but unique identifier
            telemetry = {
                enable = false,
            },
        },
    },
}
-- require('lspconfig')['rnix'].setup {
--     on_attach = on_attach,
--     flags = lsp_flags,
-- }

require('lspconfig')['nixd'].setup {
    on_attach = on_attach,
    flags = lsp_flags,
    settings = {
        nixd = {
            formatting = {
                command = { "nixpkgs-fmt" },
            }
        }
    }
}

-- require('lspconfig')['rust_analyzer'].setup {
--     on_attach = on_attach,
--     flags = lsp_flags,
--     settings = {
--         ["rust-analyzer"] = {
--             imports = {
--                 granularity = {
--                     group = "module",
--                 },
--                 prefix = "self",
--             },
--             cargo = {
--                 buildScripts = {
--                     enable = true,
--                 },
--             },
--             procMacro = {
--                 enable = true
--             },
--         }
--     }
-- }

require('null-ls').setup {
    on_attach = on_attach,
    flags = lsp_flags,
    sources = {
        require("null-ls").builtins.formatting.black,
        require("null-ls").builtins.formatting.prettier,
        require("null-ls").builtins.diagnostics.cfn_lint.with({
            args = {
                '-i', 'W3002', -- Do not try to parse nested stack's TemplateURL
                '-i', 'E3043', -- Do not try to parse nested stack's TemplateURL
                '--format', 'parseable',
                '--'
            }
        }),
        require("null-ls").builtins.diagnostics.checkstyle.with({
            args = function(params)
                return {
                    "-f",
                    "sarif",
                    "-c",
                    vim.fn.expand("~/dev/nas/nas_checkstyle.xml"),
                    params.bufname,
                }
            end
        })
    },
    -- debug = true,
}

require('lspconfig')['marksman'].setup {
    on_attach = on_attach,
    flags = lsp_flags,
}

require 'lspconfig'.jdtls.setup {
    on_attach = on_attach,
    flags = lsp_flags,
}

require 'lspconfig'.gopls.setup {
    on_attach = on_attach,
    flags = lsp_flags,
}
