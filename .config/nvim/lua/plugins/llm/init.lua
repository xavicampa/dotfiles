return {
  "ggml-org/llama.vim",
  init = function()

    vim.g.llama_config = {

      show_info = 0,

      endpoint_fim = "http://localhost:8080/infill",
      model_fim = "Jackrong/Qwopus3.6-27B-v2-MTP-GGUF:Q8_0",

      endpoint_inst = "http://localhost:8080/v1/chat/completions",
      model_inst = "Jackrong/Qwopus3.6-27B-v2-MTP-GGUF:Q8_0"
    }
  end
}
