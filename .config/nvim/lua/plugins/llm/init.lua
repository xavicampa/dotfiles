return {
  "ggml-org/llama.vim",
  init = function()

    vim.g.llama_config = {
      show_info = 0,

      endpoint_fim = "http://localhost:8080/upstream/Qwen3.6-35B-A3B-GGUF/infill",
      -- endpoint_fim = "http://localhost:8080/upstream/Qwen2.5-Coder-14B-GGUF/infill",
      endpoint_inst = "http://localhost:8080/upstream/Qwen3.6-35B-A3B-GGUF/v1/chat/completions",
    }
  end
}
