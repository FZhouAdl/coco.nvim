--- coco.nvim SSE parser (Phase 4).

local M = {}

---@class CocoSseParser
local Parser = {}
Parser.__index = Parser

function M.new()
  return setmetatable({ buffer = "" }, Parser)
end

---@param chunk string
---@return table[] events
function Parser:feed(chunk)
  -- TODO: implement in Phase 4.
  return {}
end

return M
