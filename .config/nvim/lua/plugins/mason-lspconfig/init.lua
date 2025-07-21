-- local pid = vim.fn.getpid()

return {
    "mason-org/mason-lspconfig.nvim",
    version = "^1.0.0",
    init = function()
        require("mason-lspconfig").setup_handlers({
            function(server_name) -- default handler (optional)
                require("lspconfig")[server_name].setup({})
                -- vim.lsp.enable(server_name)
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
                -- vim.lsp.enable("omnisharp")
            end
        })
    end,
    opts = {
        ensure_installed = {
            -- "jdtls", nvim-java
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
