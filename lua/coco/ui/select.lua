--- coco.nvim picker helpers (Phase 3).

local M = {}

---@param items any[]
---@param opts { prompt: string|nil, format: fun(item: any): string }
---@param cb fun(item: any|nil)
function M.pick(items, opts, cb)
  opts = opts or {}
  local ok, _ = pcall(require, "snacks.picker")
  if ok then
    -- TODO: snacks picker integration.
  end
  vim.ui.select(items, {
    prompt = opts.prompt or "Select: ",
    format_item = opts.format or tostring,
  }, cb)
end

return M
