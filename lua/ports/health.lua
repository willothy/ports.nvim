--- `:checkhealth ports` implementation.
local M = {}

function M.check()
  local health = vim.health
  health.start("ports.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10+ is required (vim.system / vim.ui.open)")
  end

  local backend = require("ports.scan").backend()
  if backend == "lsof" then
    health.ok("port scanner backend: lsof (" .. vim.fn.exepath("lsof") .. ")")
  elseif backend == "ss" then
    health.ok("port scanner backend: ss (" .. vim.fn.exepath("ss") .. ")")
    health.info("lsof not found; uptime/cwd enrichment still uses ps/lsof where available")
  else
    health.error("no port scanner found", { "Install `lsof` (macOS/Linux) or `ss` (Linux, iproute2)" })
  end

  if vim.fn.executable("ps") == 1 then
    health.ok("ps found (" .. vim.fn.exepath("ps") .. ") — uptime/command enrichment available")
  else
    health.warn("ps not found — uptime and full command line will be unavailable")
  end

  if vim.fn.executable("kill") == 1 then
    health.ok("kill found — process termination available")
  else
    health.warn("kill not found — the kill action will not work")
  end

  if vim.fn.executable("tail") == 1 then
    health.ok("tail found — log tailing available")
  else
    health.warn("tail not found — the logs action will not work")
  end

  -- vim.ui.open availability for the browser action.
  if type(vim.ui.open) == "function" then
    health.ok("vim.ui.open available — browser action will work out of the box")
  else
    health.warn("vim.ui.open unavailable — set browser.cmd in setup() for the open action")
  end
end

return M
