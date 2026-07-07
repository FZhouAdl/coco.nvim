--- coco.nvim Snowflake connection manager (Phase 3).

local async = require("coco.util.async")
local json = require("coco.util.json")
local state = require("coco.session.state")
local log = require("coco.util.log")

local M = {}

---@class CocoConnection
---@field name string
---@field active boolean
---@field role string|nil
---@field warehouse string|nil
---@field account string|nil

--- Parse JSON output from `cortex connections list --json`.
---@param stdout string
---@return CocoConnection[]
local function parse_json_list(stdout)
  local items = {}
  local ok, parsed = json.decode(stdout)
  if not ok or type(parsed) ~= "table" then
    return items
  end
  local arr = parsed.connections or parsed
  if type(arr) ~= "table" then
    return items
  end
  for _, c in ipairs(arr) do
    if type(c) == "table" then
      table.insert(items, {
        name = c.name or c.connection or "",
        active = c.active == true or c["*"] == true or c.is_active == true,
        role = c.role,
        warehouse = c.warehouse or c.ware_house,
        account = c.account,
      })
    end
  end
  return items
end

--- Parse plain-text table output from `cortex connections list`.
--- Heuristic: lines with at least two columns; active row marked with *.
---@param stdout string
---@return CocoConnection[]
local function parse_text_list(stdout)
  local items = {}
  for line in stdout:gmatch("[^\r\n]+") do
    local cols = {}
    for col in line:gmatch("%S+") do
      table.insert(cols, col)
    end
    if #cols >= 2 and cols[1] ~= "Name" and cols[1] ~= "Connection" then
      local raw_first = cols[1]
      local active = raw_first:find("^%*") ~= nil
      local name = active and cols[2] or raw_first
      table.insert(items, {
        name = name,
        active = active,
        role = active and cols[3] or cols[2],
        warehouse = active and cols[4] or cols[3],
        account = active and cols[5] or cols[4],
      })
    end
  end
  return items
end

---@param stdout string
---@return CocoConnection[]
local function parse_list(stdout)
  local items = parse_json_list(stdout)
  if #items > 0 then
    return items
  end
  return parse_text_list(stdout)
end

---@param items CocoConnection[]
local function update_state(items)
  for _, c in ipairs(items) do
    if c.active then
      state.dispatch({
        type = "set_connection",
        connection = c.name,
        role = c.role,
        warehouse = c.warehouse,
      })
      break
    end
  end
end

---@param cb fun(err: string|nil, connections: CocoConnection[])
function M.list(cb)
  if vim.fn.executable("cortex") == 0 then
    cb("cortex not found on PATH", {})
    return
  end
  async.spawn({ "cortex", "connections", "list", "--json" }, { timeout = 30000 }, function(obj)
    if obj.code ~= 0 then
      -- Fallback to plain text.
      async.spawn({ "cortex", "connections", "list" }, { timeout = 30000 }, function(obj2)
        if obj2.code ~= 0 then
          cb(obj2.stderr or "cortex connections list failed", {})
          return
        end
        local items = parse_list(obj2.stdout or "")
        update_state(items)
        cb(nil, items)
      end)
      return
    end
    local items = parse_list(obj.stdout or "")
    update_state(items)
    cb(nil, items)
  end)
end

---@param name string
---@param cb fun(err: string|nil)
function M.set(name, cb)
  async.spawn({ "cortex", "connections", "set", name }, { timeout = 30000 }, function(obj)
    if obj.code ~= 0 then
      local err = obj.stderr or "cortex connections set failed"
      log.error("connection set failed: " .. err)
      cb(err)
      return
    end
    state.dispatch({
      type = "set_connection",
      connection = name,
      role = nil,
      warehouse = nil,
    })
    log.info("connection set to " .. name)
    cb(nil)
  end)
end

return M
