return {
  "ggml-org/llama.vim",
  init = function()
    vim.g.llama_config = {
      show_info = 0,

      -- endpoint = "https://router.huggingface.co/v1"
      endpoint = "http://localhost:8082/infill",

      -- replace the default keymaps with custom ones
      keymap_accept_full = "<C-j>",
      keymap_accept_line = "<C-l>",
      keymap_accept_word = "<C-w>",
    }
  end
}
