--- coco.nvim MCP JSON-RPC request handler (Phase 2).

local jsonrpc = require("coco.mcp.jsonrpc")
local tools = require("coco.mcp.tools")
local state = require("coco.session.state")
local log = require("coco.util.log")

local M = {}

-- The MCP spec requires initialize + notifications/initialized before tools
-- may be used. This flag is module-level because the server is localhost-only
-- and handles one client at a time.
local initialized = false

--- Reset initialization state (useful in tests).
function M.reset()
  initialized = false
end

---@param req table
---@param cb fun(resp: table|nil)
function M.handle(req, cb)
  state.dispatch({ type = "counter", name = "mcp_requests_total", delta = 1 })

  if not req.jsonrpc or req.jsonrpc ~= "2.0" then
    cb(jsonrpc.make_error(req.id, jsonrpc.INVALID_REQUEST, "invalid jsonrpc"))
    return
  end

  local method = req.method
  if method == "initialize" then
    initialized = false
    cb(
      jsonrpc.make_response(req.id, {
        protocolVersion = "2024-11-05",
        -- Empty Lua tables encode as JSON arrays; use vim.empty_dict() for
        -- MCP capability objects that must be objects, not arrays.
        capabilities = { tools = vim.empty_dict(), logging = vim.empty_dict() },
        serverInfo = { name = "coco-nvim", version = "0.2.0" },
      })
    )
    return
  end

  if method == "notifications/initialized" then
    initialized = true
    -- Notifications (no id) must not receive a response.
    cb(nil)
    return
  end

  -- Ping is a required base method and needs no initialization.
  if method == "ping" then
    if req.id ~= nil then
      cb(jsonrpc.make_response(req.id, vim.empty_dict()))
    else
      cb(nil)
    end
    return
  end

  -- Reject tool operations until the lifecycle handshake is complete.
  if not initialized and (method == "tools/list" or method == "tools/call") then
    if req.id ~= nil then
      cb(jsonrpc.make_error(req.id, -32002, "server not initialized"))
    else
      cb(nil)
    end
    return
  end

  -- Notifications (no id) other than the lifecycle notification receive no response.
  if req.id == nil then
    cb(nil)
    return
  end

  if method == "tools/list" then
    cb(jsonrpc.make_response(req.id, { tools = tools.list() }))
  elseif method == "tools/call" then
    local call = req.params or {}
    log.debug("mcp handler: tools/call " .. tostring(call.name))
    tools.dispatch(call, function(result)
      cb(jsonrpc.make_response(req.id, result))
    end)
  else
    cb(jsonrpc.make_error(req.id, jsonrpc.METHOD_NOT_FOUND, "method not found: " .. tostring(method)))
  end
end

return M
