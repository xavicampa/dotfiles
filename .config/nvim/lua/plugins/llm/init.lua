return {
        'huggingface/llm.nvim',
        opts = {
            backend = "ollama",
            accept_keymap = "<S-Tab>",
            model = "codellama:7b-code",
            fim = {
                enabled = true,
                prefix = "<PRE> ",
                middle = " <MID>",
                suffix = " <SUF>",
            },
            context_window = 4096,
            url = "http://localhost:11434",
            tokens_to_clear = { "<EOT>" },
            -- model = "deepseek-coder-v2:16b-lite-base-q4_0",
            -- fim = {
            --     enabled = true,
            --     prefix = "<｜fim▁begin｜>",
            --     middle = "<｜fim▁end｜>",
            --     suffix = "<｜fim▁hole｜>",
            -- },
            -- context_window = 4096,
            -- url = "http://localhost:11434",
        }
}
