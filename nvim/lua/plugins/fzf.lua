local actions = require("fzf-lua.actions")
return {
  "ibhagwan/fzf-lua",
  opts = {
    files = {
      actions = {
        ["ctrl-t"] = function(selected, opts)
          actions.vimcmd_entry("tab drop", selected, opts)
        end,
      },
    },
  },
}
