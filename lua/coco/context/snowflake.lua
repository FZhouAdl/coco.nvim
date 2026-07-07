--- coco.nvim Snowflake object metadata (Phase 3).

local config = require("coco.config")
local state = require("coco.session.state")
local async = require("coco.util.async")
local json = require("coco.util.json")
local log = require("coco.util.log")

local M = {}

---@class CocoCacheEntry
---@field result table|string
---@field expires number

local cache = {} ---@type table<string, CocoCacheEntry>
local order = {} ---@type string[]
local pending = {} ---@type table<string, fun(err: string|nil, result: table|string|nil)[]>
local clock_offset = 0 ---@type number

---@return number ms
local function now_ms()
  return (vim.uv.hrtime() / 1e6) + clock_offset
end

---@return string
local function cache_key(name)
  local s = state.get()
  local conn = s.connection or "default"
  local role = s.role or ""
  return conn .. "|" .. role .. "|" .. name:upper()
end

--- Move key to most-recent position.
---@param key string
local function touch(key)
  for i, k in ipairs(order) do
    if k == key then
      table.remove(order, i)
      break
    end
  end
  table.insert(order, key)
end

--- Evict expired entries and enforce max size (LRU by access/insertion order).
local function prune_cache()
  local cfg = config.get().snowflake.object_cache
  local now = now_ms()
  local ttl = cfg.ttl_ms or 300000
  local expired = {}
  for key, entry in pairs(cache) do
    if entry.expires < now then
      table.insert(expired, key)
    end
  end
  for _, key in ipairs(expired) do
    cache[key] = nil
    for i, k in ipairs(order) do
      if k == key then
        table.remove(order, i)
        break
      end
    end
  end
  local size = cfg.size or 32
  while #order > size do
    local key = table.remove(order, 1)
    cache[key] = nil
  end
end

--- Clear the object cache.
function M.clear()
  cache = {}
  order = {}
  pending = {}
end

--- Inject a clock offset (ms) for tests.
---@param offset number
function M._set_clock_offset(offset)
  clock_offset = offset
end

--- Parse CLI stdout into a structured result with cap handling.
---@param name string
---@param stdout string
---@return table
local function parse_result(name, stdout)
  local text = stdout or ""
  local cap = 51200
  local truncated = false
  local file_path
  if #text > cap then
    truncated = true
    local cache_dir = vim.fn.stdpath("cache")
    file_path = cache_dir .. "/coco_object_" .. name:gsub("[^A-Za-z0-9_]", "_") .. ".txt"
    local fd = io.open(file_path, "w")
    if fd then
      fd:write(text)
      fd:close()
    else
      file_path = nil
    end
    -- Truncate displayed text unconditionally by running byte total.
    local lines = vim.split(text, "\n")
    local kept = {}
    local used = 0
    local max_keep = cap - 4096
    for _, line in ipairs(lines) do
      local line_cost = #line + 1
      if used + line_cost > max_keep then
        break
      end
      used = used + line_cost
      table.insert(kept, line)
    end
    text = table.concat(kept, "\n") .. "\n[truncated; full output at " .. (file_path or "<unwritable>") .. "]"
  end
  local ok, parsed = json.decode(text)
  if ok and type(parsed) == "table" then
    parsed.truncated = truncated
    parsed.file_path = file_path
    return parsed
  end
  return {
    name = name,
    text = text,
    truncated = truncated,
    file_path = file_path,
  }
end

--- Resolve all pending callbacks for a key.
---@param key string
---@param err string|nil
---@param result table|string|nil
local function resolve_pending(key, err, result)
  local cbs = pending[key]
  pending[key] = nil
  if cbs then
    for _, cb in ipairs(cbs) do
      local ok, cb_err = pcall(cb, err, result)
      if not ok then
        log.error("snowflake lookup callback error: " .. tostring(cb_err))
      end
    end
  end
end

--- Run the fetch subprocess and cache the result.
---@param name string
---@param key string
local function fetch(name, key)
  local function try_table_details(next)
    async.spawn({ "cortex", "search", "table-details", name }, { timeout = 60000 }, function(obj)
      if obj.code == 0 and obj.stdout and obj.stdout:match("%S") then
        local parsed = parse_result(name, obj.stdout)
        cache[key] = { result = parsed, expires = now_ms() + (config.get().snowflake.object_cache.ttl_ms or 300000) }
        touch(key)
        resolve_pending(key, nil, parsed)
        return
      end
      next()
    end)
  end

  local function try_object_search()
    async.spawn({ "cortex", "search", "object", name }, { timeout = 60000 }, function(obj)
      if obj.code ~= 0 then
        local err = obj.stderr or "cortex search failed"
        log.warn("snowflake lookup failed for " .. name .. ": " .. err)
        resolve_pending(key, err, nil)
        return
      end
      local parsed = parse_result(name, obj.stdout)
      cache[key] = { result = parsed, expires = now_ms() + (config.get().snowflake.object_cache.ttl_ms or 300000) }
      touch(key)
      resolve_pending(key, nil, parsed)
    end)
  end

  try_table_details(try_object_search)
end

---@param name string
---@param cb fun(err: string|nil, result: table|string|nil)
function M.lookup(name, cb)
  prune_cache()
  local key = cache_key(name)
  local entry = cache[key]
  if entry and entry.expires > now_ms() then
    touch(key)
    cb(nil, entry.result)
    return
  end

  local s = state.get()
  local conn = s.connection
  if not conn then
    cb("no active Snowflake connection", nil)
    return
  end

  -- Deduplicate in-flight lookups.
  if pending[key] then
    table.insert(pending[key], cb)
    return
  end
  pending[key] = { cb }

  fetch(name, key)
  -- Return pending sentinel immediately; agent can poll getSnowflakeObject.
  cb(nil, { pending = true, message = "lookup pending; retry shortly" })
end

--- Blocking variant for placeholder expansion.
---@param name string
---@param timeout_ms number
---@param cb fun(err: string|nil, result: table|string|nil)
function M.lookup_sync(name, timeout_ms, cb)
  prune_cache()
  local key = cache_key(name)
  local entry = cache[key]
  if entry and entry.expires > now_ms() then
    cb(nil, entry.result)
    return
  end

  local done = false
  M.lookup(name, function(err, result)
    if result and result.pending then
      return
    end
    done = true
    cb(err, result)
  end)

  vim.wait(timeout_ms or 30000, function()
    return done
  end, 10)
end

return M
