--- coco.nvim HTTP MCP server (Phase 2).

local jsonrpc = require("coco.mcp.jsonrpc")
local log = require("coco.util.log")
local state = require("coco.session.state")
local async = require("coco.util.async")

local M = {}

local server ---@type table|nil
local clients = {}
local client_count = 0
local handler_fn ---@type fun(req: table): table|nil
local token_secret ---@type string|nil
local max_body ---@type number
local max_conns ---@type number
local idle_ms ---@type number
local trace_counter = 0
local auth_failures = {} ---@type number[]

local bit_mod = rawget(_G, "bit") or rawget(_G, "bit32")

--- Secure constant-time string compare.
---@param a string
---@param b string
---@return boolean
local function secure_eq(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b or #a == 0 then
    return false
  end
  local diff = 0
  for i = 1, #a do
    diff = bit_mod.bor(diff, bit_mod.bxor(a:byte(i), b:byte(i)))
  end
  return diff == 0
end

--- Generate a short trace id.
---@return string
local function next_trace()
  trace_counter = trace_counter + 1
  return string.format("%x", trace_counter)
end

--- Format a minimal HTTP response.
---@param status string
---@param body string
---@param extra_headers table|nil
---@return string
local function http_response(status, body, extra_headers)
  local headers = {
    "HTTP/1.1 " .. status,
    "Content-Length: " .. tostring(#body),
    "Connection: close",
  }
  if extra_headers then
    for k, v in pairs(extra_headers) do
      table.insert(headers, k .. ": " .. v)
    end
  end
  if body ~= "" then
    table.insert(headers, "Content-Type: application/json")
  end
  return table.concat(headers, "\r\n") .. "\r\n\r\n" .. body
end

--- Parse the first HTTP request from a buffer.
--- Returns method, path, headers, body, consumed, err.
---@param buf string
---@return string|nil method
---@return string|nil path
---@return table|nil headers
---@return string|nil body
---@return number consumed
---@return string|nil err
local function parse_request(buf)
  local header_end = buf:find("\r\n\r\n", 1, true)
  if not header_end then
    return nil, nil, nil, nil, 0, nil
  end
  local head = buf:sub(1, header_end - 1)
  local lines = vim.split(head, "\r\n", { plain = true })
  local request_line = table.remove(lines, 1)
  if not request_line then
    return nil, nil, nil, nil, 0, "bad request line"
  end
  local method, path = request_line:match("^(%S+)%s+(%S+)%s+HTTP/1%.[01]$")
  if not method then
    return nil, nil, nil, nil, 0, "bad request line"
  end
  local headers = {}
  for _, line in ipairs(lines) do
    local k, v = line:match("^([^:]+):%s*(.*)$")
    if k then
      headers[k:lower()] = v
    end
  end
  local content_length = tonumber(headers["content-length"]) or 0
  local body_start = header_end + 4
  local body_end = body_start + content_length - 1
  if #buf < body_end then
    return nil, nil, nil, nil, 0, nil
  end
  local body = buf:sub(body_start, body_end)
  return method, path, headers, body, body_end, nil
end

--- Handle a single client connection.
---@param client table
local function handle_client(client)
  local buf = ""
  local idle_timer = vim.loop.new_timer()
  local closed = false

  local function close()
    if closed then
      return
    end
    closed = true
    if clients[client] then
      clients[client] = nil
      client_count = client_count - 1
    end
    if idle_timer then
      idle_timer:stop()
      idle_timer:close()
    end
    pcall(client.close, client)
  end

  local function reset_idle()
    if idle_timer then
      idle_timer:stop()
      idle_timer:start(
        idle_ms,
        0,
        vim.schedule_wrap(function()
          if not closed then
            log.debug("mcp server: idle timeout")
            close()
          end
        end)
      )
    end
  end

  clients[client] = true
  client_count = client_count + 1
  reset_idle()

  client:read_start(vim.schedule_wrap(function(err, chunk)
    if err then
      close()
      return
    end
    if not chunk then
      close()
      return
    end
    if closed then
      return
    end
    buf = buf .. chunk
    if #buf > max_body + 8192 then
      client:write(http_response("413 Payload Too Large", ""), function()
        close()
      end)
      return
    end
    local method, path, headers, body, consumed, parse_err = parse_request(buf)
    if parse_err then
      client:write(http_response("400 Bad Request", ""), function()
        close()
      end)
      return
    end
    if not method then
      return
    end
    if idle_timer then
      idle_timer:stop()
    end

    local trace = next_trace()
    log.debug("mcp server: request " .. trace .. " " .. method .. " " .. path)

    -- Authorization
    local auth = headers["authorization"] or ""
    local provided = auth:match("^Bearer%s+(%S+)$") or ""
    if not secure_eq(provided, token_secret or "") then
      log.debug("mcp server: auth failure " .. trace)
      state.dispatch({ type = "counter", name = "mcp_auth_failures_total", delta = 1 })
      local now = os.time()
      table.insert(auth_failures, now)
      while #auth_failures > 0 and now - auth_failures[1] > 10 do
        table.remove(auth_failures, 1)
      end
      if #auth_failures >= 5 then
        async.schedule(function()
          vim.notify("[coco] repeated MCP auth failures detected", vim.log.levels.WARN)
        end)
        auth_failures = {}
      end
      client:write(http_response("401 Unauthorized", "", { ["WWW-Authenticate"] = "Bearer" }), function()
        close()
      end)
      return
    end

    -- Route
    if method ~= "POST" or path ~= "/mcp" then
      client:write(http_response("404 Not Found", ""), function()
        close()
      end)
      return
    end

    -- Dispatch
    local req = jsonrpc.parse(body)
    if not req then
      local resp_body = jsonrpc.write_frame(
        jsonrpc.make_error(nil, jsonrpc.PARSE_ERROR, "parse error")
      )
      client:write(
        http_response("200 OK", resp_body, { ["X-Coco-Trace"] = trace }),
        function()
          close()
        end
      )
      return
    end

    local function send_response(resp)
      if resp == nil then
        resp = jsonrpc.make_error(req.id, jsonrpc.METHOD_NOT_FOUND, "method not found")
      end
      local resp_body = jsonrpc.write_frame(resp)
      client:write(
        http_response("200 OK", resp_body, { ["X-Coco-Trace"] = trace }),
        function()
          close()
        end
      )
    end

    local hok, herr = pcall(handler_fn, req, send_response)
    if not hok then
      log.error("mcp server: handler error " .. trace .. ": " .. tostring(herr))
      send_response(jsonrpc.make_error(req.id, jsonrpc.INTERNAL_ERROR, "internal error"))
    end
  end))
end

---@class CocoMcpServerOpts
---@field host string
---@field port number
---@field token string
---@field max_body_bytes number|nil
---@field max_concurrent number|nil
---@field idle_timeout_ms number|nil
---@field handler fun(req: table, cb: fun(resp: table|nil))

--- Start the MCP HTTP server.
---@param opts CocoMcpServerOpts
---@param cb fun(err: string|nil, port: number|nil)
function M.start(opts, cb)
  if server then
    cb("already running", nil)
    return
  end

  handler_fn = opts.handler
  token_secret = opts.token
  max_body = opts.max_body_bytes or 262144
  max_conns = opts.max_concurrent or 32
  idle_ms = opts.idle_timeout_ms or 5000

  local host = opts.host or "127.0.0.1"
  if host ~= "127.0.0.1" and host ~= "localhost" and host ~= "::1" then
    cb("mcp server must bind to a loopback address", nil)
    return
  end

  local s = vim.loop.new_tcp()
  local ok, bound_port_or_err = pcall(function()
    local bind_ok, bind_err = s:bind(host, opts.port)
    if not bind_ok then
      error(bind_err)
    end
    local listen_ok, listen_err = s:listen(128, vim.schedule_wrap(function(err2)
      if err2 then
        log.error("mcp server accept error: " .. tostring(err2))
        return
      end
      if client_count >= max_conns then
        local c = vim.loop.new_tcp()
        local accept_ok = s:accept(c)
        if accept_ok then
          c:write(http_response("503 Service Unavailable", ""), function()
            pcall(c.close, c)
          end)
        end
        return
      end
      local client = vim.loop.new_tcp()
      local accept_ok = s:accept(client)
      if accept_ok then
        clients[client] = true
        handle_client(client)
      end
    end))
    if not listen_ok then
      error(listen_err)
    end
    local name = s:getsockname()
    return name and name.port or opts.port
  end)

  if not ok then
    pcall(s.close, s)
    cb(tostring(bound_port_or_err), nil)
    return
  end

  server = s
  log.info("mcp server listening on " .. opts.host .. ":" .. bound_port_or_err)
  cb(nil, bound_port_or_err)
end

--- Stop the MCP HTTP server.
function M.stop()
  for client, _ in pairs(clients) do
    pcall(client.close, client)
  end
  clients = {}
  client_count = 0
  if server then
    pcall(server.close, server)
    server = nil
  end
  log.info("mcp server stopped")
end

---@return boolean
function M.is_running()
  return server ~= nil
end

return M
