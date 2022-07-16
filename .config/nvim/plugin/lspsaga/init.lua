local action = require("lspsaga.codeaction")

-- code action
vim.keymap.set("n", "<space>ca", action.code_action, { silent = true,noremap = true })
vim.keymap.set("v", "<space>ca", function()
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-U>", true, false, true))
    action.range_code_action()
end, { silent = true,noremap =true })

local saga = require 'lspsaga'

-- show hover doc
vim.keymap.set("n", "K", require("lspsaga.hover").render_hover_doc, { silent = true })
vim.keymap.set("n", "gs", require("lspsaga.signaturehelp").signature_help, { silent = true,noremap = true})
vim.keymap.set("n", "gr", require("lspsaga.rename").lsp_rename, { silent = true,noremap = true })
vim.keymap.set("n", "gd", require("lspsaga.definition").preview_definition, { silent = true,noremap = true })
vim.keymap.set("n", "gh", require("lspsaga.finder").lsp_finder, { silent = true,noremap = true })

-- use custom config
saga.init_lsp_saga({
    -- put modified options in there
})
