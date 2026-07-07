--- coco.nvim SSE parser (Phase 4).

local M = {}

---@class CocoSseEvent
---@field event string
---@field data string
---@field id string|nil

---@class CocoSseParser
local Parser = {}
Parser.__index = Parser

function M.new()
  return setmetatable({ buffer = "", last_id = nil }, Parser)
end

---@param chunk string
---@return CocoSseEvent[] events
function Parser:feed(chunk)
  self.buffer = self.buffer .. chunk
  local events = {}
  while true do
    local eol_pos = self.buffer:find("\n", 1, true)
    if not eol_pos then
      break
    end
    local line = self.buffer:sub(1, eol_pos - 1)
    self.buffer = self.buffer:sub(eol_pos + 1)
    -- Strip trailing \r from \r\n.
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    if line == "" then
      -- Dispatch current event if any data accumulated.
      if self._event_data ~= nil or self._event_name ~= nil or self._event_id ~= nil then
        table.insert(events, {
          event = self._event_name or "message",
          data = self._event_data or "",
          id = self._event_id,
        })
        if self._event_id then
          self.last_id = self._event_id
        end
        self._event_data = nil
        self._event_name = nil
        self._event_id = nil
      end
    else
      local field, value = line:match("^([^:]*):%s?(.*)$")
      if field then
        if field == "data" then
          if self._event_data then
            self._event_data = self._event_data .. "\n" .. value
          else
            self._event_data = value
          end
        elseif field == "event" then
          self._event_name = value
        elseif field == "id" then
          self._event_id = value
        elseif field == "retry" then
          local n = tonumber(value)
          if n then
            self.retry = n
          end
        end
      end
    end
  end
  return events
end

---@return string|nil
function Parser:last_event_id()
  return self.last_id
end

return M
