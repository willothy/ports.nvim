-- Minimal init for the test suite. Puts the plugin and plenary on the
-- runtimepath so `PlenaryBustedDirectory` (and each spec it spawns) can load
-- both. plenary is expected at $PLENARY_PATH or ./.tests/plenary.nvim (the
-- Makefile clones it there).
local root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h:h")

vim.opt.swapfile = false
vim.opt.rtp:prepend(root)

local plenary = os.getenv("PLENARY_PATH") or (root .. "/.tests/plenary.nvim")
if vim.fn.isdirectory(plenary) == 1 then
  vim.opt.rtp:prepend(plenary)
end

vim.cmd("runtime plugin/plenary.vim")
