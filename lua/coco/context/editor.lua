--- coco.nvim editor context primitives.

local M = {}

---@class CocoBufferContext
---@field filePath string
---@field name string
---@field active boolean
---@field modified boolean
---@field filetype string

---@class CocoSelection
---@field filePath string
---@field startLine number
---@field startCol number
---@field endLine number
---@field endCol number
---@field text string

--- Get the absolute file path of the current buffer.
---@return string
function M.current_file_path()
  return vim.fn.expand("%:p")
end

--- Capture the current visual selection or cursor position.
---@return CocoSelection
function M.selection()
  local mode = vim.fn.mode()
  local bufname = vim.fn.expand("%:p")
  local text = ""
  local sl, sc, el, ec
  if mode:match("[vV\22]") then
    local vstart = vim.fn.getpos("v")
    local vend = vim.fn.getpos(".")
    sl = math.min(vstart[2], vend[2])
    el = math.max(vstart[2], vend[2])
    sc = math.min(vstart[3], vend[3])
    ec = math.max(vstart[3], vend[3])
    text = M.get_visual_selection_text()
  else
    local pos = vim.api.nvim_win_get_cursor(0)
    sl, el = pos[1], pos[1]
    sc = pos[2] + 1
    ec = sc
    text = vim.api.nvim_get_current_line()
  end
  return {
    filePath = bufname,
    startLine = sl or 1,
    startCol = sc or 1,
    endLine = el or 1,
    endCol = ec or 1,
    text = text or "",
  }
end

--- Return the text of the current visual selection.
---@return string
function M.get_visual_selection_text()
  local _, ls, cs = unpack(vim.fn.getpos("'<") or { 0, 0, 0 })
  local _, le, ce = unpack(vim.fn.getpos("'>") or { 0, 0, 0 })
  if ls == 0 then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(0, ls - 1, le, false)
  if #lines == 0 then
    return ""
  end
  lines[#lines] = lines[#lines]:sub(1, ce)
  lines[1] = lines[1]:sub(cs)
  return table.concat(lines, "\n")
end

--- Return open buffer metadata.
---@return CocoBufferContext[]
function M.open_buffers()
  local bufs = {}
  local current = vim.api.nvim_get_current_buf()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
      local name = vim.api.nvim_buf_get_name(b)
      table.insert(bufs, {
        filePath = name,
        name = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]",
        active = b == current,
        modified = vim.bo[b].modified,
        filetype = vim.bo[b].filetype,
      })
    end
  end
  return bufs
end

--- Return LSP diagnostics.
---@param uri string|nil nil means all buffers
---@return table[]
function M.diagnostics(uri)
  local items = {}
  local bufs = uri and { vim.uri_to_bufnr(uri) } or vim.api.nvim_list_bufs()
  for _, b in ipairs(bufs) do
    if vim.api.nvim_buf_is_loaded(b) then
      for _, d in ipairs(vim.diagnostic.get(b)) do
        local row = (d.lnum or 0) + 1
        local col = (d.col or 0) + 1
        table.insert(items, {
          filePath = vim.api.nvim_buf_get_name(b),
          line = row,
          column = col,
          severity = d.severity,
          message = d.message,
          source = d.source,
          code = d.code,
        })
      end
    end
  end
  return items
end

--- Return workspace info.
---@return { cwd: string, git_root: string|nil, workspace_folders: string[] }
function M.workspace_info()
  local cwd = vim.fn.getcwd()
  local git_root = vim.fs.root(0, ".git") or vim.fs.root(cwd, ".git")
  return {
    cwd = cwd,
    git_root = git_root,
    workspace_folders = { cwd },
  }
end

--- Context queue used by :CocoAdd / :CocoAsk.
local context_queue = {}

--- Add a file/range to the context queue.
---@param path string|nil
---@param l1 number|nil
---@param l2 number|nil
function M.add_to_context(path, l1, l2)
  path = path or M.current_file_path()
  table.insert(context_queue, { path = path, l1 = l1, l2 = l2 })
end

--- Drain and return the context queue.
---@return { path: string, l1: number|nil, l2: number|nil }[]
function M.drain_context_queue()
  local q = context_queue
  context_queue = {}
  return q
end

return M
