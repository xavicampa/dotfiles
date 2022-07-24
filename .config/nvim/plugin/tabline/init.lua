local tabline = require("tabline")
tabline.setup {
    options = {
        show_bufnr = true,
        show_filename_only = true
    }
}

local augroup = vim.api.nvim_create_augroup("TablineBuffers", {})

function ShowCurrentBuffers()
        local data = vim.t.tabline_data
        if data == nil then
                tabline._new_tab_data(vim.fn.tabpagenr())
                data = vim.t.tabline_data
        end
        data.show_all_buffers = false
        vim.t.tabline_data = data
        vim.cmd([[redrawtabline]])
end

vim.api.nvim_create_autocmd({ "TabEnter" }, {
        group = augroup,
        callback = ShowCurrentBuffers,
})
