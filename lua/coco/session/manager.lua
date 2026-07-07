--- coco.nvim session manager.

local config = require("coco.config")
local state = require("coco.session.state")
local terminal = require("coco.session.terminal")
local async = require("coco.util.async")
local log = require("coco.util.log")
local server = require("coco.mcp.server")
local register = require("coco.mcp.register")
local handler = require("coco.mcp.handler")

local M = {}

---@type CocoAsyncHandle|nil
local probe_handle

--- Generate a random hex token by reading /dev/urandom.
---@param bytes number
---@return string
local function random_token(bytes)
  local fd = io.open("/dev/urandom", "rb")
  if not fd then
    -- Fallback: not cryptographically secure, should rarely happen on POSIX.
    local parts = {}
    for _ = 1, bytes do
      table.insert(parts, string.format("%02x", math.random(0, 255)))
    end
    return table.concat(parts)
  end
  local raw = fd:read(bytes)
  fd:close()
  local parts = {}
  for i = 1, #raw do
    table.insert(parts, string.format("%02x", raw:byte(i)))
  end
  return table.concat(parts)
end

--- Probe for the cortex CLI and start a terminal session.
---@param opts { resume?: boolean }|nil
function M.start(opts)
  opts = opts or {}
  if state.get().phase ~= "inactive" then
    log.warn("session already " .. state.get().phase)
    return
  end
  state.dispatch({ type = "start" })
  log.info("starting CoCo session" .. (opts.resume and " (resume)" or ""))

  async.which(config.get().cli.cmd, function(found, path)
    if not found then
      state.dispatch({ type = "stopped" })
      async.schedule(function()
        vim.notify(
          "[coco] `"
            .. config.get().cli.cmd
            .. "` not found on PATH. Install the Snowflake Cortex Code CLI: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-coder",
          vim.log.levels.ERROR
        )
      end)
      return
    end

    state.dispatch({ type = "cli_ready" })

    local function open_terminal()
      local bufnr = terminal.open()
      if not bufnr then
        state.dispatch({ type = "stopped" })
        log.error("failed to open terminal")
        return
      end
    end

    if not config.get().transport.mcp then
      state.dispatch({ type = "active" })
      open_terminal()
      return
    end

    local token = random_token(config.get().mcp.token_bytes)
    server.start({
      host = config.get().mcp.host,
      port = config.get().mcp.port,
      token = token,
      max_body_bytes = config.get().mcp.max_body_bytes,
      handler = handler.handle,
    }, function(err, port)
      if err or not port then
        log.error("mcp server failed: " .. tostring(err))
        state.dispatch({ type = "degraded", reason = "MCP server failed: " .. tostring(err) })
        open_terminal()
        return
      end

      state.dispatch({ type = "mcp_ready", port = port, token = token })
      local url = "http://127.0.0.1:" .. port .. "/mcp"

      register.add(config.get().mcp.server_name, url, token, function(ok, reg_err)
        if not ok then
          log.error("mcp registration failed: " .. tostring(reg_err))
          state.dispatch({ type = "degraded", reason = "mcp registration failed: " .. tostring(reg_err) })
        else
          state.dispatch({ type = "active" })
        end
        open_terminal()
      end)
    end)
  end)
end

--- Stop the active session.
function M.stop()
  if state.get().phase == "inactive" then
    log.warn("no active session to stop")
    return
  end
  state.dispatch({ type = "stop" })
  terminal.close()
  register.remove(config.get().mcp.server_name, function(_)
    server.stop()
  end)
  if probe_handle then
    probe_handle.cancel()
    probe_handle = nil
  end
  state.dispatch({ type = "stopped" })
  log.info("CoCo session stopped")
end

--- Send text to the terminal.
---@param text string|nil
function M.send(text)
  if not text or text == "" then
    return
  end
  terminal.send(text)
end

--- Print session status.
function M.status()
  local s = state.get()
  local function mark(on)
    return on and "✅" or "❌"
  end
  local lines = {
    "coco.nvim session status",
    "  phase:      " .. s.phase,
    "  connection: " .. (s.connection or "<none>"),
    "  role:       " .. (s.role or "<none>"),
    "  warehouse:  " .. (s.warehouse or "<none>"),
    "  model:      " .. (s.model or "<none>"),
    "  transport:  " .. mark(s.transport.terminal) .. " " .. mark(s.transport.mcp) .. " " .. mark(s.transport.rest),
  }
  if s.mcp_port then
    table.insert(lines, "  mcp port:   " .. s.mcp_port)
  end
  local pending = {}
  for id, info in pairs(s.pending_tools) do
    table.insert(pending, string.format("%s (%ds)", info.tool, os.time() - info.started))
  end
  if #pending > 0 then
    table.insert(lines, "  in-flight:  " .. table.concat(pending, ", "))
  end
  for name, value in pairs(s.counters) do
    table.insert(lines, "  " .. name .. ": " .. value)
  end
  vim.schedule(function()
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end)
end

return M
