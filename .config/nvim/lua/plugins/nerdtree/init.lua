return {
    "preservim/nerdtree",
    dependencies = {
        "Deftera186/vim-devicons",
        "xuyuanp/nerdtree-git-plugin",
    },
    opts = {},
    config = function()
        vim.api.nvim_set_keymap("n", "<C-t>", ":NERDTreeToggle<CR>", { noremap = true })
        vim.g.NERDTreeQuitOnOpen = 1
        vim.g.NERDTreeGitStatusUseNerdFonts = 1
        vim.g.NERDTreeFileExtensionHighlightFullName = 1
        vim.g.NERDTreeExactMatchHighlightFullName = 1
        vim.g.NERDTreePatternMatchHighlightFullName = 1
    end
}
