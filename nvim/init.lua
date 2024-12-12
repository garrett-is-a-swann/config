-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

vim.api.nvim_create_user_command("Ff", function()
    local handle = io.popen("git rev-parse --show-toplevel")
    if handle == nil then
        return
    end
    local path = handle:read("*a"):sub(1, -2)
    print(path)

    require("fzf-lua").files({ cwd = path })
end, {})

vim.cmd.colorscheme("catppuccin")
-- vim.cmd("colorscheme desertrose")
