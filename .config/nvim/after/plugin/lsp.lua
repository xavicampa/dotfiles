require 'lspconfig'.ts_ls.setup {}
require 'lspconfig'.lemminx.setup {}
require 'lspconfig'.pyright.setup {}
require 'lspconfig'.marksman.setup {}
require 'lspconfig'.jdtls.setup {}
require 'lspconfig'.gopls.setup {}

local pid = vim.fn.getpid()
require('lspconfig')['omnisharp'].setup {
    cmd = { "OmniSharp", "--languageserver", "--hostPID", tostring(pid) },
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

require('lspconfig')['nixd'].setup {
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
    -- debug = true,
    sources = {
        require("null-ls").builtins.code_actions.gitsigns,
        require("null-ls").builtins.formatting.black,
        require("null-ls").builtins.formatting.prettier,
        require("null-ls").builtins.diagnostics.write_good,
        require("null-ls").builtins.diagnostics.cfn_lint.with({
            extra_args = {
                -- '-i', 'W3002', -- Do not try to parse nested stack's TemplateURL
                -- '-i', 'E3043', -- Do not try to parse nested stack's TemplateURL
                '-c', 'I', --  Include suggestions and best practices
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
}
