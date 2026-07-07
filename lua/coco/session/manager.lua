--- coco.nvim session manager.

local config = require("coco.config")
local state = require("coco.session.state")
local terminal = require("coco.session.terminal")
local async = require("coco.util.async")
local log = require("coco.util.log")

local M = {}

---@type CocoAsyncHandle|nil
local probe_handle

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

    -- MCP steps are stubbed here; Phase 2 wires them in.
    if config.get().transport.mcp then
      state.dispatch({ type = "degraded", reason = "MCP not yet implemented (Phase 2)" })
    else
      state.dispatch({ type = "active" })
    end

    local bufnr = terminal.open()
    if not bufnr then
      state.dispatch({ type = "stopped" })
      log.error("failed to open terminal")
      return
    end
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
  local lines = {
    "coco.nvim session status",
    "  phase:      " .. s.phase,
    "  connection: " .. (s.connection or "<none>"),
    "  role:       " .. (s.role or "<none>"),
    "  warehouse:  " .. (s.warehouse or "<none>"),
    "  model:      " .. (s.model or "<none>"),
    "  transport:",
    "    terminal: " .. (s.transport.terminal and "yes" or "no"),
    "    mcp:      " .. (s.transport.mcp and "yes" or "no"),
    "    rest:     " .. (s.transport.rest and "yes" or "no"),
  }
  if s.mcp_port then
    table.insert(lines, "  mcp port:   " .. s.mcp_port)
  end
  for name, value in pairs(s.counters) do
    table.insert(lines, "  " .. name .. ": " .. value)
  end
  vim.schedule(function()
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end)
end

return M
