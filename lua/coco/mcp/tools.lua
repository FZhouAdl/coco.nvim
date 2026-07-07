--- coco.nvim MCP tool registry (Phase 2).

local M = {}

---@param name string
---@param schema table
---@param handler fun(args: table, cb: fun(result: table))
function M.register(name, schema, handler)
  -- TODO: implement in Phase 2.
end

---@param call { name: string, arguments: table }
---@param cb fun(result: table)
function M.dispatch(call, cb)
  -- TODO: implement in Phase 2.
  cb({ isError = true, content = { { type = "text", text = "not implemented" } } })
end

return M
