# ports.nvim

See what's listening on your machine — and what it actually is — without leaving Neovim.

`:Ports` scans local listening ports, identifies each one (Next.js, Vite,
Postgres, Redis, …), and gives you kill / open-in-browser / tail-logs actions
right there in the list.

<img width="1143" height="312" alt="Screenshot 2026-06-30 at 8 34 05 AM" src="https://github.com/user-attachments/assets/23388eb1-5dd1-48c6-bbcb-e4346c9c8b99" />

## Features

- **List listening ports** — every local TCP listener, sorted by port.
- **Tell you what they are** — detects dev frameworks (Next.js, Nuxt, Vite,
  Remix, Astro, Angular, CRA, SvelteKit, Rails, Django, Flask, Laravel,
  Phoenix, …) from the command line, and services (Postgres, MySQL, Redis,
  MongoDB, Elasticsearch, RabbitMQ, …) from the command or well-known port.
- **Kill a process** — `SIGTERM` with one key, `SIGKILL` to escalate.
- **Open in browser** — jump straight to `http://localhost:<port>`.
- **Tail logs** — discovers log files among the process's open file
  descriptors and follows them in a split.
- **Detect stale dev servers** — flags servers whose working directory was
  deleted, duplicate servers running from the same project, and (optionally)
  long-running ones.

No project files to configure, no servers to register. It just looks at what's
running and tells you.

## Requirements

- Neovim **0.10+** (uses `vim.system` and `vim.ui.open`).
- `lsof` (macOS / Linux) or `ss` (Linux, iproute2) for scanning.
- `ps` for uptime / full command line, `kill` to terminate, `tail` for logs.

Run `:checkhealth ports` to confirm your setup.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "willothy/ports.nvim", cmd = "Ports", keys = { { "<leader>p", "<cmd>Ports<cr>", desc = "Ports" } } }
```

Calling `setup()` is **optional** — the plugin works out of the box.

## Usage

| Command            | Description                              |
| ------------------ | ---------------------------------------- |
| `:Ports`           | Open the interactive list                |
| `:Ports toggle`    | Toggle the window                        |
| `:Ports kill {n}`  | Kill whatever is listening on port `n`   |
| `:Ports browser {n}` | Open `http://localhost:n` in a browser |
| `:Ports logs {n}`  | Tail logs for the process on port `n`    |

### In the list

| Key | Action                              |
| --- | ----------------------------------- |
| `o` / `<CR>` | Open in browser            |
| `K` | Kill (SIGTERM)                      |
| `X` | Force kill (SIGKILL)                |
| `L` | Tail logs                           |
| `i` | Show full details                   |
| `y` | Yank the URL                        |
| `s` | Toggle stale-only filter            |
| `r` | Rescan                              |
| `q` / `<Esc>` | Close                      |

## Configuration

All defaults shown; pass only what you want to change.

```lua
require("ports").setup({
  stale = {
    enabled = true,
    orphaned = true,    -- working directory no longer exists
    duplicates = true,  -- another server in the same project directory
    max_age = 0,        -- flag servers older than N seconds (0 = off)
  },
  scan = {
    include_loopback = true,  -- 127.0.0.1 / ::1
    include_any = true,       -- 0.0.0.0 / *
    include_external = true,  -- bound to a specific external interface
  },
  browser = {
    cmd = nil,          -- nil → vim.ui.open; string → run `{cmd, url}`; or function(url)
    scheme = "http",
    host = "localhost",
  },
  ui = {
    border = "rounded",
    width = 0.82,        -- fraction of the editor, or absolute columns (>1)
    height = 0.6,
    icons = true,        -- Nerd Font glyphs in the type column
    auto_refresh = 0,    -- ms; 0 disables periodic rescans while open
  },
  kill = {
    signal = "TERM",
    confirm = true,
  },
  keymaps = { open = "o", kill = "K", force_kill = "X", logs = "L", info = "i",
              yank = "y", refresh = "r", stale = "s", help = "?", quit = "q" },
})
```

Set any keymap to `false` to disable it.

## License

MIT
