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

--- Border title/footer chunks default to rendering on the bright FloatTitle /
--- FloatFooter background. We want the chunk text to sit on the ordinary float
--- background instead, so the bright accent stays on the border itself rather
--- than filling a bar behind the title and footer. These derived groups graft
--- each accent foreground onto the NormalFloat background.
---@type table<string, {fg: string, extra: table|nil}>
local DERIVED = {
  PortsTitleName = { fg = "Title", extra = { bold = true } },
  PortsTitleDim = { fg = "Comment" },
  PortsTitleCount = { fg = "Identifier" },
  PortsTitleStale = { fg = "DiagnosticWarn" },
  PortsFooterKey = { fg = "Special" },
  PortsFooterLabel = { fg = "NonText" },
}

local function setup_highlights()
  for name, link in pairs(HL) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end

  local function attrs(group)
    return vim.api.nvim_get_hl(0, { name = group, link = false })
  end

  -- Column header reads best as a dim, bold label; derive it from Comment so
  -- it tracks the colorscheme while staying distinct from data rows.
  vim.api.nvim_set_hl(0, "PortsColHeader", { fg = attrs("Comment").fg, bold = true, default = true })

  -- Match the window body so title/footer text blends with the float instead
  -- of sitting on the bright FloatTitle/FloatFooter bar.
  local float_bg = attrs("NormalFloat").bg or attrs("Normal").bg
  for name, spec in pairs(DERIVED) do
    local hl = { fg = attrs(spec.fg).fg, bg = float_bg, default = true }
    if spec.extra then
      hl = vim.tbl_extend("force", hl, spec.extra)
    end
    vim.api.nvim_set_hl(0, name, hl)
  end

  -- Thin bright bars flanking the title, drawn as a foreground glyph (not a
  -- filled block) in the FloatTitle colour, falling back to the border colour.
  local bar_fg = attrs("FloatTitle").bg or attrs("FloatBorder").fg
  vim.api.nvim_set_hl(0, "PortsTitleBar", { fg = bar_fg, bg = float_bg, default = true })
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

--- Total display width of every column up to (but excluding) COMMAND.
---@return integer
local function fixed_prefix_width()
  return COL.gutter + COL.port + #GAP + COL.type + #GAP + COL.pid + #GAP + COL.uptime + #GAP + COL.address + #GAP
end

--- Resolve a config dimension: a fraction (<=1) of `total`, or an absolute
--- count capped at `total`.
---@param v number
---@param total integer
---@return integer
local function resolve_dim(v, total)
  if v <= 1 then
    return math.floor(total * v)
  end
  return math.min(math.floor(v), total)
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

--- The keymap legend as border-footer chunks, so it stays pinned to the
--- window frame and remains visible even when the list scrolls. Returns the
--- chunk list and its total display width.
---@return table[] chunks, integer width
local function footer_chunks()
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
  local chunks = {}
  local width = 0
  local function put(text, hl)
    chunks[#chunks + 1] = { text, hl }
    width = width + vim.fn.strdisplaywidth(text)
  end
  put(" ", "PortsFooterLabel")
  local first = true
  for _, it in ipairs(items) do
    local lhs = k[it[1]]
    if lhs then
      if not first then
        put("   ", "PortsFooterLabel")
      end
      put(lhs, "PortsFooterKey")
      put(" " .. it[2], "PortsFooterLabel")
      first = false
    end
  end
  put(" ", "PortsFooterLabel")
  return chunks, width
end

--- The window title as border chunks: a styled name plus live counts. Returns
--- the chunk list and its total display width.
---@param n_listening integer
---@param n_stale integer
---@return table[] chunks, integer width
local function title_chunks(n_listening, n_stale)
  local chunks = {}
  local width = 0
  local function put(text, hl)
    chunks[#chunks + 1] = { text, hl }
    width = width + vim.fn.strdisplaywidth(text)
  end
  put("▎", "PortsTitleBar")
  if config.options.ui.icons then
    put(" ", "PortsTitleName")
  end
  put("Ports", "PortsTitleName")
  put("  ·  ", "PortsTitleDim")
  put(tostring(n_listening), "PortsTitleCount")
  put(" listening", "PortsTitleDim")
  if n_stale > 0 then
    put("  ·  ", "PortsTitleDim")
    put(tostring(n_stale), "PortsTitleStale")
    put(" stale", "PortsTitleStale")
  end
  if state.stale_only then
    put("  ·  ", "PortsTitleDim")
    put("stale-only", "PortsTitleDim")
  end
  put(" ", "PortsTitleDim")
  put("🮇", "PortsTitleBar")
  return chunks, width
end

--- A horizontal rule spanning the inner window width.
---@param width integer
---@return table line
local function rule_line(width)
  local line = new_line()
  add(line, " " .. string.rep("─", math.max(1, width - 2)), "PortsRule")
  return line
end

--- Build the table buffer (column header + rule + rows). Chrome — the title
--- counts and the keymap legend — lives in the window border, not here, so it
--- stays visible when the table scrolls.
---@param entries ports.Entry[]
---@param cmd_w integer  width allotted to the COMMAND column
---@param rule_w integer width of the header rule
---@return string[] lines
---@return table[] hls            list of {row, startc, endc, hl}
---@return table<integer, ports.Entry> rows
---@return table[] stale_marks    list of {row, reason}
local function build(entries, cmd_w, rule_w)
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
  push(rule_line(rule_w))

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

  return lines, hls, rows, stale_marks
end

--- Paint the buffer with the current data and size the window to fit it,
--- capped at the configured width/height maxima.
---@param entries ports.Entry[]
local function paint(entries)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  local ui = config.options.ui

  -- Counts (over all listeners, regardless of any stale-only filter).
  local stale_count = 0
  for _, e in ipairs(entries) do
    if e.stale then
      stale_count = stale_count + 1
    end
  end

  -- Width: fit the longest visible command, but also the title and legend, all
  -- capped at the configured maximum. The COMMAND column absorbs the slack.
  local fixed = fixed_prefix_width()
  local max_cmd = vim.fn.strdisplaywidth("COMMAND")
  for _, e in ipairs(entries) do
    if not state.stale_only or e.stale then
      max_cmd = math.max(max_cmd, vim.fn.strdisplaywidth(e.args or e.command or ""))
    end
  end
  local title, title_w = title_chunks(#entries, stale_count)
  local _, footer_w = footer_chunks()

  local max_w = math.max(24, resolve_dim(ui.width, vim.o.columns))
  local desired = math.max(fixed + max_cmd, title_w + 2, footer_w + 2)
  local width = math.max(fixed + 8, math.min(max_w, desired))
  local cmd_w = width - fixed

  local lines, hls, rows, stale_marks = build(entries, cmd_w, width)
  state.rows = rows

  -- Height: fit every row, capped at the configured maximum and the screen.
  local max_h = math.max(1, resolve_dim(ui.height, vim.o.lines))
  local height = math.max(1, math.min(#lines, max_h, vim.o.lines - 2))

  -- Resize and re-centre, and refresh the live counts in the border title.
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_config, state.win, {
      relative = "editor",
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      title = title,
      title_pos = "center",
    })
  end

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

--- Initial floating-window geometry, shown while the first scan runs. The
--- window is resized to fit content by `paint`; the border footer (the keymap
--- legend) is static and set once here.
---@return table win_config
local function win_geometry()
  local ui = config.options.ui
  local footer, footer_w = footer_chunks()
  local title = title_chunks(0, 0)
  local max_w = math.max(24, resolve_dim(ui.width, vim.o.columns))
  local width = math.min(max_w, footer_w + 2)
  local height = 1
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = ui.border,
    title = title,
    title_pos = "center",
    footer = footer,
    footer_pos = "center",
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
