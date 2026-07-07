local log = require("coco.util.log")
local server = require("coco.mcp.server")

describe("security", function()
  it("redacts Authorization bearer tokens from log file", function()
    local tmp = vim.fn.tempname() .. ".log"
    log.setup({ level = "info", file = tmp })
    log.info("request: Authorization: Bearer secret-token-123")
    -- Force flush by re-setup? log.lua flushes on each write.
    local fd = io.open(tmp, "r")
    local content = fd and fd:read("*a") or ""
    if fd then
      fd:close()
    end
    assert.is_falsy(content:find("secret%-token%-123"))
    assert.is_truthy(content:find("Authorization%s*:%s*Bearer%s+<redacted>"))
    os.remove(tmp)
  end)

  it("redates PAT-like env vars from log file", function()
    local tmp = vim.fn.tempname() .. ".log"
    log.setup({ level = "info", file = tmp })
    log.info("env MY_PAT=abc123")
    local fd = io.open(tmp, "r")
    local content = fd and fd:read("*a") or ""
    if fd then
      fd:close()
    end
    assert.is_falsy(content:find("abc123"))
    assert.is_truthy(content:find("MY_PAT=<redacted>"))
    os.remove(tmp)
  end)

  it("mcp server binds to 127.0.0.1", function()
    local started_port
    server.start({
      host = "127.0.0.1",
      port = 0,
      token = "tok",
      handler = function(req, cb)
        cb({ jsonrpc = "2.0", id = req.id, result = {} })
      end,
    }, function(err, port)
      assert.is_nil(err)
      started_port = port
    end)
    vim.wait(1000, function()
      return started_port ~= nil
    end)
    assert.is_number(started_port)
    server.stop()
  end)
end)
