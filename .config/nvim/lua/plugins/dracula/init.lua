return {
        "Mofiqul/dracula.nvim",
        opts = {
            italic_comment = true
        },
        init = function ()
            vim.cmd([[colorscheme dracula]])
        end
}
