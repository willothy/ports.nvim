--- Process control: terminate the process behind a port.
local M = {}

--- Send a signal to a pid. Callback runs on the main loop.
---@param pid integer
---@param signal string  signal name without the leading dash, e.g. "TERM", "KILL"
---@param cb fun(ok: boolean, err: string|nil)
function M.kill(pid, signal, cb)
  signal = signal or "TERM"
  local done = vim.schedule_wrap(cb)
  local ok, err = pcall(vim.system, { "kill", "-" .. signal, tostring(pid) }, { text = true }, function(res)
    if res.code == 0 then
      done(true, nil)
    else
      local msg = res.stderr ~= "" and res.stderr or ("kill exited with code " .. res.code)
      done(false, vim.trim(msg))
    end
  end)
  if not ok then
    done(false, tostring(err))
  end
end

--- Check whether a pid is still alive (signal 0).
---@param pid integer
---@param cb fun(alive: boolean)
function M.is_alive(pid, cb)
  local done = vim.schedule_wrap(cb)
  local ok = pcall(vim.system, { "kill", "-0", tostring(pid) }, { text = true }, function(res)
    done(res.code == 0)
  end)
  if not ok then
    done(false)
  end
end

return M
