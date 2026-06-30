--- Identify what is listening on a port.
---
--- Detection layers, in priority order:
---   1. Command-line signatures (dev frameworks, app servers).
---   2. Well-known service ports (databases, brokers, caches).
---   3. A prettified fallback to the raw command name.
---
--- Matching against the command line uses literal substring tests on a
--- lowercased copy (no patterns).
local util = require("ports.util")

local M = {}

--- Dev-framework / app-server signatures. `kw` is matched as a literal
--- substring of the lowercased command line. `server = true` marks something
--- that is a long-running dev server (used by stale detection). Ordered most
--- specific first so e.g. "next" wins before a bare "node".
---@type {kw: string, name: string, server: boolean, icon: string}[]
local SIGNATURES = {
  { kw = "next dev", name = "Next.js", server = true, icon = "" },
  { kw = "next-server", name = "Next.js", server = true, icon = "" },
  { kw = "next/dist/bin", name = "Next.js", server = true, icon = "" },
  { kw = "/.bin/next", name = "Next.js", server = true, icon = "" },
  { kw = "nuxt", name = "Nuxt", server = true, icon = "" },
  { kw = "vite", name = "Vite", server = true, icon = "" },
  { kw = "astro", name = "Astro", server = true, icon = "" },
  { kw = "remix", name = "Remix", server = true, icon = "" },
  { kw = "ng serve", name = "Angular", server = true, icon = "" },
  { kw = "@angular", name = "Angular", server = true, icon = "" },
  { kw = "react-scripts", name = "Create React App", server = true, icon = "" },
  { kw = "vue-cli-service", name = "Vue CLI", server = true, icon = "" },
  { kw = "svelte-kit", name = "SvelteKit", server = true, icon = "" },
  { kw = "sveltekit", name = "SvelteKit", server = true, icon = "" },
  { kw = "gatsby", name = "Gatsby", server = true, icon = "" },
  { kw = "storybook", name = "Storybook", server = true, icon = "" },
  { kw = "webpack", name = "webpack", server = true, icon = "" },
  { kw = "parcel", name = "Parcel", server = true, icon = "" },
  { kw = "esbuild", name = "esbuild", server = true, icon = "" },
  { kw = "turbopack", name = "Turbopack", server = true, icon = "" },
  { kw = "rollup", name = "Rollup", server = true, icon = "" },
  { kw = "manage.py runserver", name = "Django", server = true, icon = "" },
  { kw = "django", name = "Django", server = true, icon = "" },
  { kw = "flask", name = "Flask", server = true, icon = "" },
  { kw = "uvicorn", name = "Uvicorn", server = true, icon = "" },
  { kw = "gunicorn", name = "Gunicorn", server = true, icon = "" },
  { kw = "hypercorn", name = "Hypercorn", server = true, icon = "" },
  { kw = "fastapi", name = "FastAPI", server = true, icon = "" },
  { kw = "php artisan serve", name = "Laravel", server = true, icon = "" },
  { kw = "artisan serve", name = "Laravel", server = true, icon = "" },
  { kw = "rails server", name = "Rails", server = true, icon = "" },
  { kw = "rails s", name = "Rails", server = true, icon = "" },
  { kw = "puma", name = "Puma", server = true, icon = "" },
  { kw = "unicorn", name = "Unicorn", server = true, icon = "" },
  { kw = "hugo server", name = "Hugo", server = true, icon = "" },
  { kw = "jekyll serve", name = "Jekyll", server = true, icon = "" },
  { kw = "mix phx.server", name = "Phoenix", server = true, icon = "" },
  { kw = "air", name = "Go (air)", server = true, icon = "" },
}

--- Well-known service ports for things that don't reveal themselves on the
--- command line (or whose command name is uninformative).
---@type table<integer, {name: string, icon: string}>
local SERVICE_PORTS = {
  [5432] = { name = "Postgres", icon = "" },
  [5433] = { name = "Postgres", icon = "" },
  [3306] = { name = "MySQL", icon = "" },
  [33060] = { name = "MySQL", icon = "" },
  [6379] = { name = "Redis", icon = "" },
  [6380] = { name = "Redis", icon = "" },
  [27017] = { name = "MongoDB", icon = "" },
  [27018] = { name = "MongoDB", icon = "" },
  [9200] = { name = "Elasticsearch", icon = "" },
  [9300] = { name = "Elasticsearch", icon = "" },
  [5601] = { name = "Kibana", icon = "" },
  [5672] = { name = "RabbitMQ", icon = "" },
  [15672] = { name = "RabbitMQ", icon = "" },
  [11211] = { name = "Memcached", icon = "" },
  [9092] = { name = "Kafka", icon = "" },
  [2181] = { name = "ZooKeeper", icon = "" },
  [8086] = { name = "InfluxDB", icon = "" },
  [25] = { name = "SMTP", icon = "" },
  [1025] = { name = "Mailhog SMTP", icon = "" },
  [8025] = { name = "Mailhog UI", icon = "" },
}

--- Command names that, by themselves, denote a known service.
---@type table<string, {name: string, icon: string}>
local SERVICE_COMMANDS = {
  ["postgres"] = { name = "Postgres", icon = "" },
  ["postmaster"] = { name = "Postgres", icon = "" },
  ["mysqld"] = { name = "MySQL", icon = "" },
  ["mariadbd"] = { name = "MariaDB", icon = "" },
  ["redis-server"] = { name = "Redis", icon = "" },
  ["mongod"] = { name = "MongoDB", icon = "" },
  ["memcached"] = { name = "Memcached", icon = "" },
  ["docker"] = { name = "Docker", icon = "" },
  ["com.docker.backend"] = { name = "Docker", icon = "" },
  ["dockerd"] = { name = "Docker", icon = "" },
  ["nginx"] = { name = "nginx", icon = "" },
  ["caddy"] = { name = "Caddy", icon = "" },
  ["ollama"] = { name = "Ollama", icon = "" },
}

--- Prettify a raw command name for the fallback case.
---@param command string|nil
---@return string
local function prettify(command)
  if not command or command == "" then
    return "unknown"
  end
  return command
end

--- Detect the service/framework for an entry, mutating it in place with
--- `type`, `icon`, and `is_server` fields.
---@param entry ports.Entry
---@return ports.Entry
function M.detect(entry)
  local hay = string.lower(entry.args or entry.command or "")

  for _, sig in ipairs(SIGNATURES) do
    if util.contains(hay, sig.kw) then
      entry.type = sig.name
      entry.icon = sig.icon
      entry.is_server = sig.server
      return entry
    end
  end

  local svc_cmd = SERVICE_COMMANDS[string.lower(entry.command or "")]
  if svc_cmd then
    entry.type = svc_cmd.name
    entry.icon = svc_cmd.icon
    entry.is_server = false
    return entry
  end

  local svc = SERVICE_PORTS[entry.port]
  if svc then
    entry.type = svc.name
    entry.icon = svc.icon
    entry.is_server = false
    return entry
  end

  -- Generic runtimes: report the runtime but treat as a (probable) server so
  -- stale heuristics still apply to a bare `node`/`bun`/`deno` listener.
  local cmd = string.lower(entry.command or "")
  if cmd == "node" or cmd == "bun" or cmd == "deno" or cmd == "python" or cmd == "python3" then
    entry.type = prettify(entry.command)
    entry.icon = ""
    entry.is_server = true
    return entry
  end

  entry.type = prettify(entry.command)
  entry.icon = ""
  entry.is_server = false
  return entry
end

--- Run detection over a list of entries.
---@param entries ports.Entry[]
---@return ports.Entry[]
function M.detect_all(entries)
  for _, e in ipairs(entries) do
    M.detect(e)
  end
  return entries
end

return M
