local log = require("coco.util.log")
local server = require("coco.mcp.server")
local register = require("coco.mcp.register")
local tools = require("coco.mcp.tools")
local async = require("coco.util.async")
local rest = require("coco.rest.client")

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

  it("writes mcp.json with 0600 permissions", function()
    local orig_home = vim.env.HOME
    local tmp_home = vim.fn.tempname()
    vim.env.HOME = tmp_home

    -- Bypass the cortex reconnect subprocess.
    local orig_spawn = async.spawn
    async.spawn = function(_, _, cb)
      cb({ code = 0, stdout = "", stderr = "" })
      return { cancel = function() end }
    end

    local ok = false
    register.add("coco-test-server", "http://127.0.0.1:1234/mcp", "secret-token", function(result)
      ok = result
    end)
    vim.wait(1000, function()
      return ok
    end)

    local path = tmp_home .. "/.snowflake/cortex/mcp.json"
    local fd = io.open(path, "r")
    assert.is_not_nil(fd)
    local content = fd:read("*a")
    fd:close()
    assert.is_truthy(content:find("secret%-token"))

    local stat = vim.uv.fs_stat(path)
    assert.is_not_nil(stat)
    -- fs_stat mode includes file-type bits; mask to permission bits only.
    local bit_mod = rawget(_G, "bit") or rawget(_G, "bit32")
    assert.equals(tonumber("600", 8), bit_mod.band(stat.mode, tonumber("777", 8)))

    async.spawn = orig_spawn
    vim.env.HOME = orig_home
  end)

  it("rejects file tool paths outside the workspace", function()
    local tmp_file = vim.fn.tempname() .. "_outside_coco"
    local fd = io.open(tmp_file, "w")
    fd:write("x")
    fd:close()

    local path, err = tools._validate_file_path(tmp_file)
    assert.is_nil(path)
    assert.is_not_nil(err)
    assert.is_truthy(err:find("outside workspace"))
  end)

  it("rejects file tool paths with traversal", function()
    local path, err = tools._validate_file_path("foo/../../outside_workspace.lua")
    assert.is_nil(path)
    assert.is_not_nil(err)
    assert.is_truthy(err == "filePath contains disallowed traversal" or err:find("outside workspace"))
  end)

  it("never passes the bearer token on curl argv", function()
    local orig_home = vim.env.HOME
    local tmp_home = vim.fn.tempname()
    vim.fn.mkdir(tmp_home, "p")
    vim.fn.mkdir(tmp_home .. "/.snowflake", "p")
    vim.env.HOME = tmp_home
    vim.env.SNOWFLAKE_ACCOUNT = "testaccount"

    local fd = io.open(tmp_home .. "/.snowflake/connections.toml", "w")
    fd:write("[default]\naccount = \"testaccount\"\ntoken = \"argv-secret-token\"\n")
    fd:close()

    local captured_cmd
    local orig_system = vim.system
    vim.system = function(cmd, _, cb)
      captured_cmd = cmd
      cb({ code = 0, stdout = "", stderr = "" })
      return { kill = function() end }
    end

    rest.complete({ messages = {} }, function(_, _, err)
      -- ignore
    end)

    assert.is_not_nil(captured_cmd)
    for _, arg in ipairs(captured_cmd) do
      assert.is_falsy(arg:find("argv%-secret%-token"))
      assert.is_falsy(arg:find("Authorization"))
    end

    vim.system = orig_system
    vim.env.HOME = orig_home
    vim.env.SNOWFLAKE_ACCOUNT = nil
  end)
end)
