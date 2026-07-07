--- coco.nvim native diff review (Phase 2).

local state = require("coco.session.state")
local log = require("coco.util.log")

local M = {}

---@class CocoDiffView
---@field old_path string
---@field new_path string
---@field tabpage number
---@field new_bufnr number

local views = {} ---@type table<string, CocoDiffView>
local augroup = vim.api.nvim_create_augroup("CocoDiff", { clear = true })

--- Read file contents or return empty string.
---@param path string
---@return string
local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return ""
  end
  local data = fd:read("*a")
  fd:close()
  return data or ""
end

--- Open a diff review tab for proposed changes.
---@param old_path string
---@param new_path string
---@param new_contents string
---@param tab_name string|nil
---@return string diff_id
function M.open(old_path, new_path, new_contents, tab_name)
  local id = old_path

  -- Close any existing view for this path.
  M.close(id)

  -- Create scratch buffer for new contents.
  local new_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[new_buf].buftype = "acwrite"
  vim.bo[new_buf].bufhidden = "wipe"
  vim.bo[new_buf].swapfile = false
  vim.bo[new_buf].modifiable = true
  vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, vim.split(new_contents, "\n"))
  vim.bo[new_buf].modifiable = false
  vim.api.nvim_buf_set_name(new_buf, "coco://diff/" .. vim.fn.fnamemodify(new_path, ":t"))

  -- Open diff tab.
  vim.cmd("tabnew " .. vim.fn.fnameescape(old_path))
  local tabpage = vim.api.nvim_get_current_tabpage()
  local old_win = vim.api.nvim_get_current_win()
  vim.cmd("diffthis")

  vim.cmd("vsplit")
  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_win, new_buf)
  vim.cmd("diffthis")

  views[id] = {
    old_path = old_path,
    new_path = new_path,
    tabpage = tabpage,
    new_bufnr = new_buf,
  }

  state.dispatch({ type = "diff_open", id = id })

  vim.api.nvim_buf_set_var(new_buf, "coco_diff_id", id)
  local ok, old_buf = pcall(vim.api.nvim_win_get_buf, old_win)
  if ok then
    vim.api.nvim_buf_set_var(old_buf, "coco_diff_id", id)
  end

  -- Optional keymaps.
  if require("coco.config").get().ui.diff.keymaps then
    local opts = { buffer = new_buf, silent = true }
    vim.keymap.set("n", "<leader>ca", function()
      M.accept(id)
    end, opts)
    vim.keymap.set("n", "<leader>cx", function()
      M.deny(id)
    end, opts)
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(new_win),
    once = true,
    callback = function()
      M.close(id)
      local entry = state.get().diffs[id]
      if entry and entry.status == "pending" then
        state.dispatch({ type = "diff_resolve", id = id, status = "DIFF_REJECTED" })
        state.dispatch({ type = "counter", name = "diff_rejected_total", delta = 1 })
      end
    end,
  })

  return id
end

--- Accept a diff and write the new contents to disk.
---@param diff_id string
function M.accept(diff_id)
  local view = views[diff_id]
  if not view then
    log.warn("diff accept: no view for " .. diff_id)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(view.new_bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  -- Preserve POSIX trailing newline if the buffer content lacks one.
  if text:sub(-1) ~= "\n" then
    text = text .. "\n"
  end
  local fd = io.open(view.old_path, "w")
  if not fd then
    log.error("diff accept: failed to open " .. view.old_path)
    return
  end
  fd:write(text)
  fd:close()
  state.dispatch({ type = "diff_resolve", id = diff_id, status = "FILE_SAVED" })
  state.dispatch({ type = "counter", name = "diff_accepted_total", delta = 1 })
  M.close(diff_id)
  log.info("diff accepted: " .. view.old_path)
end

--- Deny a diff and close its tab.
---@param diff_id string
function M.deny(diff_id)
  local view = views[diff_id]
  if not view then
    log.warn("diff deny: no view for " .. diff_id)
    return
  end
  state.dispatch({ type = "diff_resolve", id = diff_id, status = "DIFF_REJECTED" })
  state.dispatch({ type = "counter", name = "diff_rejected_total", delta = 1 })
  M.close(diff_id)
  log.info("diff denied: " .. view.old_path)
end

--- Close a diff view without changing resolution state.
---@param diff_id string
function M.close(diff_id)
  local view = views[diff_id]
  if not view then
    return
  end
  if vim.api.nvim_tabpage_is_valid(view.tabpage) then
    pcall(vim.api.nvim_set_current_tabpage, view.tabpage)
    pcall(vim.cmd, "tabclose")
  end
  views[diff_id] = nil
end

--- Close all diff tabs.
function M.close_all()
  for id, _ in pairs(views) do
    M.close(id)
  end
  views = {}
end

---@return table<string, CocoDiffView>
function M._views()
  return views
end

return M
