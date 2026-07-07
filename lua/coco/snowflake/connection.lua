--- coco.nvim Snowflake connection manager (Phase 3).

local M = {}

---@param cb fun(err: string|nil, connections: table[])
function M.list(cb)
  -- TODO: implement in Phase 3.
  cb("not implemented", {})
end

---@param name string
---@param cb fun(err: string|nil)
function M.set(name, cb)
  -- TODO: implement in Phase 3.
  cb("not implemented")
end

return M
