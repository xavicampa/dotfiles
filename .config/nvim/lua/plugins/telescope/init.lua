return {
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    pickers = {
      find_files = {
        hidden = true
      },
      grep_string = {
        additional_args = { "--hidden" }
      },
      live_grep = {
        additional_args = { "--hidden" }
      }
    }
  }
}
