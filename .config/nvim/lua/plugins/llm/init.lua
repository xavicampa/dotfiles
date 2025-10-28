return {
    'huggingface/llm.nvim',
    opts = {
        -- backend = "ollama",
        backend = "openai",

        accept_keymap = "<S-Tab>",

        -- url = "http://localhost:11434",
        url = "http://172.16.99.120:1234/v1",

        -- model = "codellama:7b-code",
        -- fim = {
        --     enabled = true,
        --     prefix = "<PRE> ",
        --     middle = " <MID>",
        --     suffix = " <SUF>",
        -- },
        -- context_window = 4096,
        -- tokens_to_clear = { "<EOT>" },

        -- model = "qwen2.5-coder:1.5b-base",
        model = "qwen/qwen2.5-coder:7b",
        fim = {
            enabled = true,
            prefix = "<|fim_prefix|>",
            middle = "<|fim_middle|>",
            suffix = "<|fim_suffix|>",
        },
        context_window = 32000,

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
