--- Tail logs associated with a port's process.
---
--- Log files are discovered automatically from the process's open file
--- descriptors via `lsof` (regular files whose names look like logs). When
--- several exist the user picks one; the chosen file is followed with
--- `tail -f` inside a terminal split.
local util = require("ports.util")

local M = {}

--- Heuristic: does this open file look like a log we'd want to tail?
---@param path string
---@return boolean
local function looks_like_log(path)
  local lower = string.lower(path)
  if string.sub(lower, -4) == ".log" then
    return true
  end
  if util.contains(lower, "/logs/") or util.contains(lower, "/log/") then
    return true
  end
  if string.sub(lower, -4) == ".out" or string.sub(lower, -4) == ".err" then
    return true
  end
  return false
end

--- Discover candidate log files from a process's open file descriptors.
---@param pid integer
---@param cb fun(paths: string[])
function M.discover(pid, cb)
  local done = vim.schedule_wrap(cb)
  if vim.fn.executable("lsof") ~= 1 then
    done({})
    return
  end
  -- `-Ftn` emits type (t) and name (n) records per open file. We keep regular
  -- files (t == "REG") whose names look like logs.
  local ok = pcall(vim.system, { "lsof", "-p", tostring(pid), "-Ftn" }, { text = true }, function(res)
    local paths = {}
    local seen = {}
    local is_reg = false
    for _, line in ipairs(util.split(res.stdout or "", "\n")) do
      local f = string.sub(line, 1, 1)
      local v = string.sub(line, 2)
      if f == "t" then
        is_reg = (v == "REG")
      elseif f == "n" and is_reg then
        if string.sub(v, 1, 1) == "/" and looks_like_log(v) and not seen[v] then
          seen[v] = true
          paths[#paths + 1] = v
        end
      end
    end
    done(paths)
  end)
  if not ok then
    done({})
  end
end

--- Follow a file with `tail -f` in a horizontal terminal split.
---@param path string
function M.tail_file(path)
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify("ports: log file not readable: " .. path, vim.log.levels.ERROR)
    return
  end
  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("buflisted", false, { buf = buf })
  -- jobstart with term mode renders the live output; `tail -f` streams it.
  vim.fn.jobstart({ "tail", "-n", "200", "-f", path }, { term = true })
  vim.api.nvim_buf_set_name(buf, "ports://logs/" .. vim.fs.basename(path))
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end, { buffer = buf, nowait = true, desc = "Close log tail" })
  vim.cmd("normal! G")
end

--- Discover and tail logs for an entry, prompting if several files exist.
---@param entry ports.Entry
function M.tail(entry)
  M.discover(entry.pid, function(paths)
    if #paths == 0 then
      vim.notify(
        ("ports: no open log file found for %s (pid %d)"):format(entry.type or entry.command or "process", entry.pid),
        vim.log.levels.WARN
      )
      return
    end
    if #paths == 1 then
      M.tail_file(paths[1])
      return
    end
    vim.ui.select(paths, { prompt = "Tail which log?" }, function(choice)
      if choice then
        M.tail_file(choice)
      end
    end)
  end)
end

return M
