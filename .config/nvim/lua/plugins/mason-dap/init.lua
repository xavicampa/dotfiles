return {
    "jay-babu/mason-nvim-dap.nvim",
    opts = {
        ensure_installed = { "coreclr" },
        handlers = {
            function(config)
                -- all sources with no handler get passed here

                -- Keep original functionality
                require('mason-nvim-dap').default_setup(config)
                -- print(config.name)
            end,
            coreclr = function(config)
                config.adapters = {
                    type = "executable",
                    -- override the command as masons version of netcoredbg does not run in macos
                    -- this var needs to be set in shell.nix
                    command = os.getenv('NETCOREDBG_NIX_PATH') .. "/netcoredbg",
                    args = { "--interpreter=vscode" }
                }
                require('mason-nvim-dap').default_setup(config)
                -- print(config.name)
            end
        },
    },
    dependencies = {
        "mfussenegger/nvim-dap",
        {
            "mason-org/mason.nvim",
            version = "^1.0.0",
        },
    }
}
