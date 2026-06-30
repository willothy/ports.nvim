--- Discover processes listening on local TCP ports.
---
--- Primary backend is `lsof` (works on macOS and Linux). On Linux without
--- `lsof`, `ss` is used as a fallback. Process metadata (full command line,
--- uptime) comes from `ps`, and the working directory from `lsof`.
---
--- All commands run asynchronously via `vim.system`; the public `scan`
--- function takes a callback invoked on the main loop.
local util = require("ports.util")

local M = {}

---@class ports.Entry
---@field port integer
---@field proto string         "tcp"
---@field address string       bind address, e.g. "127.0.0.1", "*", "::1"
---@field pid integer
---@field command string       short command name (from lsof/ss)
---@field args string|nil      full command line (from ps)
---@field user string|nil
---@field ppid integer|nil
---@field cwd string|nil       process working directory
---@field uptime integer|nil   seconds since start
---@field type string|nil      detected service/framework (filled by detect)
---@field icon string|nil      glyph for the detected type (filled by detect)
---@field is_server boolean|nil whether `type` is a dev server (filled by detect)
---@field stale table|nil      { reasons = string[] } (filled by stale)

--- Run a command, returning (ok, stdout_lines, stderr) via callback.
---@param cmd string[]
---@param cb fun(ok: boolean, lines: string[], stderr: string)
local function run(cmd, cb)
  local ok, err = pcall(vim.system, cmd, { text = true }, function(res)
    -- lsof exits non-zero when it merely emits warnings, so success is judged
    -- by whether we got parseable stdout, not purely by exit code.
    local out = res.stdout or ""
    local lines = util.split(out, "\n")
    cb(res.code == 0 or out ~= "", lines, res.stderr or "")
  end)
  if not ok then
    cb(false, {}, tostring(err))
  end
end

--- Parse `lsof -nP -iTCP -sTCP:LISTEN -FpcnLR` field output.
--- Each line is `<field-id><value>`. Process-level fields (p/c/L/R) are
--- followed by repeated file blocks (f then n) for each listening socket.
---@param lines string[]
---@return table<integer, ports.Entry[]> pid -> entries
local function parse_lsof_listen(lines)
  local by_pid = {}
  local cur ---@type {pid: integer, command: string?, user: string?, ppid: integer?}|nil
  for _, line in ipairs(lines) do
    if #line >= 1 then
      local f = string.sub(line, 1, 1)
      local v = string.sub(line, 2)
      if f == "p" then
        cur = { pid = tonumber(v) }
        if cur.pid then
          by_pid[cur.pid] = by_pid[cur.pid] or {}
        end
      elseif cur then
        if f == "c" then
          cur.command = v
        elseif f == "L" then
          cur.user = v
        elseif f == "R" then
          cur.ppid = tonumber(v)
        elseif f == "n" then
          -- A listening socket name: "*:3000", "127.0.0.1:3000", "[::1]:3000".
          local addr, port = M.parse_socket_name(v)
          if port and cur.pid then
            table.insert(by_pid[cur.pid], {
              port = port,
              proto = "tcp",
              address = addr,
              pid = cur.pid,
              command = cur.command,
              user = cur.user,
              ppid = cur.ppid,
            })
          end
        end
      end
    end
  end
  return by_pid
end

--- Split an lsof socket name into (address, port). Hand-written: the port is
--- the digits after the final colon; the address is what precedes it, with any
--- surrounding IPv6 brackets stripped.
---@param name string
---@return string|nil address
---@return integer|nil port
function M.parse_socket_name(name)
  local colon = util.rfind(name, ":")
  if not colon then
    return nil, nil
  end
  local addr = string.sub(name, 1, colon - 1)
  local port = tonumber(string.sub(name, colon + 1))
  if not port then
    return nil, nil
  end
  if string.sub(addr, 1, 1) == "[" and string.sub(addr, -1) == "]" then
    addr = string.sub(addr, 2, #addr - 1)
  end
  if addr == "" then
    addr = "*"
  end
  return addr, port
end

--- Parse a line of `ss -tlnpH` output (Linux fallback).
--- Columns: State Recv-Q Send-Q Local-Address:Port Peer-Address:Port [Process].
--- The Process column looks like: users:(("node",pid=1234,fd=23)).
---@param line string
---@return ports.Entry|nil
function M.parse_ss_line(line)
  line = util.trim(line)
  if line == "" then
    return nil
  end
  -- Tokenise the leading fixed columns by whitespace.
  local _, i = util.read_token(line, 1) -- State
  local _, j = util.read_token(line, i) -- Recv-Q
  local _, k = util.read_token(line, j) -- Send-Q
  local local_addr, l = util.read_token(line, k) -- Local Address:Port
  local _, m = util.read_token(line, l) -- Peer Address:Port
  local proc = util.trim(string.sub(line, m))

  local addr, port = M.parse_socket_name(local_addr)
  if not port then
    return nil
  end

  local entry = { port = port, proto = "tcp", address = addr }

  -- Extract command name and pid from users:(("name",pid=NNN,...)).
  local name_start = string.find(proc, '"', 1, true)
  if name_start then
    local name_end = string.find(proc, '"', name_start + 1, true)
    if name_end then
      entry.command = string.sub(proc, name_start + 1, name_end - 1)
    end
  end
  local pid_marker = string.find(proc, "pid=", 1, true)
  if pid_marker then
    local digits = {}
    local p = pid_marker + 4
    while p <= #proc do
      local c = string.sub(proc, p, p)
      if c >= "0" and c <= "9" then
        digits[#digits + 1] = c
        p = p + 1
      else
        break
      end
    end
    entry.pid = tonumber(table.concat(digits))
  end
  return entry
end

--- Annotate entries with full command line + uptime from `ps`, keyed by pid.
---@param pids integer[]
---@param cb fun(meta: table<integer, {args: string, uptime: integer}>)
local function fetch_ps_meta(pids, cb)
  if #pids == 0 then
    cb({})
    return
  end
  local cmd = { "ps", "-o", "pid=,etime=,args=", "-p", table.concat(pids, ",") }
  run(cmd, function(_, lines)
    local meta = {}
    for _, line in ipairs(lines) do
      if util.trim(line) ~= "" then
        local pid, etime, args = util.parse_ps_line(line)
        if pid then
          meta[pid] = { args = args or "", uptime = util.etime_to_secs(etime or "") }
        end
      end
    end
    cb(meta)
  end)
end

--- Look up the working directory of each pid via `lsof -d cwd`.
---@param pids integer[]
---@param cb fun(cwds: table<integer, string>)
local function fetch_cwds(pids, cb)
  if #pids == 0 then
    cb({})
    return
  end
  local cmd = { "lsof", "-a", "-p", table.concat(pids, ","), "-d", "cwd", "-Fpn" }
  run(cmd, function(_, lines)
    local cwds = {}
    local cur
    for _, line in ipairs(lines) do
      local f = string.sub(line, 1, 1)
      local v = string.sub(line, 2)
      if f == "p" then
        cur = tonumber(v)
      elseif f == "n" and cur then
        cwds[cur] = v
      end
    end
    cb(cwds)
  end)
end

--- Which backend is available on this system.
---@return "lsof"|"ss"|nil
function M.backend()
  if vim.fn.executable("lsof") == 1 then
    return "lsof"
  end
  if vim.fn.executable("ss") == 1 then
    return "ss"
  end
  return nil
end

--- Scan for listening TCP ports via lsof.
---@param cb fun(err: string|nil, entries: ports.Entry[])
local function scan_lsof(cb)
  run({ "lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-FpcnLR" }, function(ok, lines, stderr)
    if not ok then
      cb("lsof failed: " .. stderr, {})
      return
    end
    local by_pid = parse_lsof_listen(lines)

    -- Dedupe sockets: a process commonly listens on the same port over both
    -- IPv4 and IPv6. Collapse to one entry per (pid, port), preferring a
    -- concrete loopback/any address for display.
    local entries = {}
    local pids = {}
    for pid, list in pairs(by_pid) do
      local seen = {}
      for _, e in ipairs(list) do
        local prev = seen[e.port]
        if not prev then
          seen[e.port] = e
          entries[#entries + 1] = e
          pids[#pids + 1] = pid
        elseif prev.address == "::1" and e.address == "127.0.0.1" then
          -- Prefer the IPv4 loopback label when both are present.
          prev.address = e.address
        end
      end
    end

    fetch_ps_meta(pids, function(meta)
      fetch_cwds(pids, function(cwds)
        for _, e in ipairs(entries) do
          local m = meta[e.pid]
          if m then
            e.args = m.args
            e.uptime = m.uptime
          end
          e.cwd = cwds[e.pid]
        end
        cb(nil, entries)
      end)
    end)
  end)
end

--- Scan via `ss` (Linux fallback), enriched with the same ps/cwd lookups.
---@param cb fun(err: string|nil, entries: ports.Entry[])
local function scan_ss(cb)
  run({ "ss", "-tlnpH" }, function(ok, lines, stderr)
    if not ok then
      cb("ss failed: " .. stderr, {})
      return
    end
    local entries = {}
    local pids = {}
    local seen = {}
    for _, line in ipairs(lines) do
      local e = M.parse_ss_line(line)
      if e and e.pid then
        local key = e.pid .. ":" .. e.port
        if not seen[key] then
          seen[key] = true
          entries[#entries + 1] = e
          pids[#pids + 1] = e.pid
        end
      end
    end
    fetch_ps_meta(pids, function(meta)
      fetch_cwds(pids, function(cwds)
        for _, e in ipairs(entries) do
          local m = meta[e.pid]
          if m then
            e.args = m.args
            e.uptime = m.uptime
          end
          e.cwd = cwds[e.pid]
        end
        cb(nil, entries)
      end)
    end)
  end)
end

--- Scan listening ports, enrich and sort. Callback runs on the main loop.
---@param cb fun(err: string|nil, entries: ports.Entry[])
function M.scan(cb)
  local wrapped = vim.schedule_wrap(function(err, entries)
    if not err then
      table.sort(entries, function(a, b)
        return a.port < b.port
      end)
    end
    cb(err, entries or {})
  end)

  local backend = M.backend()
  if backend == "lsof" then
    scan_lsof(wrapped)
  elseif backend == "ss" then
    scan_ss(wrapped)
  else
    wrapped("no supported backend found (need `lsof` or `ss`)", {})
  end
end

return M
