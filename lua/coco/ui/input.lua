--- coco.nvim user input UI.

local config = require("coco.config")
local placeholders = require("coco.context.placeholders")
local manager = require("coco.session.manager")
local editor = require("coco.context.editor")

local M = {}

--- Ask CoCo, optionally with a pre-filled prompt.
---@param prompt string|nil
function M.ask(prompt)
  prompt = prompt or ""
  local q = editor.drain_context_queue()
  local ctx = { selection = editor.selection() }

  local function submit(final)
    final = placeholders.expand(final, ctx)
    -- Append any queued file context.
    if #q > 0 then
      local parts = {}
      for _, item in ipairs(q) do
        table.insert(parts, item.path)
      end
      final = final .. "\n\nContext files: " .. table.concat(parts, ", ")
    end
    manager.send(final)
  end

  if prompt ~= "" then
    submit(prompt)
    return
  end

  local ok, snacks = pcall(require, "snacks.input")
  if ok then
    snacks.input({
      prompt = "CoCo: ",
    }, function(value)
      if value then
        submit(value)
      end
    end)
  else
    vim.ui.input({ prompt = "CoCo: " }, function(value)
      if value then
        submit(value)
      end
    end)
  end
end

return M
