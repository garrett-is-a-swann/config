return {
    "folke/flash.nvim",
    opts = {
        highlight = {
            backdrop = true,
        },
        modes = {
            search = {
                highlight = false,
            },
            char = {
                highlight = {
                    backdrop = false,
                },
            },
            treesitter = {
                highlight = {
                    backdrop = false,
                },
            },
        },
    },
    keys = {
        {
            "<c-f>",
            mode = { "n", "x" },
            function()
                require("flash").jump()
            end,
            desc = "Flash",
            remap = true,
        },
        {
            "<c-s>",
            mode = { "n", "x" },
            function()
                require("flash").treesitter()
            end,
            desc = "Flash treesitter",
        },
    },
}
