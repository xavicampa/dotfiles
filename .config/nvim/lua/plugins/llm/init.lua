return {
    'huggingface/llm.nvim',
    opts = {
        accept_keymap = "<S-Tab>",

        backend = "ollama",
        url = "http://localhost:11434",

        -- backend = "openai",
        -- url = "http://172.16.99.120:1234",
        context_window = 32000,
        -- url = "http://localhost:1234",
        -- context_window = 8000,
        api_token = nil,

        -- model = "codellama:7b-code",
        -- fim = {
        --     enabled = true,
        --     prefix = "<PRE> ",
        --     middle = " <MID>",
        --     suffix = " <SUF>",
        -- },
        -- tokens_to_clear = { "<EOT>" },

        -- model = "qwen2.5-coder:1.5b-base",
        model = "qwen2.5-coder:3b-base",
        fim = {
            enabled = true,
            prefix = "<|fim_prefix|>",
            middle = "<|fim_middle|>",
            suffix = "<|fim_suffix|>",
        },

        -- model = "deepseek-coder-v2:16b-lite-base-q4_0",
        -- fim = {
        --     enabled = true,
        --     prefix = "<｜fim▁begin｜>",
        --     middle = "<｜fim▁end｜>",
        --     suffix = "<｜fim▁hole｜>",
        -- },

        -- tokenizer = {
        --     repository = "Qwen/Qwen2.5-Coder-1.5B"
        -- },
    }
}
