--- Stale dev-server detection.
---
--- Annotates dev-server entries with `entry.stale = { reasons = {...} }` when
--- they match any enabled heuristic. Only entries detected as dev servers
--- (`is_server`) are considered — databases and the like are never "stale".
local M = {}

--- Whether a path exists and is a directory.
---@param path string|nil
---@return boolean
local function dir_exists(path)
  if not path or path == "" then
    return false
  end
  return vim.fn.isdirectory(path) == 1
end

--- Evaluate staleness across all entries, mutating them in place.
---@param entries ports.Entry[]
---@param cfg table ports.Config.stale
---@return ports.Entry[]
function M.evaluate(entries, cfg)
  if not cfg or not cfg.enabled then
    return entries
  end

  -- Pre-compute, per project directory, how many distinct dev-server pids run
  -- there, for duplicate detection.
  local cwd_pids = {} ---@type table<string, table<integer, boolean>>
  for _, e in ipairs(entries) do
    if e.is_server and e.cwd and e.cwd ~= "" and e.cwd ~= "/" then
      cwd_pids[e.cwd] = cwd_pids[e.cwd] or {}
      cwd_pids[e.cwd][e.pid] = true
    end
  end

  local function count(set)
    local n = 0
    for _ in pairs(set) do
      n = n + 1
    end
    return n
  end

  for _, e in ipairs(entries) do
    if e.is_server then
      local reasons = {}

      if cfg.orphaned and e.cwd and e.cwd ~= "" and not dir_exists(e.cwd) then
        reasons[#reasons + 1] = "working directory no longer exists"
      end

      if cfg.duplicates and e.cwd and cwd_pids[e.cwd] and count(cwd_pids[e.cwd]) > 1 then
        reasons[#reasons + 1] = "duplicate server in the same project"
      end

      if cfg.max_age and cfg.max_age > 0 and e.uptime and e.uptime > cfg.max_age then
        local util = require("ports.util")
        reasons[#reasons + 1] = "running for " .. util.human_duration(e.uptime)
      end

      if #reasons > 0 then
        e.stale = { reasons = reasons }
      end
    end
  end

  return entries
end

return M
