--- coco.nvim native diff review (Phase 2).

local M = {}

---@param old_path string
---@param new_path string
---@param new_contents string
---@param tab_name string
---@return string diff_id
function M.open(old_path, new_path, new_contents, tab_name)
  -- TODO: implement in Phase 2.
  return ""
end

---@param diff_id string
function M.accept(diff_id)
  -- TODO: implement in Phase 2.
end

---@param diff_id string
function M.deny(diff_id)
  -- TODO: implement in Phase 2.
end

function M.close_all()
  -- TODO: implement in Phase 2.
end

return M
