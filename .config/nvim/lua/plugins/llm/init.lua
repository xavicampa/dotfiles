return {
  "ggml-org/llama.vim",
  init = function()

    vim.g.llama_config = {

      show_info = 0,

      endpoint_fim = "http://localhost:8080/infill",
      model_fim = "bartowski/Qwen_Qwen3.6-27B-GGUF:Q8_0",

      endpoint_inst = "http://localhost:8080/v1/chat/completions",
      model_inst = "bartowski/Qwen_Qwen3.6-27B-GGUF:Q8_0"
    }
  end
}
