local stale = require("ports.stale")

describe("stale.evaluate", function()
  it("flags orphaned and duplicate dev servers but never databases", function()
    local cwd = vim.fn.getcwd()
    local entries = {
      { pid = 1, port = 3000, cwd = "/does/not/exist/xyz", is_server = true, uptime = 100 },
      { pid = 2, port = 3001, cwd = cwd, is_server = true, uptime = 100 },
      { pid = 3, port = 3002, cwd = cwd, is_server = true, uptime = 100 },
      { pid = 4, port = 5432, cwd = "/does/not/exist/xyz", is_server = false, uptime = 100 },
    }
    stale.evaluate(entries, { enabled = true, orphaned = true, duplicates = true, max_age = 0 })

    assert.is_not_nil(entries[1].stale) -- orphaned cwd
    assert.is_not_nil(entries[2].stale) -- duplicate in same cwd
    assert.is_not_nil(entries[3].stale) -- duplicate in same cwd
    assert.is_nil(entries[4].stale) -- a database is never "stale"
  end)

  it("records a human-readable reason", function()
    local entries = { { pid = 1, port = 3000, cwd = "/does/not/exist/xyz", is_server = true, uptime = 5 } }
    stale.evaluate(entries, { enabled = true, orphaned = true, duplicates = false, max_age = 0 })
    assert.is_not_nil(entries[1].stale)
    assert.equals("working directory no longer exists", entries[1].stale.reasons[1])
  end)

  it("respects max_age", function()
    local entries = { { pid = 9, port = 9, cwd = vim.fn.getcwd(), is_server = true, uptime = 100 } }
    stale.evaluate(entries, { enabled = true, orphaned = false, duplicates = false, max_age = 50 })
    assert.is_not_nil(entries[1].stale)
  end)

  it("does not flag a single fresh server in an existing directory", function()
    local entries = { { pid = 1, port = 3000, cwd = vim.fn.getcwd(), is_server = true, uptime = 10 } }
    stale.evaluate(entries, { enabled = true, orphaned = true, duplicates = true, max_age = 0 })
    assert.is_nil(entries[1].stale)
  end)

  it("does nothing when disabled", function()
    local entries = { { pid = 1, port = 3000, cwd = "/does/not/exist/xyz", is_server = true, uptime = 10 } }
    stale.evaluate(entries, { enabled = false })
    assert.is_nil(entries[1].stale)
  end)
end)
