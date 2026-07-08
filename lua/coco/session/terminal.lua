--- coco.nvim terminal wrapper.

local config = require("coco.config")
local state = require("coco.session.state")
local log = require("coco.util.log")

local M = {}

local function has_snacks()
  local ok, _ = pcall(require, "snacks.terminal")
  return ok
end

local function resolve_provider()
  local cfg = config.get().ui.terminal.provider
  if cfg == "auto" then
    return has_snacks() and "snacks" or "native"
  end
  return cfg
end

---@return number|nil bufnr
local function open_native()
  local position = config.get().ui.terminal.position
  local width = config.get().ui.terminal.width
  local split_cmd
  if position == "left" or position == "right" then
    split_cmd = (position == "left" and "topleft " or "botright ")
      .. "vertical "
      .. math.floor(vim.o.columns * width)
      .. "split"
  else
    split_cmd = (position == "top" and "topleft " or "botright ")
      .. math.floor(vim.o.lines * width)
      .. "split"
  end
  local parts = { config.get().cli.cmd }
  for _, arg in ipairs(config.get().cli.args or {}) do
    table.insert(parts, vim.fn.shellescape(arg))
  end
  local old_timeout = vim.env.COCO_MCP_TOOL_TIMEOUT_MS
  vim.env.COCO_MCP_TOOL_TIMEOUT_MS = tostring(config.get().cli.mcp_tool_timeout_ms)
  vim.cmd(split_cmd .. " | terminal " .. table.concat(parts, " "))
  if old_timeout ~= nil then
    vim.env.COCO_MCP_TOOL_TIMEOUT_MS = old_timeout
  else
    vim.env.COCO_MCP_TOOL_TIMEOUT_MS = nil
  end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buflisted = false
  return bufnr
end

---@return number|nil bufnr
local function open_snacks()
  local ok, Terminal = pcall(require, "snacks.terminal")
  if not ok then
    return open_native()
  end
  local cfg = config.get().ui.terminal
  local position = cfg.position
  if position == "left" or position == "right" or position == "top" or position == "bottom" then
    return open_native()
  end
  local parts = { config.get().cli.cmd }
  for _, arg in ipairs(config.get().cli.args or {}) do
    table.insert(parts, vim.fn.shellescape(arg))
  end
  local t = Terminal.open(table.concat(parts, " "), {
    env = {
      COCO_MCP_TOOL_TIMEOUT_MS = tostring(config.get().cli.mcp_tool_timeout_ms),
    },
    position = position,
  })
  return t and t.buf
end

--- Open the CoCo terminal window.
---@return number|nil bufnr
function M.open()
  local provider = resolve_provider()
  local bufnr
  if provider == "snacks" then
    bufnr = open_snacks()
  else
    bufnr = open_native()
  end
  if bufnr then
    state.dispatch({ type = "set_terminal_bufnr", bufnr = bufnr })
    vim.api.nvim_buf_set_var(bufnr, "coco_terminal", true)
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = bufnr,
      once = true,
      callback = function()
        -- If the manager is already stopping the session, do not dispatch again.
        if state.get().phase == "stopping" then
          return
        end
        log.warn("terminal closed unexpectedly")
        state.dispatch({ type = "stopped" })
      end,
    })
  end
  return bufnr
end

--- Close the CoCo terminal window.
function M.close()
  local bufnr = state.get().terminal_bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
  -- The caller (session manager or TermClose autocmd) is responsible for
  -- dispatching the "stopped" message to avoid double-dispatch.
end

--- Toggle the CoCo terminal window.
function M.toggle()
  local bufnr = state.get().terminal_bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local wins = vim.fn.win_findbuf(bufnr)
    if #wins > 0 then
      for _, w in ipairs(wins) do
        if vim.api.nvim_win_is_valid(w) then
          vim.api.nvim_win_close(w, false)
          return
        end
      end
    else
      -- Re-open the existing terminal buffer in a vertical split rather than
      -- replacing the current buffer.
      vim.cmd("vertical botright split")
      vim.api.nvim_win_set_buf(0, bufnr)
    end
  else
    M.open()
  end
end

--- Focus the CoCo terminal window without entering terminal mode.
function M.focus_window()
  local bufnr = state.get().terminal_bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local wins = vim.fn.win_findbuf(bufnr)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      return
    end
    vim.cmd("vertical botright split")
    vim.api.nvim_win_set_buf(0, bufnr)
    return
  end
  M.open()
end

--- Focus the CoCo terminal window.
function M.focus()
  M.focus_window()
  vim.cmd("startinsert")
end

--- Send text to the running terminal job.
---@param text string|nil
function M.send(text)
  if not text or text == "" then
    return
  end
  local bufnr = state.get().terminal_bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn("no active terminal to send to")
    return
  end
  local channel = vim.bo[bufnr].channel
  if channel and channel ~= 0 then
    -- Use \r (CR) instead of \n (LF) to submit. Terminal programs in raw mode
    -- expect CR for Enter (same as what a real keypress sends to the PTY).
    local payload = text:gsub("\n$", "") .. "\r"
    vim.fn.chansend(channel, payload)
    -- In some Neovim versions/environments, chansend may be buffered or ignored 
    -- if the terminal window is not focused or in terminal mode.
    -- We ensure the window is focused and enters terminal mode immediately.
    M.focus()
  else
    log.warn("terminal job channel not available")
  end
end

return M
