return {
  "NickvanDyke/opencode.nvim",
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      port = 12345
    }
    vim.o.autoread = true
  end
}
