return {
    "folke/snacks.nvim",
    keys = {
        { "<leader><space>", function() Snacks.picker.smart() end,           desc = "Smart Find Files" },
        { "<leader>,",       function() Snacks.picker.buffers() end,         desc = "Buffers" },
        { "<leader>/",       function() Snacks.picker.grep() end,            desc = "Grep" },
        { "<leader>:",       function() Snacks.picker.command_history() end, desc = "Command History" },
        { "<leader>n",       function() Snacks.picker.notifications() end,   desc = "Notification History" },
        { "<leader>e",       function() Snacks.explorer() end,               desc = "File Explorer" },
        { "<leader>g",       function() Snacks.lazygit.open() end,           desc = "Open lazygit" },
    },
    lazy = false,
    opts = {
        animation = {},
        dashboard = {},
        image = {},
        indent = {},
        lazygit = {},
        notifier = {},
        picker = {
            sources = {
                explorer = {
                    auto_close = true,
                }
            }
        },
        scroll = {},
        terminal = {},
    },
    priority = 1000,
}
