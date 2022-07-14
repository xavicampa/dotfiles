vim.opt.termguicolors = true
local opts = { noremap = true, silent = true }
vim.keymap.set('n', 'gb', ':BufferLinePick<CR>', opts)
require("bufferline").setup {
    options = {
        numbers = "buffer_id",
        show_close_icon = false,
        show_buffer_close_icons = false,
        diagnostics = "nvim_lsp"
    }
}
