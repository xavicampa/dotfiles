return {
    "rcarriga/nvim-dap-ui",
    init = function()
        local dap = require("dap")
        local dapui = require("dapui")
        dap.listeners.before.attach.dapui_config = function()
            dapui.open()
        end
        dap.listeners.before.launch.dapui_config = function()
            dapui.open()
        end
        dap.listeners.before.event_terminated.dapui_config = function()
            dapui.close()
        end
        dap.listeners.before.event_exited.dapui_config = function()
            dapui.close()
        end
    end,
    opts = {
    },
    dependencies = {
        {
            "mason-org/mason.nvim",
            version = "^1.0.0",
        },
        "nvim-neotest/nvim-nio"
    }
}
