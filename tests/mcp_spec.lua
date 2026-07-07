local jsonrpc = require("coco.mcp.jsonrpc")
local server = require("coco.mcp.server")
local handler = require("coco.mcp.handler")
local tools = require("coco.mcp.tools")
local state = require("coco.session.state")
local async = require("coco.util.async")

describe("jsonrpc", function()
  it("writes a frame with Content-Length", function()
    local frame = jsonrpc.write_frame({ jsonrpc = "2.0", id = 1, result = {} })
    assert.is_truthy(frame:find("Content%-Length:"))
    assert.is_truthy(frame:find("\r\n\r\n"))
  end)

  it("reads a round-tripped frame", function()
    local msg = { jsonrpc = "2.0", id = 5, result = { ok = true } }
    local frame = jsonrpc.write_frame(msg)
    local parsed, tail, err = jsonrpc.read_frame(frame)
    assert.is_nil(err)
    assert.is_nil(tail)
    assert.equals(5, parsed.id)
    assert.equals(true, parsed.result.ok)
  end)

  it("returns nil with tail when buffer is incomplete", function()
    local frame = jsonrpc.write_frame({ jsonrpc = "2.0", id = 1, result = {} })
    local parsed, tail, err = jsonrpc.read_frame(frame:sub(1, 10))
    assert.is_nil(parsed)
    assert.is_nil(err)
    assert.equals(10, #tail)
  end)

  it("returns parse error for malformed JSON", function()
    local frame = "Content-Length: 5\r\n\r\nhello"
    local parsed, tail, err = jsonrpc.read_frame(frame)
    assert.is_nil(parsed)
    assert.equals("parse error", err)
    assert.equals("", tail)
  end)

  it("parses lowercase content-length header", function()
    local body = "{\"jsonrpc\":\"2.0\"}"
    local frame = "content-length: " .. tostring(#body) .. "\r\n\r\n" .. body
    local parsed, tail, err = jsonrpc.read_frame(frame)
    assert.is_nil(err)
    assert.is_nil(tail)
    assert.equals("2.0", parsed.jsonrpc)
  end)
end)

describe("mcp server", function()
  local token = "test-token-1234"
  local captured = {}

  before_each(function()
    server.stop()
    captured = {}
  end)

  after_each(function()
    server.stop()
  end)

  local function test_handler(req, cb)
    table.insert(captured, req)
    cb({ jsonrpc = "2.0", id = req.id, result = { echo = req.method } })
  end

  local resp_file = vim.fn.tempname() .. "_coco_test_resp"

  local function http_post(port, path, body, auth)
    local done = false
    local code, resp = "", ""
    local cmd = {
      "curl",
      "-s",
      "-o",
      resp_file,
      "-w",
      "%{http_code}",
      "-X",
      "POST",
      "http://127.0.0.1:" .. port .. path,
      "-H",
      "Content-Type: application/json",
    }
    if auth then
      table.insert(cmd, "-H")
      table.insert(cmd, "Authorization: Bearer " .. auth)
    end
    table.insert(cmd, "-d")
    table.insert(cmd, body)
    async.spawn(cmd, { timeout = 3000 }, function(obj)
      code = obj.code == 0 and vim.trim(obj.stdout) or ""
      local fd = io.open(resp_file, "r")
      resp = fd and fd:read("*a") or ""
      if fd then
        fd:close()
      end
      done = true
    end)
    vim.wait(4000, function()
      return done
    end)
    return code, resp
  end

  it("starts on a random port and responds to valid request", function()
    local started_port
    server.start({
      host = "127.0.0.1",
      port = 0,
      token = token,
      handler = test_handler,
    }, function(err, port)
      assert.is_nil(err)
      assert.is_number(port)
      started_port = port
    end)
    vim.wait(1000, function()
      return started_port ~= nil
    end)
    assert.is_number(started_port)

    local body = vim.json.encode({ jsonrpc = "2.0", id = 1, method = "ping" })
    local code, resp = http_post(started_port, "/mcp", body, token)
    assert.equals("200", code)
    assert.is_truthy(resp:find("ping"))
  end)

  it("returns 401 for bad token", function()
    local started_port
    server.start({
      host = "127.0.0.1",
      port = 0,
      token = token,
      handler = test_handler,
    }, function(err, port)
      assert.is_nil(err)
      assert.is_number(port)
      started_port = port
    end)
    vim.wait(1000, function()
      return started_port ~= nil
    end)

    local body = vim.json.encode({ jsonrpc = "2.0", id = 1, method = "ping" })
    local code, resp = http_post(started_port, "/mcp", body, "wrong-token")
    assert.equals("401", code)
    assert.equals("", resp)
  end)

  it("returns 404 for wrong route", function()
    local started_port
    server.start({
      host = "127.0.0.1",
      port = 0,
      token = token,
      handler = test_handler,
    }, function(err, port)
      assert.is_nil(err)
      assert.is_number(port)
      started_port = port
    end)
    vim.wait(1000, function()
      return started_port ~= nil
    end)

    local body = vim.json.encode({ jsonrpc = "2.0", id = 1, method = "ping" })
    local code, _ = http_post(started_port, "/wrong", body, token)
    assert.equals("404", code)
  end)

  it("responds with raw JSON (no inner Content-Length framing)", function()
    local started_port
    handler.reset()
    server.start({
      host = "127.0.0.1",
      port = 0,
      token = token,
      handler = handler.handle,
    }, function(err, port)
      assert.is_nil(err)
      started_port = port
    end)
    vim.wait(1000, function()
      return started_port ~= nil
    end)

    local init = vim.json.encode({ jsonrpc = "2.0", id = 1, method = "initialize" })
    local code, resp = http_post(started_port, "/mcp", init, token)
    assert.equals("200", code)
    assert.is_falsy(resp:find("Content%-Length"))
    local parsed = vim.json.decode(resp)
    assert.equals("coco-nvim", parsed.result.serverInfo.name)
  end)

  it("rejects tools/list before lifecycle handshake", function()
    local started_port
    handler.reset()
    server.start({
      host = "127.0.0.1",
      port = 0,
      token = token,
      handler = handler.handle,
    }, function(err, port)
      assert.is_nil(err)
      started_port = port
    end)
    vim.wait(1000, function()
      return started_port ~= nil
    end)

    local body = vim.json.encode({ jsonrpc = "2.0", id = 2, method = "tools/list" })
    local code, resp = http_post(started_port, "/mcp", body, token)
    assert.equals("200", code)
    local parsed = vim.json.decode(resp)
    assert.equals(-32002, parsed.error.code)
  end)

  it("allows tools/list after initialize + notifications/initialized", function()
    local started_port
    handler.reset()
    server.start({
      host = "127.0.0.1",
      port = 0,
      token = token,
      handler = handler.handle,
    }, function(err, port)
      assert.is_nil(err)
      started_port = port
    end)
    vim.wait(1000, function()
      return started_port ~= nil
    end)

    local init = vim.json.encode({ jsonrpc = "2.0", id = 1, method = "initialize" })
    http_post(started_port, "/mcp", init, token)

    local notify = vim.json.encode({ jsonrpc = "2.0", method = "notifications/initialized" })
    local code2, resp2 = http_post(started_port, "/mcp", notify, token)
    assert.equals("200", code2)
    assert.equals("", resp2)

    local body = vim.json.encode({ jsonrpc = "2.0", id = 3, method = "tools/list" })
    local code, resp = http_post(started_port, "/mcp", body, token)
    assert.equals("200", code)
    local parsed = vim.json.decode(resp)
    assert.is_nil(parsed.error)
    assert.is_truthy(#parsed.result.tools > 0)
  end)

  it("returns empty body for notifications", function()
    local started_port
    handler.reset()
    server.start({
      host = "127.0.0.1",
      port = 0,
      token = token,
      handler = handler.handle,
    }, function(err, port)
      assert.is_nil(err)
      started_port = port
    end)
    vim.wait(1000, function()
      return started_port ~= nil
    end)

    local notify = vim.json.encode({ jsonrpc = "2.0", method = "notifications/initialized" })
    local code, resp = http_post(started_port, "/mcp", notify, token)
    assert.equals("200", code)
    assert.equals("", resp)
  end)

  it("compares tokens in constant time", function()
    assert.is_true(server._secure_eq("same", "same"))
    assert.is_false(server._secure_eq("same", "different"))
    assert.is_false(server._secure_eq("short", "longerstring"))
    assert.is_false(server._secure_eq("", ""))
    assert.is_false(server._secure_eq("a", ""))
  end)
end)

describe("tool registry", function()
  before_each(function()
    tools.reset()
    state.reset()
  end)

  it("rejects unknown fields", function()
    tools.register("echo", {
      type = "object",
      properties = { msg = { type = "string" } },
      additionalProperties = false,
    }, function(args, cb)
      cb({ content = { { type = "text", text = args.msg } } })
    end)

    local result
    tools.dispatch({ name = "echo", arguments = { msg = "hi", extra = 1 } }, function(r)
      result = r
    end)
    assert.is_not_nil(result)
    assert.equals(true, result.isError)
    local parsed = vim.json.decode(result.content[1].text)
    assert.equals("SCHEMA_VIOLATION", parsed.code)
  end)

  it("rejects missing required field", function()
    tools.register("openFile", {
      type = "object",
      properties = { filePath = { type = "string" } },
      required = { "filePath" },
      additionalProperties = false,
    }, function(_, cb)
      cb({ content = {} })
    end)

    local result
    tools.dispatch({ name = "openFile", arguments = {} }, function(r)
      result = r
    end)
    assert.is_not_nil(result)
    assert.equals(true, result.isError)
  end)

  it("dispatches a valid call", function()
    tools.register("echo", {
      type = "object",
      properties = { msg = { type = "string" } },
      additionalProperties = false,
    }, function(args, cb)
      cb({ content = { { type = "text", text = args.msg } } })
    end)

    local result
    tools.dispatch({ name = "echo", arguments = { msg = "hello" } }, function(r)
      result = r
    end)
    assert.is_not_nil(result)
    assert.is_nil(result.isError)
    assert.equals("hello", result.content[1].text)
  end)

  it("ignores double callbacks from a tool handler", function()
    tools.register("double", {
      type = "object",
      properties = {},
      additionalProperties = false,
    }, function(_, cb)
      cb({ content = { { type = "text", text = "first" } } })
      cb({ content = { { type = "text", text = "second" } } })
    end)

    local count = 0
    local result
    tools.dispatch({ name = "double", arguments = {} }, function(r)
      count = count + 1
      result = r
    end)
    assert.equals(1, count)
    assert.equals("first", result.content[1].text)
  end)
end)
