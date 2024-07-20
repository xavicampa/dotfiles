require("gen").setup {
    opts = {
        model = "qwen2"
    },
    vim.keymap.set({ 'n', 'v' }, '<leader>oo', ':Gen<CR>')
}
