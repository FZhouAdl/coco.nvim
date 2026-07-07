--- coco.nvim user input UI.

local config = require("coco.config")
local placeholders = require("coco.context.placeholders")
local manager = require("coco.session.manager")
local editor = require("coco.context.editor")
local rest = require("coco.rest.client")
local float = require("coco.ui.float")
local virt = require("coco.ui.virt")

local M = {}

--- Build a one-shot REST message list from a prompt.
---@param prompt string
---@return table[]
local function build_messages(prompt)
  return {
    { role = "system", content = "You are a helpful coding assistant." },
    { role = "user", content = prompt },
  }
end

--- Stream a one-shot answer to a scratch buffer.
---@param prompt string
local function rest_ask(prompt)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "# CoCo", "", "Thinking…" })
  float.open({ bufnr = bufnr })

  local current_line = ""
  local proc ---@type vim.SystemObj|nil

  local function cleanup()
    if proc and proc.kill then
      pcall(proc.kill, proc, "term")
    end
    proc = nil
  end

  vim.api.nvim_create_autocmd({ "WinClosed", "BufWipeout" }, {
    buffer = bufnr,
    once = true,
    callback = cleanup,
  })

  proc = rest.complete({ messages = build_messages(prompt), stream = true }, function(chunk, done, err)
    if err then
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "Error: " .. err })
      end)
      return
    end
    if done then
      return
    end
    if chunk and chunk.type == "text" and chunk.text then
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        local text = chunk.text
        -- Append text, splitting on newlines. Only the last buffer line is
        -- rewritten; completed lines are appended once.
        local parts = vim.split(text, "\n", { plain = true })
        for i, part in ipairs(parts) do
          if i == 1 then
            current_line = current_line .. part
          else
            vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { part })
            current_line = part
          end
        end
        vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, { current_line })
      end)
    end
  end)
end

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

    if config.get().transport.rest.enabled then
      rest_ask(final)
    else
      manager.send(final)
    end
  end

  if prompt ~= "" then
    submit(prompt)
    return
  end

  local ok, snacks = pcall(require, "snacks.input")
  if ok and snacks then
    local handled = false
    local ret = snacks.input({
      prompt = "CoCo: ",
    }, function(value)
      if not handled and value then
        handled = true
        submit(value)
      end
    end)
    -- Some snacks.input variants return the value directly instead of using a callback.
    if not handled and type(ret) == "string" and ret ~= "" then
      handled = true
      submit(ret)
    end
  else
    vim.ui.input({ prompt = "CoCo: " }, function(value)
      if value then
        submit(value)
      end
    end)
  end
end

--- Trigger ghost-text completion at the cursor.
function M.complete()
  local prompt = editor.selection().text
  if prompt == "" then
    prompt = vim.api.nvim_get_current_line()
  end
  prompt = "Complete the following code:\n" .. prompt

  virt.start_completion("…")
  local completion_parts = {}
  local proc = rest.complete({ messages = build_messages(prompt), stream = true }, function(chunk, done, err)
    if done or err then
      return
    end
    if chunk and chunk.type == "text" then
      vim.schedule(function()
        table.insert(completion_parts, chunk.text or "")
        virt.update_completion(table.concat(completion_parts))
      end)
    end
  end)
  -- Store the process handle so a new completion cancels the previous stream.
  virt._set_completion_proc(proc)
end

return M
