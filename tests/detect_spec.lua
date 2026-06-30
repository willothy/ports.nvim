local detect = require("ports.detect")

--- Run detection over a fresh entry and return it.
local function det(args, command, port)
  local entry = { args = args, command = command, port = port }
  detect.detect(entry)
  return entry
end

describe("detect by command-line signature", function()
  it("identifies Next.js", function()
    assert.equals("Next.js", det("node /app/node_modules/.bin/next dev", "node", 3000).type)
  end)

  it("marks dev frameworks as servers", function()
    assert.is_true(det("node /app/node_modules/.bin/next dev", "node", 3000).is_server)
  end)

  it("identifies Vite", function()
    assert.equals("Vite", det("node /app/node_modules/vite/bin/vite.js", "node", 5173).type)
  end)

  it("identifies Uvicorn from a python command line", function()
    assert.equals("Uvicorn", det("python -m uvicorn app:app", "python3.11", 8000).type)
  end)
end)

describe("detect by service command", function()
  it("identifies Postgres from the command name", function()
    assert.equals("Postgres", det("/usr/local/bin/postgres -D /data", "postgres", 5432).type)
  end)

  it("identifies Redis from the command name", function()
    assert.equals("Redis", det("", "redis-server", 6379).type)
  end)

  it("identifies MongoDB from the command name", function()
    assert.equals("MongoDB", det("", "mongod", 27017).type)
  end)

  it("does not mark databases as dev servers", function()
    assert.is_false(det("", "redis-server", 6379).is_server)
  end)
end)

describe("detect by well-known port", function()
  it("falls back to the port when the command is unknown", function()
    assert.equals("Postgres", det("", "somecustomthing", 5432).type)
  end)
end)

describe("detect fallback", function()
  it("reports the runtime for a bare node process", function()
    assert.equals("node", det("/bin/node server.js", "node", 4000).type)
  end)

  it("treats a bare runtime as a probable server", function()
    assert.is_true(det("/bin/node server.js", "node", 4000).is_server)
  end)

  it("falls back to the raw command name for anything else", function()
    local e = det("", "weird-daemon", 12345)
    assert.equals("weird-daemon", e.type)
    assert.is_false(e.is_server)
  end)
end)
