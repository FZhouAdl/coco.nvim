--- coco.nvim MCP registration lifecycle (Phase 2).

local M = {}

---@param server_name string
---@param url string
---@param token string
---@param cb fun(ok: boolean, err: string|nil)
function M.add(server_name, url, token, cb)
  -- TODO: implement in Phase 2.
  cb(false, "not implemented")
end

---@param server_name string
---@param cb fun(ok: boolean)
function M.remove(server_name, cb)
  -- TODO: implement in Phase 2.
  cb(false)
end

return M
