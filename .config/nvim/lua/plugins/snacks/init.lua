return {
    "folke/snacks.nvim",
    keys = {
        { "<leader>gg", function () Snacks.lazygit.open() end, desc = "Open lazygit" },
    },
    lazy = false,
    opts = {
        animation = {},
        dashboard = {},
        dim = {},
        indent = {},
        lazygit = {},
        scroll = {},
        terminal = {},
    },
    priority = 1000,
}
