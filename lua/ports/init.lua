--- ports.nvim — local dev server & port manager.
---
--- Public entry point. Wires scanning → detection → stale evaluation,
--- exposes a small Lua API, and opens the UI.
local config = require("ports.config")

local M = {}

--- Configure ports.nvim. Optional — defaults work without calling this.
---@param opts table|nil ports.Config
---@return ports.Config
function M.setup(opts)
  return config.setup(opts)
end

--- Scan, enrich, and return listening-port entries. Runs on the main loop.
---@param cb fun(err: string|nil, entries: ports.Entry[])
function M.list(cb)
  require("ports.scan").scan(function(err, entries)
    if err then
      cb(err, {})
      return
    end

    entries = M.filter(entries)
    require("ports.detect").detect_all(entries)
    require("ports.stale").evaluate(entries, config.options.stale)

    cb(nil, entries)
  end)
end

--- Apply the configured address-family scan filters.
---@param entries ports.Entry[]
---@return ports.Entry[]
function M.filter(entries)
  local s = config.options.scan
  local out = {}
  for _, e in ipairs(entries) do
    local addr = e.address
    local keep
    if addr == "127.0.0.1" or addr == "::1" then
      keep = s.include_loopback
    elseif addr == "*" or addr == "0.0.0.0" or addr == "::" then
      keep = s.include_any
    else
      keep = s.include_external
    end
    if keep then
      out[#out + 1] = e
    end
  end
  return out
end

--- Open the interactive ports window.
function M.open()
  require("ports.ui").open()
end

--- Toggle the interactive ports window.
function M.toggle()
  require("ports.ui").toggle()
end

--- Find the single live entry for a port, or nil.
---@param port integer
---@param cb fun(entry: ports.Entry|nil)
function M.entry_for(port, cb)
  M.list(function(_, entries)
    for _, e in ipairs(entries) do
      if e.port == port then
        cb(e)
        return
      end
    end
    cb(nil)
  end)
end

--- Kill whatever is listening on `port`.
---@param port integer
---@param signal string|nil
function M.kill(port, signal)
  M.entry_for(port, function(entry)
    if not entry then
      vim.notify(("ports: nothing listening on port %d"):format(port), vim.log.levels.WARN)
      return
    end
    require("ports.process").kill(entry.pid, signal or config.options.kill.signal, function(ok, err)
      if ok then
        vim.notify(("ports: killed %s (pid %d) on port %d"):format(entry.type or "process", entry.pid, port))
      else
        vim.notify(("ports: failed to kill pid %d: %s"):format(entry.pid, err or "?"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Open the browser for `port`.
---@param port integer
function M.open_browser(port)
  M.entry_for(port, function(entry)
    if entry then
      require("ports.browser").open_entry(entry)
    else
      vim.notify(("ports: nothing listening on port %d"):format(port), vim.log.levels.WARN)
    end
  end)
end

--- Tail logs for `port`.
---@param port integer
function M.logs(port)
  M.entry_for(port, function(entry)
    if entry then
      require("ports.logs").tail(entry)
    else
      vim.notify(("ports: nothing listening on port %d"):format(port), vim.log.levels.WARN)
    end
  end)
end

return M
