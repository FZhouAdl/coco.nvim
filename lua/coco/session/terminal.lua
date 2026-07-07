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
  vim.cmd(split_cmd .. " | terminal " .. config.get().cli.cmd)
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
  local t = Terminal.open({
    cmd = config.get().cli.cmd,
    env = {
      COCO_MCP_TOOL_TIMEOUT_MS = tostring(config.get().cli.mcp_tool_timeout_ms),
    },
    position = cfg.position,
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
  state.dispatch({ type = "stopped" })
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
      vim.api.nvim_set_current_buf(bufnr)
    end
  else
    M.open()
  end
end

--- Focus the CoCo terminal window.
function M.focus()
  local bufnr = state.get().terminal_bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local wins = vim.fn.win_findbuf(bufnr)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      return
    end
  end
  M.open()
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
    vim.fn.chansend(channel, text:gsub("\n$", "") .. "\n")
  else
    log.warn("terminal job channel not available")
  end
end

return M
