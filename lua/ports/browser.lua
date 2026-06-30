--- Open the URL behind a port in a browser.
local config = require("ports.config")

local M = {}

--- Build the URL for an entry from its bind address and port.
---@param entry ports.Entry
---@return string
function M.url_for(entry)
  local b = config.options.browser
  local host = b.host or "localhost"
  -- If the listener is bound to a specific external address, prefer it over
  -- localhost so the URL actually reaches the service.
  if entry.address and entry.address ~= "*" and entry.address ~= "0.0.0.0" and entry.address ~= "::" then
    if entry.address == "127.0.0.1" or entry.address == "::1" then
      host = b.host or "localhost"
    else
      host = entry.address
    end
  end
  return string.format("%s://%s:%d", b.scheme or "http", host, entry.port)
end

--- Open a URL using the configured strategy (function > command > vim.ui.open).
---@param url string
---@param cb fun(ok: boolean, err: string|nil)|nil
function M.open(url, cb)
  cb = cb or function() end
  local custom = config.options.browser.cmd
  if type(custom) == "function" then
    local ok, err = pcall(custom, url)
    cb(ok, ok and nil or tostring(err))
    return
  end
  if type(custom) == "string" then
    local ok, err = pcall(vim.system, { custom, url }, { text = true }, function(res)
      vim.schedule(function()
        cb(res.code == 0, res.code == 0 and nil or vim.trim(res.stderr or ""))
      end)
    end)
    if not ok then
      cb(false, tostring(err))
    end
    return
  end
  -- vim.ui.open returns (cmd, err) in recent Neovim; treat a non-nil err as
  -- failure. It launches the OS opener asynchronously.
  local ok, ret, err = pcall(vim.ui.open, url)
  if not ok then
    cb(false, tostring(ret))
  elseif err then
    cb(false, tostring(err))
  else
    cb(true, nil)
  end
end

--- Open the browser for an entry.
---@param entry ports.Entry
---@param cb fun(ok: boolean, err: string|nil)|nil
function M.open_entry(entry, cb)
  M.open(M.url_for(entry), cb)
end

return M
