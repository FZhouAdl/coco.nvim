--- coco.nvim placeholder expansion.

local editor = require("coco.context.editor")
local snowflake = require("coco.context.snowflake")

local M = {}

---@class CocoPlaceholderContext
---@field selection CocoSelection|nil
---@field buffers CocoBufferContext[]|nil
---@field diagnostics table[]|nil

--- Expand placeholders in a prompt string.
---@param prompt string
---@param ctx CocoPlaceholderContext|nil
---@return string expanded
function M.expand(prompt, ctx)
  ctx = ctx or {}
  local selection = ctx.selection or editor.selection()
  local buffers = ctx.buffers or editor.open_buffers()
  local diagnostics = ctx.diagnostics

  -- @this
  prompt = prompt:gsub("@this", function()
    return selection.text ~= "" and selection.text
      or ("cursor at %s:%d:%d"):format(selection.filePath, selection.startLine, selection.startCol)
  end)

  -- @buffer
  prompt = prompt:gsub("@buffer", function()
    local current = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(current, 0, -1, false)
    return table.concat(lines, "\n")
  end)

  -- @buffers
  prompt = prompt:gsub("@buffers", function()
    local parts = {}
    for _, b in ipairs(buffers) do
      table.insert(parts, ("%s%s"):format(b.filePath, b.modified and " [modified]" or ""))
    end
    return table.concat(parts, "\n")
  end)

  -- @diagnostics
  prompt = prompt:gsub("@diagnostics", function()
    local diags = diagnostics or editor.diagnostics()
    if #diags == 0 then
      return "No diagnostics."
    end
    local parts = {}
    for _, d in ipairs(diags) do
      table.insert(parts, ("%s:%d:%d [%d] %s"):format(d.filePath, d.line, d.column, d.severity, d.message))
    end
    return table.concat(parts, "\n")
  end)

  -- @object:<NAME>
  prompt = prompt:gsub("@object:([^%s]+)", function(name)
    local done = false
    local result
    snowflake.lookup(name, function(err, res)
      if err then
        result = "[object lookup failed: " .. err .. "]"
      elseif res and res.pending then
        result = "[object " .. name .. " lookup pending; retry shortly]"
      elseif type(res) == "table" then
        local ok2, encoded = pcall(vim.json.encode, res)
        result = ok2 and encoded or tostring(res)
      else
        result = tostring(res or "")
      end
      done = true
    end)
    vim.wait(2000, function()
      return done
    end, 10)
    return result or "[object " .. name .. " lookup timeout]"
  end)

  -- @marks, @quickfix, @visible — minimal stubs.
  prompt = prompt:gsub("@marks", function()
    return "(marks not yet implemented)"
  end)
  prompt = prompt:gsub("@quickfix", function()
    local qf = vim.fn.getqflist()
    if #qf == 0 then
      return "Quickfix list is empty."
    end
    local parts = {}
    for _, e in ipairs(qf) do
      local fname = e.bufnr and vim.api.nvim_buf_get_name(e.bufnr) or ""
      table.insert(parts, ("%s:%d: %s"):format(fname, e.lnum or 0, e.text or ""))
    end
    return table.concat(parts, "\n")
  end)
  prompt = prompt:gsub("@visible", function()
    local visible = {}
    local first = vim.fn.line("w0")
    local last = vim.fn.line("w$")
    local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
    return table.concat(lines, "\n")
  end)

  return prompt
end

return M
