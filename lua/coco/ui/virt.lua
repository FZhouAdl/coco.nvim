--- coco.nvim virtual text / extmarks (Phase 4).

local M = {}

local ns = vim.api.nvim_create_namespace("coco.nvim")

---@param bufnr number
---@param line number
---@param text string
function M.set(bufnr, line, text)
  vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
    virt_text = { { text, "Comment" } },
    virt_text_pos = "eol",
  })
end

---@param bufnr number|nil
function M.clear(bufnr)
  if bufnr then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  else
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      vim.api.nvim_buf_clear_namespace(b, ns, 0, -1)
    end
  end
end

return M
