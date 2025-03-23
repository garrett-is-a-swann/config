return {
    "akinsho/bufferline.nvim",
    opts = {
        options = {
            mode = "tabs",
            show_close_icon = false,
            name_formatter = function(buf)
                local current = vim.api.nvim_get_current_tabpage()
                local offset = current - vim.api.nvim_tabpage_get_number(buf.tabnr)
                buf.name = "(" .. tostring(offset) .. ")" .. buf.name
            end,
        },
        highlights = {
            buffer_selected = {
                fg = {
                    attribute = "fg",
                    highlight = "Type",
                },
            },
            indicator_selected = {
                fg = {
                    attribute = "fg",
                    highlight = "Statement",
                },
            },
            background = {
                fg = {
                    attribute = "fg",
                    highlight = "Question",
                },
            },
        },
    },
}
