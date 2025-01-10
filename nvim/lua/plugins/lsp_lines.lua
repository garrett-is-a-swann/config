return {
    "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
    opts = function()
        vim.diagnostic.config({
            virtual_text = false,
        })
        vim.diagnostic.config({
            virtual_lines = {
                only_current_line = true,
                highlight_whole_line = false,
            },
        })
    end,
}
