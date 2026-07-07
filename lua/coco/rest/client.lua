--- coco.nvim Cortex REST client (Phase 4).

local M = {}

---@param opts { messages: table[], stream: boolean }
---@param cb fun(chunk: string|nil, done: boolean, err: string|nil)
function M.complete(opts, cb)
  -- TODO: implement in Phase 4.
  cb(nil, true, "not implemented")
end

return M
