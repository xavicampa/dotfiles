return {
  "ggml-org/llama.vim",
  init = function()

    vim.g.llama_config = {

      show_info = 0,

      endpoint_fim = "http://localhost:8080/infill",
      model_fim = "Qwen3.6-27B-GGUF",

      endpoint_inst = "http://localhost:8080/v1/chat/completions",
      model_inst = "Qwen3.6-27B-GGUF"
    }
  end
}
