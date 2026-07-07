--- coco.nvim virtual text / extmarks (Phase 4).

local M = {}

local ns = vim.api.nvim_create_namespace("coco.nvim")
local current_completion = nil ---@type { bufnr: number, line: number, extmark: number, text: string }|nil
local current_proc = nil ---@type vim.SystemObj|nil

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
  current_completion = nil
  if bufnr then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  else
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      vim.api.nvim_buf_clear_namespace(b, ns, 0, -1)
    end
  end
end

--- Start a ghost-text completion at the current cursor line.
---@param text string
function M.start_completion(text)
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  M.cancel_completion()
  local extmark = vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
    virt_text = { { text, "Comment" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
  current_completion = { bufnr = bufnr, line = line, extmark = extmark, text = text }
end

--- Update the current ghost-text completion.
---@param text string
function M.update_completion(text)
  if not current_completion then
    M.start_completion(text)
    return
  end
  if not vim.api.nvim_buf_is_valid(current_completion.bufnr) then
    M.start_completion(text)
    return
  end
  vim.api.nvim_buf_set_extmark(current_completion.bufnr, ns, current_completion.line, 0, {
    id = current_completion.extmark,
    virt_text = { { text, "Comment" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
  current_completion.text = text
end

--- Accept the current completion by inserting its text at the cursor.
function M.accept_completion()
  if not current_completion then
    return
  end
  local bufnr = current_completion.bufnr
  local line = current_completion.line
  local text = current_completion.text
  local row = line
  local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
  if not lines or not lines[1] then
    M.cancel_completion()
    return
  end
  local col = #lines[1]
  local new_lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(bufnr, row, col, row, col, new_lines)
  M.cancel_completion()
end

--- Cancel and clear the current completion.
function M.cancel_completion()
  M._cancel_completion_proc()
  if current_completion then
    if vim.api.nvim_buf_is_valid(current_completion.bufnr) then
      vim.api.nvim_buf_del_extmark(current_completion.bufnr, ns, current_completion.extmark)
    end
    current_completion = nil
  end
end

--- Attach the in-flight REST process for cancellation.
---@param proc vim.SystemObj|nil
function M._set_completion_proc(proc)
  current_proc = proc
end

--- Kill the in-flight completion process, if any.
function M._cancel_completion_proc()
  if current_proc and current_proc.kill then
    pcall(current_proc.kill, current_proc, "term")
  end
  current_proc = nil
end

---@return { bufnr: number, text: string }|nil
function M.current_completion()
  if not current_completion then
    return nil
  end
  return { bufnr = current_completion.bufnr, text = current_completion.text }
end

return M
