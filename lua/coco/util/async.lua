--- coco.nvim async / subprocess helpers.

local M = {}

---@class CocoAsyncHandle
---@field cancel fun()
---@field pid number|nil

--- Safely schedule a function on the main loop.
---@param fn fun()
function M.schedule(fn)
  vim.schedule(function()
    local ok, err = pcall(fn)
    if not ok then
      require("coco.util.log").error("scheduled callback error: " .. tostring(err))
    end
  end)
end

--- Spawn a subprocess asynchronously.
---@param cmd string[]
---@param opts vim.SystemOpts|nil
---@param cb fun(obj: vim.SystemCompleted)
---@return CocoAsyncHandle
function M.spawn(cmd, opts, cb)
  opts = opts or {}
  if opts.timeout == nil then
    opts.timeout = 60000
  end
  local safe_cb = function(obj)
    -- vim.system callbacks run in a fast-event context; schedule user code
    -- onto the main loop so it can safely call vimscript functions and APIs.
    M.schedule(function()
      cb(obj)
    end)
  end
  local proc = vim.system(cmd, opts, safe_cb)
  return {
    cancel = function()
      pcall(proc.kill, proc, "term")
    end,
    pid = proc.pid,
  }
end

--- Check if a command exists on PATH.
---@param name string
---@param cb fun(found: boolean, path: string|nil)
function M.which(name, cb)
  M.spawn({ "which", name }, { timeout = 5000 }, function(obj)
    local found = obj.code == 0 and obj.stdout and obj.stdout:match("%S")
    cb(found, found and vim.trim(obj.stdout) or nil)
  end)
end

return M
