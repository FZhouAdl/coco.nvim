--- Minimal TOML helpers for config files that coco.nvim reads.

local M = {}

--- Parse a simple key=value line.
---@param line string
---@return string|nil key
---@return string|nil value
local function parse_kv(line)
  return line:match("^%s*([^%s=]+)%s*=%s*[\"']?([^%\"']+)[%\"']?%s*$")
end

--- Read all scalar key/value pairs from a TOML section.
--- Handles both `[section]` and `[connections.section]` header styles.
---@param data string
---@param section string
---@return table<string, string>
function M.section_values(data, section)
  local values = {}
  local in_section = false
  for line in data:gmatch("[^\r\n]+") do
    local sec = line:match("^%s*%[(.-)%]%s*$")
    if sec then
      in_section = sec == section or sec == "connections." .. section
    elseif in_section then
      local k, v = parse_kv(line)
      if k and v then
        values[k] = v
      end
    end
  end
  return values
end

--- Read a single scalar value from a TOML section.
---@param data string
---@param section string
---@param key string
---@return string|nil
function M.section_value(data, section, key)
  local values = M.section_values(data, section)
  return values[key]
end

return M
