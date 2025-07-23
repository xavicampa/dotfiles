return {
    'huggingface/llm.nvim',
    opts = {
        backend = "ollama",
        accept_keymap = "<S-Tab>",
        url = "http://localhost:11434",

        -- model = "codellama:7b-code",
        -- fim = {
        --     enabled = true,
        --     prefix = "<PRE> ",
        --     middle = " <MID>",
        --     suffix = " <SUF>",
        -- },
        -- context_window = 4096,
        -- tokens_to_clear = { "<EOT>" },

        model = "qwen2.5-coder:1.5b-base",
        fim = {
            enabled = true,
            prefix = "<|fim_prefix|>",
            middle = "<|fim_middle|>",
            suffix = "<|fim_suffix|>",
        },
        context_window = 32768,
        -- tokenizer = {
        --     repository = "Qwen/Qwen2.5-Coder-1.5B"
        -- },

        -- model = "deepseek-coder-v2:16b-lite-base-q4_0",
        -- fim = {
        --     enabled = true,
        --     prefix = "<｜fim▁begin｜>",
        --     middle = "<｜fim▁end｜>",
        --     suffix = "<｜fim▁hole｜>",
        -- },
        -- context_window = 4096,
    }
}
