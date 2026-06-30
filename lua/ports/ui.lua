--- Interactive floating window: list listening ports with inline actions.
local config = require("ports.config")
local util = require("ports.util")

local M = {}

local NS = vim.api.nvim_create_namespace("ports.ui")

--- Default highlight links, defined lazily so a user colorscheme wins.
local HL = {
  PortsTitle = "Title",
  PortsPort = "Number",
  PortsType = "Function",
  PortsIcon = "Special",
  PortsPid = "Comment",
  PortsUptime = "Comment",
  PortsAddress = "String",
  PortsCommand = "Comment",
  PortsStale = "DiagnosticWarn",
  PortsDotOk = "DiagnosticOk",
  PortsDotStale = "DiagnosticWarn",
  PortsHeader = "Comment",
  PortsFooter = "NonText",
  PortsKey = "Special",
  PortsCount = "Identifier",
  PortsRule = "FloatBorder",
  PortsCursorLine = "CursorLine",
}

local function setup_highlights()
  for name, link in pairs(HL) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  -- Column header reads best as a dim, bold label; derive it from Comment so
  -- it tracks the colorscheme while staying distinct from data rows.
  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  vim.api.nvim_set_hl(0, "PortsColHeader", { fg = comment.fg, bold = true, default = true })
end

--- Module-level singleton state for the one ports window.
---@class ports.UIState
---@field buf integer|nil
---@field win integer|nil
---@field rows table<integer, ports.Entry> line (1-based) -> entry
---@field stale_only boolean
---@field show_help boolean
---@field loading boolean
---@field timer userdata|nil
local state = {
  buf = nil,
  win = nil,
  rows = {},
  stale_only = false,
  show_help = false,
  loading = false,
  timer = nil,
}

-- Column widths (display cells). Command takes the remaining space.
local COL = {
  gutter = 3, -- " ● " status dot with margins
  port = 6,
  type = 20,
  pid = 8,
  uptime = 9,
  address = 18,
}
local GAP = "  "

--- Pad a string to `width` display cells.
---@param s string
---@param width integer
---@param right_align boolean|nil
---@return string
local function pad(s, width, right_align)
  local disp = vim.fn.strdisplaywidth(s)
  if disp >= width then
    return s
  end
  local fill = string.rep(" ", width - disp)
  return right_align and (fill .. s) or (s .. fill)
end

--- A simple line builder that tracks byte ranges for highlighting.
local function new_line()
  return { text = "", hls = {} }
end

---@param line table
---@param text string
---@param hl string|nil
local function add(line, text, hl)
  local startc = #line.text
  line.text = line.text .. text
  if hl and text ~= "" then
    line.hls[#line.hls + 1] = { startc, #line.text, hl }
  end
end

--- Compute the width available for the command column.
---@param win_width integer
---@return integer
local function command_width(win_width)
  local used = COL.gutter + #GAP + COL.port + #GAP + COL.type + #GAP + COL.pid + #GAP + COL.uptime + #GAP + COL.address + #GAP
  return math.max(10, win_width - used - 1)
end

--- Render a single entry row into a line builder.
---@param entry ports.Entry
---@param cmd_w integer
---@return table line
local function render_entry(entry, cmd_w)
  local line = new_line()

  -- Gutter: a status dot, coloured by health (green = ok, amber = stale).
  add(line, " ")
  add(line, "●", entry.stale and "PortsDotStale" or "PortsDotOk")
  add(line, " ")

  -- Port.
  add(line, pad(tostring(entry.port), COL.port, true), "PortsPort")
  add(line, GAP)

  -- Type (icon + detected name) — the "what is this?" column. The glyph and
  -- the name are coloured separately so the icon keeps its category accent.
  local label = entry.type or entry.command or "?"
  local icon = config.options.ui.icons and entry.icon ~= nil and entry.icon ~= "" and entry.icon or nil
  local name_w = COL.type - (icon and 2 or 0)
  local name = util.truncate(label, name_w)
  if icon then
    add(line, icon, "PortsIcon")
    add(line, " ")
  end
  add(line, name, "PortsType")
  local used = (icon and 2 or 0) + vim.fn.strdisplaywidth(name)
  if used < COL.type then
    add(line, string.rep(" ", COL.type - used))
  end
  add(line, GAP)

  -- PID.
  add(line, pad(entry.pid and tostring(entry.pid) or "-", COL.pid, true), "PortsPid")
  add(line, GAP)

  -- Uptime.
  add(line, pad(entry.uptime and util.human_duration(entry.uptime) or "-", COL.uptime), "PortsUptime")
  add(line, GAP)

  -- Address.
  add(line, pad(util.truncate(entry.address or "-", COL.address), COL.address), "PortsAddress")
  add(line, GAP)

  -- Full command line.
  add(line, util.truncate(entry.args or entry.command or "", cmd_w), "PortsCommand")

  return line
end

--- The keymap legend shown at the bottom / when toggled.
---@return string[]
local function help_lines()
  local k = config.options.keymaps
  local function key(name, label)
    local lhs = k[name]
    if not lhs then
      return nil
    end
    return string.format("%s %s", lhs, label)
  end
  local items = {
    key("open", "open"),
    key("kill", "kill"),
    key("force_kill", "force-kill"),
    key("logs", "logs"),
    key("info", "info"),
    key("yank", "yank url"),
    key("stale", "stale-only"),
    key("refresh", "refresh"),
    key("quit", "quit"),
  }
  local present = {}
  for _, it in ipairs(items) do
    if it then
      present[#present + 1] = it
    end
  end
  return { "  " .. table.concat(present, "   ") }
end

--- The footer key/label hints, built as a styled line so keys stand out from
--- their descriptions.
---@return table line
local function footer_line()
  local k = config.options.keymaps
  local items = {
    { "open", "open" },
    { "kill", "kill" },
    { "force_kill", "force" },
    { "logs", "logs" },
    { "info", "info" },
    { "yank", "yank" },
    { "stale", "stale" },
    { "refresh", "refresh" },
    { "quit", "quit" },
  }
  local line = new_line()
  add(line, " ")
  local first = true
  for _, it in ipairs(items) do
    local lhs = k[it[1]]
    if lhs then
      add(line, first and " " or "   ")
      add(line, lhs, "PortsKey")
      add(line, " " .. it[2], "PortsFooter")
      first = false
    end
  end
  return line
end

--- A horizontal rule spanning the inner window width.
---@param width integer
---@return table line
local function rule_line(width)
  local line = new_line()
  add(line, " " .. string.rep("─", math.max(1, width - 2)), "PortsRule")
  return line
end

--- Build all buffer lines + highlights + the line→entry row map.
---@param entries ports.Entry[]
---@return string[] lines
---@return table[] hls            list of {row, startc, endc, hl}
---@return table<integer, ports.Entry> rows
---@return table[] stale_marks    list of {row, reason}
local function build(entries)
  local win_width = state.win and vim.api.nvim_win_get_width(state.win) or 80
  local cmd_w = command_width(win_width)

  local lines = {}
  local hls = {}
  local rows = {}
  local stale_marks = {}

  local function push(line_obj)
    lines[#lines + 1] = line_obj.text
    local row = #lines - 1
    for _, h in ipairs(line_obj.hls) do
      hls[#hls + 1] = { row, h[1], h[2], h[3] }
    end
    return row
  end

  -- Summary header.
  local stale_count = 0
  for _, e in ipairs(entries) do
    if e.stale then
      stale_count = stale_count + 1
    end
  end
  local icons = config.options.ui.icons
  local summary = new_line()
  add(summary, " ")
  if icons then
    add(summary, " ", "PortsTitle")
  end
  add(summary, "Ports", "PortsTitle")
  add(summary, "   ")
  add(summary, tostring(#entries), "PortsCount")
  add(summary, " listening", "PortsHeader")
  if stale_count > 0 then
    add(summary, "  ·  ", "PortsHeader")
    add(summary, tostring(stale_count), "PortsStale")
    add(summary, " stale", "PortsStale")
  end
  if state.stale_only then
    add(summary, "  ·  ", "PortsHeader")
    add(summary, "stale-only", "PortsHeader")
  end
  push(summary)
  push(new_line())

  -- Column header.
  local head = new_line()
  add(head, pad("", COL.gutter))
  add(head, pad("PORT", COL.port, true))
  add(head, GAP)
  add(head, pad("TYPE", COL.type))
  add(head, GAP)
  add(head, pad("PID", COL.pid, true))
  add(head, GAP)
  add(head, pad("UPTIME", COL.uptime))
  add(head, GAP)
  add(head, pad("ADDRESS", COL.address))
  add(head, GAP)
  add(head, "COMMAND")
  local head_row = push(head)
  hls[#hls + 1] = { head_row, 0, #head.text, "PortsColHeader" }
  push(rule_line(win_width))

  -- Live entries.
  local shown = 0
  for _, e in ipairs(entries) do
    if not state.stale_only or e.stale then
      local row = push(render_entry(e, cmd_w))
      rows[row + 1] = e -- rows keyed 1-based (matches nvim_win_get_cursor)
      shown = shown + 1
      if e.stale then
        stale_marks[#stale_marks + 1] = { row, table.concat(e.stale.reasons, "; ") }
      end
    end
  end

  if shown == 0 then
    local empty = new_line()
    add(empty, state.stale_only and "  No stale dev servers." or "  No listening ports found.", "PortsHeader")
    push(empty)
  end

  -- Footer: a rule, then the styled key/label hints.
  push(rule_line(win_width))
  push(footer_line())

  return lines, hls, rows, stale_marks
end

--- Paint the buffer with the current data.
---@param entries ports.Entry[]
local function paint(entries)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  local lines, hls, rows, stale_marks = build(entries)
  state.rows = rows

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, h[1], h[2], {
      end_col = h[3],
      hl_group = h[4],
    })
  end
  -- Stale reasons as dim virtual text at end of the row.
  for _, m in ipairs(stale_marks) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, m[1], 0, {
      virt_text = { { "  ⚠ " .. m[2], "PortsStale" } },
      virt_text_pos = "eol",
    })
  end
end

--- The entry under the cursor, or nil.
---@return ports.Entry|nil
local function current_entry()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.rows[lnum]
end

--- Move the cursor to the first selectable row.
local function place_cursor()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return
  end
  local total = vim.api.nvim_buf_line_count(state.buf)
  for lnum = 1, total do
    if state.rows[lnum] then
      vim.api.nvim_win_set_cursor(state.win, { lnum, 0 })
      return
    end
  end
end

--- Rescan and repaint.
---@param keep_cursor boolean|nil
function M.refresh(keep_cursor)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  state.loading = true
  local saved = keep_cursor and state.win and vim.api.nvim_win_is_valid(state.win)
      and vim.api.nvim_win_get_cursor(state.win)
    or nil
  require("ports").list(function(err, entries)
    state.loading = false
    if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
      return
    end
    if err then
      vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
      vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "  ports.nvim error:", "  " .. err })
      vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
      return
    end
    paint(entries)
    if saved then
      local count = vim.api.nvim_buf_line_count(state.buf)
      saved[1] = math.min(saved[1], count)
      pcall(vim.api.nvim_win_set_cursor, state.win, saved)
    else
      place_cursor()
    end
  end)
end

-- Action handlers -----------------------------------------------------------

local function act_open()
  local e = current_entry()
  if not e then
    return
  end
  require("ports.browser").open_entry(e, function(ok, err)
    if not ok then
      vim.notify("ports: failed to open browser: " .. (err or "?"), vim.log.levels.ERROR)
    end
  end)
end

---@param signal string
local function do_kill(e, signal)
  require("ports.process").kill(e.pid, signal, function(ok, err)
    if ok then
      vim.notify(("ports: sent SIG%s to %s (pid %d)"):format(signal, e.type or "process", e.pid))
      -- Give the process a moment to exit, then refresh.
      vim.defer_fn(function()
        M.refresh(true)
      end, 250)
    else
      vim.notify("ports: kill failed: " .. (err or "?"), vim.log.levels.ERROR)
    end
  end)
end

---@param signal string
local function act_kill(signal)
  local e = current_entry()
  if not e or not e.pid then
    return
  end
  if config.options.kill.confirm then
    local prompt = ("Kill %s (pid %d) on port %d with SIG%s?"):format(e.type or "process", e.pid, e.port, signal)
    local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
  end
  do_kill(e, signal)
end

local function act_logs()
  local e = current_entry()
  if e then
    require("ports.logs").tail(e)
  end
end

local function act_yank()
  local e = current_entry()
  if not e then
    return
  end
  local url = require("ports.browser").url_for(e)
  vim.fn.setreg("+", url)
  vim.fn.setreg('"', url)
  vim.notify("ports: yanked " .. url)
end

local function act_info()
  local e = current_entry()
  if not e then
    return
  end
  local lines = {
    "Port:    " .. e.port .. "/" .. (e.proto or "tcp"),
    "Type:    " .. (e.type or "?"),
    "PID:     " .. (e.pid and tostring(e.pid) or "-"),
    "PPID:    " .. (e.ppid and tostring(e.ppid) or "-"),
    "User:    " .. (e.user or "-"),
    "Uptime:  " .. (e.uptime and util.human_duration(e.uptime) or "-"),
    "Address: " .. (e.address or "-"),
    "CWD:     " .. (e.cwd or "-"),
    "URL:     " .. require("ports.browser").url_for(e),
    "Command: " .. (e.args or e.command or "-"),
  }
  if e.stale then
    lines[#lines + 1] = "Stale:   " .. table.concat(e.stale.reasons, "; ")
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "ports.nvim" })
end

local function act_toggle_stale()
  state.stale_only = not state.stale_only
  M.refresh(false)
end

local function act_help()
  state.show_help = not state.show_help
  vim.notify(table.concat(help_lines(), "\n"), vim.log.levels.INFO, { title = "ports.nvim keys" })
end

--- Bind buffer-local keymaps from config.
local function set_keymaps()
  local k = config.options.keymaps
  local function map(name, fn)
    local lhs = k[name]
    if lhs and lhs ~= false then
      vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true, desc = "ports: " .. name })
    end
  end
  map("open", act_open)
  -- <CR> always opens too.
  vim.keymap.set("n", "<CR>", act_open, { buffer = state.buf, nowait = true, silent = true, desc = "ports: open" })
  map("kill", function()
    act_kill(config.options.kill.signal)
  end)
  map("force_kill", function()
    act_kill("KILL")
  end)
  map("logs", act_logs)
  map("info", act_info)
  map("yank", act_yank)
  map("refresh", function()
    M.refresh(true)
  end)
  map("stale", act_toggle_stale)
  map("help", act_help)
  map("quit", M.close)
  vim.keymap.set("n", "<Esc>", M.close, { buffer = state.buf, nowait = true, silent = true, desc = "ports: close" })
end

--- Compute floating-window geometry from config fractions/absolutes.
---@return table win_config
local function win_geometry()
  local ui = config.options.ui
  local function dim(v, total)
    if v <= 1 then
      return math.floor(total * v)
    end
    return math.min(v, total)
  end
  local width = dim(ui.width, vim.o.columns)
  local height = dim(ui.height, vim.o.lines)
  local title = ui.icons and "  Ports " or " Ports "
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = ui.border,
    title = { { title, "PortsTitle" } },
    title_pos = "center",
  }
end

local function stop_timer()
  if state.timer then
    state.timer:stop()
    if not state.timer:is_closing() then
      state.timer:close()
    end
    state.timer = nil
  end
end

--- Close the window (buffer is wiped automatically).
function M.close()
  stop_timer()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.rows = {}
end

--- Whether the window is currently open.
---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Open the ports window (focuses it if already open).
function M.open()
  setup_highlights()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.buf })
  vim.api.nvim_set_option_value("filetype", "ports", { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "  ports.nvim — scanning…" })
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  state.win = vim.api.nvim_open_win(state.buf, true, win_geometry())
  vim.api.nvim_set_option_value("cursorline", true, { win = state.win })
  vim.api.nvim_set_option_value("cursorlineopt", "line", { win = state.win })
  vim.api.nvim_set_option_value("wrap", false, { win = state.win })
  -- Route the cursorline through a dedicated group so it can be themed for the
  -- ports window without touching the global CursorLine.
  vim.api.nvim_set_option_value("winhighlight", "CursorLine:PortsCursorLine", { win = state.win })

  set_keymaps()

  -- Clean up state if the window is closed by other means.
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    once = true,
    callback = function()
      stop_timer()
      state.win = nil
      state.buf = nil
      state.rows = {}
    end,
  })

  M.refresh(false)

  local interval = config.options.ui.auto_refresh
  if interval and interval > 0 then
    state.timer = vim.uv.new_timer()
    state.timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        if M.is_open() then
          M.refresh(true)
        else
          stop_timer()
        end
      end)
    )
  end
end

--- Toggle the window.
function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

return M
