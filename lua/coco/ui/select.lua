--- coco.nvim picker helpers (Phase 3).

local async = require("coco.util.async")
local json = require("coco.util.json")

local M = {}

---@param items any[]
---@param opts { prompt: string|nil, format: fun(item: any): string }
---@param cb fun(item: any|nil)
function M.pick(items, opts, cb)
  opts = opts or {}
  local ok, snacks = pcall(require, "snacks.picker")
  if ok and snacks and snacks.select then
    snacks.select(items, {
      prompt = opts.prompt or "Select: ",
      format_item = opts.format or tostring,
    }, cb)
    return
  end
  -- Some snacks setups expose the picker only via the global Snacks object.
  local Snacks = rawget(_G, "Snacks")
  if Snacks and Snacks.picker and Snacks.picker.select then
    Snacks.picker.select(items, {
      prompt = opts.prompt or "Select: ",
      format_item = opts.format or tostring,
    }, cb)
    return
  end
  vim.ui.select(items, {
    prompt = opts.prompt or "Select: ",
    format_item = opts.format or tostring,
  }, cb)
end

---@class CocoModel
---@field name string
---@field provider string|nil

---@param cb fun(err: string|nil, models: CocoModel[])
function M.models(cb)
  if vim.fn.executable("cortex") == 0 then
    cb("cortex not found on PATH", {})
    return
  end
  async.spawn({ "cortex", "models", "list", "--json" }, { timeout = 30000 }, function(obj)
    if obj.code ~= 0 then
      -- Fallback to plain text.
      async.spawn({ "cortex", "models", "list" }, { timeout = 30000 }, function(obj2)
        if obj2.code ~= 0 then
          cb(obj2.stderr or "cortex models list failed", {})
          return
        end
        local models = {}
        for line in (obj2.stdout or ""):gmatch("[^\r\n]+") do
          local name = line:match("^%s*(%S+)")
          if name and name ~= "Model" then
            table.insert(models, { name = name })
          end
        end
        cb(nil, models)
      end)
      return
    end
    local ok, parsed = json.decode(obj.stdout or "")
    if ok and type(parsed) == "table" then
      local arr = parsed.models or parsed
      local models = {}
      for _, m in ipairs(arr) do
        if type(m) == "table" then
          table.insert(models, { name = m.name or m.model or "", provider = m.provider })
        end
      end
      cb(nil, models)
      return
    end
    cb(nil, {})
  end)
end

return M
