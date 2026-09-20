return {
  "ggml-org/llama.vim",
  init = function()

    vim.g.llama_config = {

      show_info = 0,

      -- endpoint_fim = "http://localhost:8090/infill",
      -- model_fim = "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF:Q4_K_M",

      endpoint_inst = "http://localhost:8080/v1/chat/completions",
      model_inst = "bartowski/Qwen3.8-27B-GGUF:MTP"
    }
  end
}
