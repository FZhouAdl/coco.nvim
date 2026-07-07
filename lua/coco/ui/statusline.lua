--- coco.nvim statusline component.

local state = require("coco.session.state")
local config = require("coco.config")

local M = {}

--- Return a short statusline string or "" when no session.
---@return string
function M.component()
  local s = state.get()
  if s.phase == "inactive" then
    return ""
  end
  local parts = {}
  if s.connection then
    table.insert(parts, s.connection)
  end
  if s.role then
    table.insert(parts, s.role)
  end
  if s.warehouse then
    table.insert(parts, s.warehouse)
  end
  if s.model then
    table.insert(parts, s.model)
  end
  if config.get().snowflake.show_cost and s.credits then
    table.insert(parts, string.format("~%.1f", s.credits))
  end
  return table.concat(parts, " · ")
end

return M
