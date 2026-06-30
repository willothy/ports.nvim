-- ports.nvim entry point: defines the :Ports command.
-- Guarded so it is only set up once, and tolerant of being loaded without
-- a prior require("ports").setup() call (defaults apply).

if vim.g.loaded_ports then
  return
end
vim.g.loaded_ports = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.api.nvim_err_writeln("ports.nvim requires Neovim 0.10+ (vim.system / vim.ui.open)")
  return
end

--- Subcommands for `:Ports`. Each receives the remaining argument list.
local subcommands = {
  open = function()
    require("ports").open()
  end,
  toggle = function()
    require("ports").toggle()
  end,
  kill = function(args)
    local port = tonumber(args[1])
    if not port then
      vim.notify("ports: usage :Ports kill {port}", vim.log.levels.ERROR)
      return
    end
    require("ports").kill(port)
  end,
  browser = function(args)
    local port = tonumber(args[1])
    if not port then
      vim.notify("ports: usage :Ports browser {port}", vim.log.levels.ERROR)
      return
    end
    require("ports").open_browser(port)
  end,
  logs = function(args)
    local port = tonumber(args[1])
    if not port then
      vim.notify("ports: usage :Ports logs {port}", vim.log.levels.ERROR)
      return
    end
    require("ports").logs(port)
  end,
}

vim.api.nvim_create_user_command("Ports", function(opts)
  local args = opts.fargs
  if #args == 0 then
    require("ports").open()
    return
  end
  local sub = args[1]
  local handler = subcommands[sub]
  if not handler then
    vim.notify("ports: unknown subcommand '" .. sub .. "'", vim.log.levels.ERROR)
    return
  end
  table.remove(args, 1)
  handler(args)
end, {
  nargs = "*",
  desc = "ports.nvim: manage local dev servers and ports",
  complete = function(arglead, cmdline, _)
    -- Count whitespace-delimited tokens already on the line (literal split).
    local tokens = vim.tbl_filter(function(t)
      return t ~= ""
    end, vim.split(cmdline, " ", { plain = true }))
    -- "Ports" plus the (partial) subcommand → still completing the subcommand.
    local completing_subcommand = #tokens <= 1 or (#tokens == 2 and arglead ~= "")
    if completing_subcommand then
      local names = vim.tbl_keys(subcommands)
      table.sort(names)
      return vim.tbl_filter(function(name)
        return vim.startswith(name, arglead)
      end, names)
    end
    return {}
  end,
})
