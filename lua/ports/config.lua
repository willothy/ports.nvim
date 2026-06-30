--- Configuration: defaults + user merge.
local M = {}

---@class ports.Config
M.defaults = {
  --- Stale dev-server detection. Each enabled rule annotates matching dev
  --- servers with a human-readable reason shown in the UI.
  stale = {
    enabled = true,
    --- Flag dev servers whose working directory no longer exists on disk.
    orphaned = true,
    --- Flag multiple dev servers running from the same project directory.
    duplicates = true,
    --- Flag dev servers running longer than this many seconds. 0 disables.
    max_age = 0,
  },

  --- Which listeners to display.
  scan = {
    include_loopback = true, -- 127.0.0.1 / ::1
    include_any = true, -- 0.0.0.0 / *
    include_external = true, -- bound to a specific external interface
  },

  browser = {
    --- nil → use `vim.ui.open` (cross-platform). A string is run as
    --- `{cmd, url}`. A function receives the URL and is fully responsible.
    ---@type string|fun(url: string)|nil
    cmd = nil,
    scheme = "http",
    host = "localhost",
  },

  ui = {
    border = "rounded",
    --- Fractions of the editor (0–1) or absolute columns/rows (>1).
    width = 0.82,
    height = 0.6,
    --- Use Nerd Font glyphs for the type column.
    icons = true,
    --- Auto-refresh interval in ms while the window is open. 0 disables.
    auto_refresh = 0,
  },

  --- Send SIGTERM first; the UI offers an escalation to SIGKILL.
  kill = {
    signal = "TERM",
    confirm = true,
  },

  ---@type table<string, string|false>
  keymaps = {
    open = "o", -- open in browser
    kill = "K", -- terminate process (SIGTERM)
    force_kill = "X", -- terminate process (SIGKILL)
    logs = "L", -- tail logs
    info = "i", -- show full details for the entry
    yank = "y", -- copy the URL to the clipboard
    refresh = "r", -- rescan
    stale = "s", -- toggle stale-only filter
    help = "?", -- toggle the keymap legend
    quit = "q", -- close the window
  },
}

---@type ports.Config
M.options = vim.deepcopy(M.defaults)

--- Merge user options over the defaults.
---@param opts table|nil
---@return ports.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
