local o = vim.o

-- Mouse is annoying and bad. Disable.
o.mouse = ""

-- Automatically change directory
o.autochdir = true

-- Spaces
o.shiftwidth = 4
o.tabstop = 4
o.softtabstop = 4
o.expandtab = true

-- Indentation
o.autoindent = true
o.smartindent = true
o.wrap = true

o.errorbells = false
o.visualbell = false

local g = vim.g

g.lazyvim_python_lsp = "pyright"
vim.g.snacks_animate = false
