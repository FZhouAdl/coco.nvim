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
local clock_offset = 0 ---@type number

---@return number ms
local function now_ms()
  return (os.time() * 1000) + clock_offset
end

---@return string
local function cache_key(name)
  local s = state.get()
  local conn = s.connection or "default"
  local role = s.role or ""
  return conn .. "|" .. role .. "|" .. name:upper()
end

--- Evict expired entries and enforce max size (LRU by insertion order).
local function prune_cache()
  local cfg = config.get().snowflake.object_cache
  local now = now_ms()
  local ttl = cfg.ttl_ms or 300000
  for k, v in pairs(cache) do
    if v.expires < now then
      cache[k] = nil
    end
  end
  local size = cfg.size or 32
  local keys = {}
  for k, _ in pairs(cache) do
    table.insert(keys, k)
  end
  while #keys > size do
    cache[keys[1]] = nil
    table.remove(keys, 1)
  end
end

--- Clear the object cache.
function M.clear()
  cache = {}
end

--- Inject a clock offset (ms) for tests.
---@param offset number
function M._set_clock_offset(offset)
  clock_offset = offset
end

---@param name string
---@param cb fun(err: string|nil, result: table|string|nil)
function M.lookup(name, cb)
  prune_cache()
  local key = cache_key(name)
  local entry = cache[key]
  if entry and entry.expires > now_ms() then
    cb(nil, entry.result)
    return
  end

  local s = state.get()
  local conn = s.connection
  if not conn then
    cb("no active Snowflake connection", nil)
    return
  end

  -- Start lookup in background and return pending sentinel immediately.
  -- The agent can poll getSnowflakeObject again shortly.
  local function fetch()
    local function try_table_details(next)
      async.spawn({ "cortex", "search", "table-details", name }, { timeout = 60000 }, function(obj)
        if obj.code == 0 and obj.stdout and obj.stdout:match("%S") then
          local parsed = parse_result(name, obj.stdout)
          cache[key] = { result = parsed, expires = now_ms() + (config.get().snowflake.object_cache.ttl_ms or 300000) }
          return
        end
        next()
      end)
    end

    local function try_object_search()
      async.spawn({ "cortex", "search", "object", name }, { timeout = 60000 }, function(obj)
        if obj.code ~= 0 then
          log.warn("snowflake lookup failed for " .. name .. ": " .. (obj.stderr or ""))
          return
        end
        local parsed = parse_result(name, obj.stdout)
        cache[key] = { result = parsed, expires = now_ms() + (config.get().snowflake.object_cache.ttl_ms or 300000) }
      end)
    end

    try_table_details(try_object_search)
  end

  fetch()
  cb(nil, { pending = true, message = "lookup pending; retry shortly" })
end

--- Parse CLI stdout into a structured result with cap handling.
---@param name string
---@param stdout string
---@return table
function parse_result(name, stdout)
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
    -- Truncate displayed text to columns + comments heuristically.
    local lines = vim.split(text, "\n")
    local kept = {}
    local in_columns = false
    for _, line in ipairs(lines) do
      if line:match("^%s*[Cc][Oo][Ll][Uu][Mm][Nn]") or line:match("[Cc][Oo][Ll][Uu][Mm][Nn][ _-]?[Nn][Aa][Mm][Ee]") then
        in_columns = true
      elseif in_columns and line:match("^%s*[Cc][Oo][Mm][Mm][Ee][Nn][Tt]") then
        in_columns = false
      end
      if not in_columns or #table.concat(kept, "\n") < cap - 4096 then
        table.insert(kept, line)
      else
        break
      end
    end
    text = table.concat(kept, "\n")
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

return M
