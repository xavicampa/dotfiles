return {
  "ggml-org/llama.vim",
  init = function()

    vim.g.llama_config = {

      show_info = 0,

      endpoint_fim = "http://localhost:8080/infill",
      model_fim = "unsloth/Qwen3.8-27B-GGUF:DFLASH2",

      endpoint_inst = "http://localhost:8080/v1/chat/completions",
      model_inst = "unsloth/Qwen3.8-27B-GGUF:DFLASH2"
    }
  end
}
