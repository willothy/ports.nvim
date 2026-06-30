--- Shared, dependency-free helpers.
---
--- Parsing here is intentionally hand-written (byte scanning / literal splits)
--- rather than pattern-based so the behaviour stays explicit and predictable.
local M = {}

--- Return the index of the last occurrence of a single byte in `s`, or nil.
---@param s string
---@param ch string single character
---@return integer|nil
function M.rfind(s, ch)
  for i = #s, 1, -1 do
    if string.sub(s, i, i) == ch then
      return i
    end
  end
  return nil
end

--- Literal (non-pattern) substring test.
---@param haystack string
---@param needle string
---@return boolean
function M.contains(haystack, needle)
  return string.find(haystack, needle, 1, true) ~= nil
end

--- Trim ASCII whitespace from both ends without using patterns.
---@param s string
---@return string
function M.trim(s)
  local n = #s
  local i = 1
  while i <= n do
    local c = string.sub(s, i, i)
    if c == " " or c == "\t" or c == "\r" or c == "\n" then
      i = i + 1
    else
      break
    end
  end
  local j = n
  while j >= i do
    local c = string.sub(s, j, j)
    if c == " " or c == "\t" or c == "\r" or c == "\n" then
      j = j - 1
    else
      break
    end
  end
  return string.sub(s, i, j)
end

--- Split a string on a literal separator, dropping empty trailing fields.
---@param s string
---@param sep string
---@return string[]
function M.split(s, sep)
  return vim.split(s, sep, { plain = true, trimempty = false })
end

--- Parse a single whitespace-delimited token starting at byte `from`.
--- Skips leading spaces, then reads until the next space.
---@param s string
---@param from integer
---@return string token, integer next start byte
local function read_token(s, from)
  local n = #s
  local i = from
  while i <= n and string.sub(s, i, i) == " " do
    i = i + 1
  end
  local start = i
  while i <= n and string.sub(s, i, i) ~= " " do
    i = i + 1
  end
  return string.sub(s, start, i - 1), i
end

M.read_token = read_token

--- Parse `ps -o pid=,etime=,args=` style output line into its three fields.
--- `args` is everything after the first two whitespace-delimited columns and
--- may itself contain spaces, so it is taken verbatim.
---@param line string
---@return integer|nil pid
---@return string|nil etime
---@return string|nil args
function M.parse_ps_line(line)
  local pid_str, i = read_token(line, 1)
  local pid = tonumber(pid_str)
  if not pid then
    return nil
  end
  local etime, j = read_token(line, i)
  -- Skip the single space separating etime from args, but preserve any
  -- spaces that are part of the command itself.
  local n = #line
  while j <= n and string.sub(line, j, j) == " " do
    j = j + 1
  end
  local args = string.sub(line, j)
  return pid, etime, args
end

--- Convert a `ps` ELAPSED field (`[[dd-]hh:]mm:ss`) into seconds.
---@param etime string
---@return integer
function M.etime_to_secs(etime)
  etime = M.trim(etime)
  if etime == "" then
    return 0
  end
  local days = 0
  local dash = string.find(etime, "-", 1, true)
  if dash then
    days = tonumber(string.sub(etime, 1, dash - 1)) or 0
    etime = string.sub(etime, dash + 1)
  end
  local parts = M.split(etime, ":")
  local h, m, s = 0, 0, 0
  if #parts == 3 then
    h = tonumber(parts[1]) or 0
    m = tonumber(parts[2]) or 0
    s = tonumber(parts[3]) or 0
  elseif #parts == 2 then
    m = tonumber(parts[1]) or 0
    s = tonumber(parts[2]) or 0
  elseif #parts == 1 then
    s = tonumber(parts[1]) or 0
  end
  return ((days * 24 + h) * 60 + m) * 60 + s
end

--- Human-friendly compact duration, e.g. "2h 13m", "5d 4h", "47s".
---@param secs integer|nil
---@return string
function M.human_duration(secs)
  if not secs or secs < 0 then
    return "-"
  end
  if secs < 60 then
    return string.format("%ds", secs)
  end
  local mins = math.floor(secs / 60)
  if mins < 60 then
    return string.format("%dm", mins)
  end
  local hours = math.floor(mins / 60)
  mins = mins % 60
  if hours < 24 then
    return string.format("%dh %dm", hours, mins)
  end
  local days = math.floor(hours / 24)
  hours = hours % 24
  return string.format("%dd %dh", days, hours)
end

--- Expand a leading `~` and environment variables in a path.
---@param path string
---@return string
function M.expand(path)
  if not path or path == "" then
    return path
  end
  return vim.fn.expand(path)
end

--- Shorten an absolute path for display, keeping the last two segments.
---@param path string
---@param max integer
---@return string
function M.shorten_path(path, max)
  if not path or path == "" then
    return ""
  end
  if #path <= max then
    return path
  end
  local segs = M.split(path, "/")
  local tail
  if #segs >= 2 then
    tail = segs[#segs - 1] .. "/" .. segs[#segs]
  else
    tail = segs[#segs]
  end
  return "…/" .. tail
end

--- Truncate a display string to `max` columns, appending an ellipsis.
---@param s string
---@param max integer
---@return string
function M.truncate(s, max)
  if max <= 0 then
    return ""
  end
  if vim.fn.strdisplaywidth(s) <= max then
    return s
  end
  -- Trim byte-by-byte until it fits (commands are ASCII-dominant; this stays
  -- correct for multibyte by measuring display width each step).
  local out = s
  while #out > 0 and vim.fn.strdisplaywidth(out .. "…") > max do
    out = string.sub(out, 1, #out - 1)
  end
  return out .. "…"
end

return M
