--- coco.nvim HTTP MCP server (Phase 2).

local M = {}

---@class CocoMcpServerOpts
---@field host string
---@field port number
---@field token string
---@field handler fun(req: table): table

---@param opts CocoMcpServerOpts
---@param cb fun(err: string|nil, port: number|nil)
function M.start(opts, cb)
  -- TODO: implement in Phase 2.
  cb("not implemented", nil)
end

function M.stop()
  -- TODO: implement in Phase 2.
end

return M
