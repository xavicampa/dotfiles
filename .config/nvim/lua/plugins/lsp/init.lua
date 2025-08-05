return {
    "neovim/nvim-lspconfig",
    init = function()
        -- Configure default global language servers
        vim.lsp.config("lua_ls", {
            settings = {
                Lua = {
                    runtime = { version = "LuaJIT" },
                    diagnostics = {
                        enable = true,
                        globals = {
                            "vim"
                        },
                    },
                    telemetry = { enable = false },
                    workspace = {
                        library = { vim.env.VIMRUNTIME },
                        checkThirdParty = false,
                    },
                },
            }
        })
        vim.lsp.config("nixd", {
            settings = {
                nixd = {
                    nixpkgs = {
                        expr = "import <nixpkgs> { }",
                    },
                    formatting = {
                        command = { "nixfmt" },
                    },
                    options = {
                        home_manager = {
                            expr =
                            "(import <home-manager/modules> { configuration = ~/.config/home-manager/home.nix; pkgs = import <nixpkgs> {}; }).options"
                        }
                    }
                }
            }
        })

        -- Enable LSPs
        vim.lsp.enable(
            {
                "nixd",
                "lua_ls",
            }
        )
    end,
}
