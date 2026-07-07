--- coco.nvim health checks.

local config = require("coco.config")
local async = require("coco.util.async")
local state = require("coco.session.state")

local M = {}

local function start()
  vim.health.start("coco.nvim")
end

local function ok(msg)
  vim.health.ok(msg)
end

local function warn(msg)
  vim.health.warn(msg)
end

local function error(msg)
  vim.health.error(msg)
end

function M.check()
  start()

  -- Neovim version
  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim >= 0.10")
  else
    error("Neovim >= 0.10 required")
  end

  -- CLI presence
  local cmd = config.get().cli.cmd
  if vim.fn.executable(cmd) == 1 then
    local version = vim.fn.system(cmd .. " --version"):gsub("%s+$", "")
    ok("`" .. cmd .. "` found: " .. version)
  else
    error("`" .. cmd .. "` not found on PATH. Install the Snowflake Cortex Code CLI.")
  end

  -- Optional deps
  local ok_snacks, _ = pcall(require, "snacks")
  if ok_snacks then
    ok("snacks.nvim detected (optional terminal/input/picker provider)")
  else
    warn("snacks.nvim not installed; native terminal fallback will be used")
  end
  local ok_telescope, _ = pcall(require, "telescope")
  if ok_telescope then
    ok("telescope.nvim detected (optional picker)")
  end
  local ok_fzf, _ = pcall(require, "fzf-lua")
  if ok_fzf then
    ok("fzf-lua detected (optional picker)")
  end

  -- Session state
  local s = state.get()
  if s.phase ~= "inactive" then
    ok("session phase: " .. s.phase)
    if s.transport.terminal then
      ok("terminal transport active")
    end
    if s.transport.mcp and s.mcp_port then
      ok("MCP transport active on 127.0.0.1:" .. s.mcp_port)
      local sock = vim.loop.new_tcp()
      local reachable = false
      sock:connect("127.0.0.1", s.mcp_port, function(err)
        reachable = err == nil
        pcall(sock.close, sock)
      end)
      vim.wait(500, function()
        return reachable
      end, 10)
      if reachable then
        ok("MCP port reachable")
      else
        warn("MCP port not reachable")
      end
    elseif config.get().transport.mcp then
      warn("MCP transport not active")
    end
  else
    warn("no active session")
  end
end

return M
