--- coco.nvim
--- Public API and lifecycle.

local config = require("coco.config")
local log = require("coco.util.log")

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

--- Setup the plugin.
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  log.setup(config.get().log)
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

return M
