--- coco.nvim JSON helpers.

local M = {}

--- Encode a Lua value to JSON.
---@param obj any
---@param opts table|nil
---@return string|nil json
---@return string|nil err
function M.encode(obj, opts)
  local ok, res = pcall(vim.json.encode, obj, opts or {})
  if not ok then
    return nil, tostring(res)
  end
  return res, nil
end

--- Decode JSON to a Lua value.
---@param str string
---@return boolean ok
---@return any value
function M.decode(str)
  local ok, res = pcall(vim.json.decode, str, { object = true, array = true })
  return ok, res
end

return M
