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
    },
}
