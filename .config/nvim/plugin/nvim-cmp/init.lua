local lspkind = require "lspkind"
lspkind.init()


local cmp = require "cmp"
cmp.setup {
    snippet = {
        expand = function(args)
           -- require('luasnip').lsp_expand(args.body)
           vim.fn["UltiSnips#Anon"](args.body)
        end,
    },
    mapping = {
        ["<C-n>"] = function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            else
              fallback()
            end
        end,
        ["<C-p>"] = function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            else
              fallback()
            end
        end,
        ["<C-d>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<C-e>"] = cmp.mapping.close(),
        ["<C-y>"] = cmp.mapping.confirm {
            behavior = cmp.ConfirmBehavior.Insert,
            select = true
        },
        ["<c-space>"] = cmp.mapping.complete(),
    },
    sources = {
        { name = "ultisnips" },
        { name = "nvim_lsp_signature_help" },
        { name = "nvim_lua" },
        { name = "nvim_lsp" },
        { name = "path" },
        {
            name = "buffer",
            option = {
                get_bufnrs = function() return vim.api.nvim_list_bufs() end
            }
        }
    },
    formatting = {
        format = lspkind.cmp_format {
            with_text = true,
            menu = {
                nvim_lua = "[api]",
                nvim_lsp = "[LSP]",
                path = "[path]",
                buffer = "[buf]"
            }
        }
    },
    experimental = {
        ghost_text = true
    }
}
