return {
    "mason-org/mason-lspconfig.nvim",
    version = "^1.0.0",
    -- init = function()
    --     require("lspconfig").lua_ls.setup({})
    -- end,
    opts = {
        ensure_installed = { "lua_ls" },
        automatic_enable = true
    },
    dependencies = {
        {
            "mason-org/mason.nvim",
            version = "^1.0.0",
            opts = {
            },
        },
        "neovim/nvim-lspconfig"
    }
}
