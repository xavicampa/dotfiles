return {
  "ggml-org/llama.vim",
  init = function()

    vim.g.llama_config = {

      show_info = 0,

      endpoint_fim = "http://localhost:8080/infill",
      model_fim = "unsloth/Qwen3.6-27B-MTP-GGUF:Q6_K_XL",

      endpoint_inst = "http://localhost:8080/v1/chat/completions",
      model_inst = "unsloth/Qwen3.6-27B-MTP-GGUF:Q6_K_XL"
    }
  end
}
