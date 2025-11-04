return {
        "David-Kunz/gen.nvim",
        opts = {
            model = "qwen3:8b",
        },
        init = function()
            require("gen").prompts["Generate"] = {
                prompt = "These are your instructions:\n\n$input\n\n" ..
                    "Do not include examples.\n\n" ..
                    "Do not include usage examples.\n\n" ..
                    "Only output the result in format ```$filetype\n...\n```:\n```$filetype\n...\n```",
                replace = "false",
                extract = "```$filetype\n(.-)```"
            }
        end,
}
