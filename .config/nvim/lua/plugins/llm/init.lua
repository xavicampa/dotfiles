return {
  "ggml-org/llama.vim",
  init = function()

    vim.g.llama_config = {
      show_info = 0,

      -- endpoint_fim = "http://localhost:8080/upstream/Qwen3.6-35B-A3B-GGUF/infill",
      endpoint_fim = "http://localhost:8012/infill",

      endpoint_inst = "http://localhost:8080/v1/chat/completions",
      -- model_inst = "Qwen3.6-35B-A3B-GGUF"
      model_inst = "Qwen3.6-27B-GGUF"
    }
  end
}
