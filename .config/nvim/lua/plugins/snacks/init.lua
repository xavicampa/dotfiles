return {
  "folke/snacks.nvim",
  keys = {
    { "<leader><space>", function() Snacks.picker.smart() end,           desc = "Smart Find Files" },
    { "<leader>,",       function() Snacks.picker.buffers() end,         desc = "Buffers" },
    { "<leader>/",       function() Snacks.picker.grep() end,            desc = "Grep" },
    { "<leader>:",       function() Snacks.picker.command_history() end, desc = "Command History" },
    { "<leader>n",       function() Snacks.picker.notifications() end,   desc = "Notification History" },
    {
      "<leader>e",
      function()
        local explorer_pickers = Snacks.picker.get({ source = "explorer" })
        for _, v in pairs(explorer_pickers) do
          if v:is_focused() then
            v:close()
          else
            v:focus()
          end
        end
        if #explorer_pickers == 0 then
          Snacks.picker.explorer()
        end
      end,
      desc = "File Explorer"
    },
    { "<leader>g", function() Snacks.lazygit.open() end, desc = "Open lazygit" },
  },
  lazy = false,
  opts = {
    animation = {},
    explorer = {
    },
    image = {},
    indent = {},
    input = {},
    lazygit = {},
    notifier = {},
    picker = {
      sources = {
        explorer = {
          win = {
            input = { keys = { ["<C-t>"] = { "tab", mode = { "n", "i" } }, }, },
            list = { keys = { ["<C-t>"] = { "tab", mode = { "n", "i" } }, }, },
          },
        }
      }
    },
    scroll = {},
    terminal = {},
  },
  priority = 1000,
}
