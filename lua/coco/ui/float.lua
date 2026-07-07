--- coco.nvim floating window helpers (Phase 2/4).

local M = {}

---@param opts { bufnr: number|nil, width: number|nil, height: number|nil }
---@return number winnr
function M.open(opts)
  local bufnr = opts.bufnr or vim.api.nvim_create_buf(false, true)
  local width = opts.width or math.floor(vim.o.columns * 0.8)
  local height = opts.height or math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local opts_k = { buffer = bufnr, silent = true, nowait = true }
  vim.keymap.set("n", "q", close, opts_k)
  vim.keymap.set("n", "<Esc>", close, opts_k)

  return win
end

return M
