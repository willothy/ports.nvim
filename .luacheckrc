std = "luajit"

-- `vim` is writable (vim.g.x, vim.opt_local.x, vim.bo.x, …) so declare it as a
-- global rather than read-only to avoid spurious "read-only field" reports.
globals = { "vim" }

-- stylua owns line length and formatting; don't double-report it here.
max_line_length = false

-- Allow unused function arguments (common in callbacks with fixed signatures).
unused_args = false
