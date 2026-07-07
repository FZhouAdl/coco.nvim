--- coco.nvim JSON-RPC 2.0 framing (Phase 2).

local M = {}

---@param msg table
---@return string
function M.write_frame(msg)
  local ok, json = pcall(vim.json.encode, msg)
  if not ok then
    return ""
  end
  return json
end

---@param str string
---@return table|nil
function M.parse(str)
  local ok, obj = pcall(vim.json.decode, str, { object = true, array = true })
  if not ok then
    return nil
  end
  return obj
end

---@param id any
---@param result any
---@return table
function M.make_response(id, result)
  return { jsonrpc = "2.0", id = id, result = result }
end

---@param id any
---@param code number
---@param message string
---@return table
function M.make_error(id, code, message)
  return { jsonrpc = "2.0", id = id, error = { code = code, message = message } }
end

return M
