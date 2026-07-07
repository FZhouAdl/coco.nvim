--- coco.nvim MCP JSON-RPC request handler (Phase 2).

local jsonrpc = require("coco.mcp.jsonrpc")
local tools = require("coco.mcp.tools")
local state = require("coco.session.state")
local log = require("coco.util.log")

local M = {}

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
    cb(
      jsonrpc.make_response(req.id, {
        protocolVersion = "2024-11-05",
        capabilities = { tools = {}, logging = {} },
        serverInfo = { name = "coco-nvim", version = "0.2.0" },
      })
    )
  elseif method == "notifications/initialized" then
    cb(nil)
  elseif method == "tools/list" then
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
