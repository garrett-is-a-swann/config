local highlight = {
    "RainbowRed",
    "RainbowYellow",
    "RainbowBlue",
    "RainbowOrange",
    "RainbowGreen",
    "RainbowViolet",
    "RainbowCyan",
}

local hooks = require("ibl.hooks")
-- create the highlight groups in the highlight setup hook, so they are reset
-- every time the colorscheme changes
hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
    vim.api.nvim_set_hl(0, "RainbowRed", { fg = "#E06C75" })
    vim.api.nvim_set_hl(0, "RainbowYellow", { fg = "#E5C07B" })
    vim.api.nvim_set_hl(0, "RainbowBlue", { fg = "#61AFEF" })
    vim.api.nvim_set_hl(0, "RainbowOrange", { fg = "#D19A66" })
    vim.api.nvim_set_hl(0, "RainbowGreen", { fg = "#98C379" })
    vim.api.nvim_set_hl(0, "RainbowViolet", { fg = "#C678DD" })
    vim.api.nvim_set_hl(0, "RainbowCyan", { fg = "#56B6C2" })
end)

IBL_ENABLED = true
IBL_OPTS = { indent = { highlight = highlight } }

return {
    "lukas-reineke/indent-blankline.nvim",
    opts = IBL_OPTS,
    keys = {
        {
            "<leader>u<tab>",
            mode = { "n" },
            function()
                if IBL_ENABLED then
                    require("ibl").setup({ enabled = false })
                else
                    require("ibl").setup(IBL_OPTS)
                end
                IBL_ENABLED = not IBL_ENABLED
            end,
            desc = "Toggle Indent Blankline (ibl) verticle bars",
        },
    },
}
