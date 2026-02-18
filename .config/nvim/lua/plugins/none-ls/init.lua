return {
        "nvimtools/none-ls.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function ()
            require("null-ls").setup({
              sources = {
                require("null-ls").builtins.code_actions.gitsigns,
                require("null-ls").builtins.formatting.black,
                require("null-ls").builtins.formatting.prettier,
                require("null-ls").builtins.diagnostics.cfn_lint.with({
                    extra_args = {
                        -- '-i', 'W3002', -- Do not try to parse nested stack's TemplateURL
                        -- '-i', 'E3043', -- Do not try to parse nested stack's TemplateURL
                        '-c', 'I', --  Include suggestions and best practices
                    }
                }),
                require("null-ls").builtins.diagnostics.checkstyle.with({
                    args = function(params)
                        return {
                            "-f",
                            "sarif",
                            "-c",
                            vim.fn.expand("~/dev/nas/nas_checkstyle.xml"),
                            params.bufname,
                        }
                    end
                })
            }
            })
        end
}
