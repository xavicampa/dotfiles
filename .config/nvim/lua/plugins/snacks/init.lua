return {
    "folke/snacks.nvim",
    keys = {
        {"<leader>gg", "<cmd>lua Snacks.lazygit.open()<CR>"},
    },
    opts = {
        lazygit = {},
        scroll = {},
    },
    priority = 1000,
}
