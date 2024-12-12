-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = vim.keymap.set

--map("n", "<S-J>", "gt", { desc = "nav tab left", noremap = true })
--map("n", "<S-K>", "gT", { desc = "nav tab right", remap = true })

map(
    "v",
    "<s-y>",
    'y :redir! > ~/.vimbuffer <bar> echon @" <bar> redir END <CR> <CR>',
    { desc = "Yoink into ~/.vimbuffer" }
)
map("v", "<s-p>", ":'<,'>!cat ~/.vimbuffer<CR>", { desc = "Ploink from ~/.vimbuffer" })
map("n", "<s-p>", ":r ~/.vimbuffer<CR>", { desc = "Ploink from ~/.vimbuffer" })

map("n", "<space><tab>]", function()
    local offset = #vim.api.nvim_list_tabpages() - (vim.v.count > 0 and vim.v.count or 1)
    vim.cmd("tabN" .. offset) -- Go backwards to go forward (backwards wraps)
end, { desc = "Navigate tab(s) right" })

map("n", "<space><tab>[", function()
    vim.cmd("tabp " .. tostring(vim.v.count > 0 and vim.v.count or 1))
end, { desc = "Navigate tab(s) left" })

map("n", "<space><tab>}", function()
    local count_str = "+" .. (vim.v.count > 0 and vim.v.count or 1)
    vim.cmd("tabm " .. count_str)
end, { desc = "Move tab(s) right" })

map("n", "<space><tab>{", function()
    local count_str = "-" .. (vim.v.count > 0 and vim.v.count or 1)
    vim.cmd("tabm " .. count_str)
end, { desc = "Move tab(s) left" })
