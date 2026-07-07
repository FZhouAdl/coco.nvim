--- coco.nvim TEA-style session state.

local log = require("coco.util.log")

local M = {}

---@alias CocoPhase "inactive"|"starting"|"degraded"|"active"|"stopping"

---@class CocoSessionState
---@field phase CocoPhase
---@field transport { terminal: boolean, mcp: boolean, rest: boolean }
---@field connection string|nil
---@field role string|nil
---@field warehouse string|nil
---@field model string|nil
---@field credits number|nil
---@field mode "confirm"|"plan"|"bypass"|nil
---@field terminal_bufnr number|nil
---@field mcp_port number|nil
---@field mcp_token string|nil
---@field pending_tools table<string, { started: number, tool: string }>
---@field diffs table<string, { status: "pending"|"FILE_SAVED"|"DIFF_REJECTED", opened: number }>
---@field counters table<string, number>

---@type CocoSessionState
local state = {
  phase = "inactive",
  transport = { terminal = false, mcp = false, rest = false },
  connection = nil,
  role = nil,
  warehouse = nil,
  model = nil,
  credits = nil,
  mode = nil,
  terminal_bufnr = nil,
  mcp_port = nil,
  mcp_token = nil,
  pending_tools = {},
  diffs = {},
  counters = {
    mcp_requests_total = 0,
    mcp_auth_failures_total = 0,
    tool_calls_total = 0,
    tool_errors_total = 0,
    diff_accepted_total = 0,
    diff_rejected_total = 0,
    sse_reconnects_total = 0,
    cli_spawn_failures_total = 0,
  },
}

local subscribers = {}

---@param s CocoSessionState
---@param msg table
local function update(s, msg)
  if msg.type == "start" then
    if s.phase ~= "inactive" then
      log.warn("state: start requested from " .. s.phase)
      return
    end
    s.phase = "starting"
    s.transport = { terminal = false, mcp = false, rest = false }
  elseif msg.type == "cli_ready" then
    if s.phase == "starting" then
      s.transport.terminal = true
    end
  elseif msg.type == "mcp_ready" then
    if s.phase == "starting" then
      s.transport.mcp = true
      s.mcp_port = msg.port
      s.mcp_token = msg.token
    end
  elseif msg.type == "rest_ready" then
    s.transport.rest = true
  elseif msg.type == "active" then
    s.phase = "active"
  elseif msg.type == "degraded" then
    s.phase = "degraded"
    s.transport.terminal = true
    if msg.reason then
      log.warn("state: degraded — " .. msg.reason)
    end
  elseif msg.type == "stop" then
    if s.phase == "inactive" or s.phase == "stopping" then
      return
    end
    s.phase = "stopping"
  elseif msg.type == "stopped" then
    s.phase = "inactive"
    s.transport = { terminal = false, mcp = false, rest = false }
    s.terminal_bufnr = nil
    s.mcp_port = nil
    s.mcp_token = nil
    s.pending_tools = {}
    s.diffs = {}
    s.credits = nil
  elseif msg.type == "set_terminal_bufnr" then
    s.terminal_bufnr = msg.bufnr
  elseif msg.type == "set_connection" then
    s.connection = msg.connection
    s.role = msg.role
    s.warehouse = msg.warehouse
  elseif msg.type == "set_model" then
    s.model = msg.model
  elseif msg.type == "set_credits" then
    s.credits = msg.credits
  elseif msg.type == "set_mode" then
    s.mode = msg.mode
  elseif msg.type == "counter" then
    s.counters[msg.name] = (s.counters[msg.name] or 0) + (msg.delta or 1)
  elseif msg.type == "tool_start" then
    s.pending_tools[msg.id] = { tool = msg.tool, started = msg.started or os.time() }
  elseif msg.type == "tool_done" then
    s.pending_tools[msg.id] = nil
  elseif msg.type == "diff_open" then
    s.diffs[msg.id] = { status = "pending", opened = os.time() }
  elseif msg.type == "diff_resolve" then
    if s.diffs[msg.id] then
      s.diffs[msg.id].status = msg.status
    end
  end
end

--- Dispatch a message to the state store.
---@param msg table
function M.dispatch(msg)
  update(state, msg)
  for _, cb in ipairs(subscribers) do
    local ok, err = pcall(cb, state, msg)
    if not ok then
      log.error("state subscriber error: " .. tostring(err))
    end
  end
end

---@return CocoSessionState
function M.get() return state end

--- Subscribe to state changes.
---@param cb fun(state: CocoSessionState, msg: table)
function M.subscribe(cb)
  table.insert(subscribers, cb)
end

--- Reset state to inactive (useful in tests).
function M.reset()
  for k, v in pairs(state.counters) do
    state.counters[k] = 0
  end
  M.dispatch({ type = "stopped" })
end

return M
