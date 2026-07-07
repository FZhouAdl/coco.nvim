--- coco.nvim
--- Public API and lifecycle.

local config = require("coco.config")
local log = require("coco.util.log")
local state = require("coco.session.state")

local M = {}

---@class CocoApi
---@field setup fun(opts?: table)
---@field start fun(opts?: { resume?: boolean })
---@field stop fun()
---@field toggle fun()
---@field focus fun()
---@field ask fun(prompt?: string)
---@field send fun(text?: string)
---@field add fun(path?: string, l1?: number, l2?: number)
---@field status fun()
---@field connection fun()
---@field select_model fun()
---@field mode fun(name: string)
---@field complete fun()

--- Setup the plugin.
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  log.setup(config.get().log)
  state.dispatch({ type = "set_mode", mode = config.get().permissions.mode })
  log.info("coco.nvim setup complete")
  require("coco.plugin.commands").register()
end

--- Start a CoCo session.
---@param opts { resume?: boolean }|nil
function M.start(opts)
  opts = opts or {}
  local manager = require("coco.session.manager")
  manager.start(opts)
end

--- Stop the active session.
function M.stop()
  local manager = require("coco.session.manager")
  manager.stop()
end

--- Toggle the CoCo terminal window.
function M.toggle()
  local terminal = require("coco.session.terminal")
  terminal.toggle()
end

--- Focus the CoCo terminal window.
function M.focus()
  local terminal = require("coco.session.terminal")
  terminal.focus()
end

--- Ask CoCo with an expanded prompt.
---@param prompt string|nil
function M.ask(prompt)
  local input = require("coco.ui.input")
  input.ask(prompt)
end

--- Send raw text to the running CoCo session.
---@param text string|nil
function M.send(text)
  local manager = require("coco.session.manager")
  manager.send(text)
end

--- Add a file or range to the context queue.
---@param path string|nil
---@param l1 number|nil
---@param l2 number|nil
function M.add(path, l1, l2)
  local context = require("coco.context.editor")
  context.add_to_context(path, l1, l2)
end

--- Print a session status summary.
function M.status()
  local manager = require("coco.session.manager")
  manager.status()
end

--- Open the connection picker.
function M.connection()
  local snowflake_conn = require("coco.snowflake.connection")
  local picker = require("coco.ui.select")
  snowflake_conn.list(function(err, items)
    if err then
      vim.notify("[coco] " .. err, vim.log.levels.ERROR)
      return
    end
    picker.pick(items, {
      prompt = "CoCo connection: ",
      format = function(item)
        return (item.active and "* " or "  ") .. item.name
          .. (item.role and " (" .. item.role .. ")" or "")
          .. (item.warehouse and " [" .. item.warehouse .. "]" or "")
      end,
    }, function(item)
      if not item then
        return
      end
      snowflake_conn.set(item.name, function(set_err)
        if set_err then
          vim.notify("[coco] " .. set_err, vim.log.levels.ERROR)
          return
        end
        require("coco.context.snowflake").clear()
        vim.notify("[coco] connection set to " .. item.name, vim.log.levels.INFO)
      end)
    end)
  end)
end

--- Open the model picker.
function M.select_model()
  local picker = require("coco.ui.select")
  picker.models(function(err, models)
    if err then
      vim.notify("[coco] " .. err, vim.log.levels.ERROR)
      return
    end
    picker.pick(models, {
      prompt = "CoCo model: ",
      format = function(item)
        return item.name .. (item.provider and " (" .. item.provider .. ")" or "")
      end,
    }, function(item)
      if not item then
        return
      end
      state.dispatch({ type = "set_model", model = item.name })
      M.send("/model " .. item.name)
      vim.notify("[coco] model set to " .. item.name, vim.log.levels.INFO)
    end)
  end)
end

--- Cycle or set the permission mode overlay.
---@param name string|nil
function M.mode(name)
  local valid = { confirm = true, plan = true, bypass = true }
  if name and not valid[name] then
    vim.notify("[coco] mode must be confirm|plan|bypass", vim.log.levels.WARN)
    return
  end
  if not name then
    local order = { "confirm", "plan", "bypass" }
    local current = state.get().mode or "confirm"
    local idx = 1
    for i, m in ipairs(order) do
      if m == current then
        idx = i % #order + 1
        break
      end
    end
    name = order[idx]
  end
  state.dispatch({ type = "set_mode", mode = name })
  local slash = "/" .. name
  M.send(slash)
  vim.notify("[coco] mode set to " .. name, vim.log.levels.INFO)
end

--- Trigger ghost-text completion at the cursor.
function M.complete()
  require("coco.ui.input").complete()
end

return M
