local util = require("ports.util")

describe("util.rfind", function()
  it("finds the last occurrence of a byte", function()
    assert.equals(6, util.rfind("[::1]:3000", ":"))
  end)

  it("returns nil when the byte is absent", function()
    assert.is_nil(util.rfind("abc", ":"))
  end)
end)

describe("util.contains", function()
  it("matches a literal substring", function()
    assert.is_true(util.contains("node next dev", "next"))
  end)

  it("does not treat the needle as a pattern", function()
    assert.is_false(util.contains("abc", "a.c"))
  end)
end)

describe("util.trim", function()
  it("strips surrounding whitespace", function()
    assert.equals("x y", util.trim("  \tx y\n "))
  end)

  it("leaves an empty string empty", function()
    assert.equals("", util.trim("   "))
  end)
end)

describe("util.etime_to_secs", function()
  it("parses mm:ss", function()
    assert.equals(30, util.etime_to_secs("00:30"))
  end)

  it("parses hh:mm:ss", function()
    assert.equals(7200, util.etime_to_secs("02:00:00"))
  end)

  it("parses dd-hh:mm:ss", function()
    assert.equals(86400, util.etime_to_secs("1-00:00:00"))
  end)

  it("treats an empty field as zero", function()
    assert.equals(0, util.etime_to_secs(""))
  end)
end)

describe("util.human_duration", function()
  it("formats seconds", function()
    assert.equals("45s", util.human_duration(45))
  end)

  it("formats whole minutes", function()
    assert.equals("1m", util.human_duration(90))
  end)

  it("formats hours and minutes", function()
    assert.equals("2h 13m", util.human_duration(7980))
  end)

  it("formats days and hours", function()
    assert.equals("5d 5h", util.human_duration(450000))
  end)

  it("renders a dash for nil or negative input", function()
    assert.equals("-", util.human_duration(nil))
    assert.equals("-", util.human_duration(-5))
  end)
end)

describe("util.parse_ps_line", function()
  it("splits pid/etime/args and preserves spaces in args", function()
    local pid, etime, args = util.parse_ps_line("  881    00:30 /bin/zsh -c echo hi there")
    assert.equals(881, pid)
    assert.equals("00:30", etime)
    assert.equals("/bin/zsh -c echo hi there", args)
  end)

  it("returns nil when the first column is not a pid", function()
    assert.is_nil(util.parse_ps_line("   not a line"))
  end)
end)
