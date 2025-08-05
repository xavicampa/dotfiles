-- local pid = vim.fn.getpid()

return {
    "mason-org/mason-lspconfig.nvim",
    version = "^1.0.0",
    init = function()
        require("mason-lspconfig").setup_handlers({
            function(server_name) -- default handler (optional)
                require("lspconfig")[server_name].setup({})
            end,
            ["omnisharp"] = function()
                require("lspconfig")["omnisharp"].setup(
                    {
                        -- cmd = { "OmniSharp", "--languageserver", "--hostPID", tostring(pid) },
                        cmd = { "dotnet", vim.fn.stdpath "data" .. "/mason/packages/omnisharp/OmniSharp.dll" },
                        FormattingOptions = {
                            EnableEditorConfigSupport = false,
                        },
                    }
                )
            end,
            ["lua_ls"] = function()
                require("lspconfig")["lua_ls"].setup(
                    {
                        settings = {
                            Lua = {
                                diagnostics = { enable = true, globals = { "vim", "Snacks" } },
                                telemetry = { enable = false },
                            },
                        }
                    }
                )
            end,
        })
    end,
    opts = {
        ensure_installed = {
            "lua_ls",
            "omnisharp",
            "pyright",
            "rnix",
            "ts_ls",
        },
    },
    dependencies = {
        {
            "mason-org/mason.nvim",
            version = "^1.0.0",
        },
        "neovim/nvim-lspconfig"
    }
}
