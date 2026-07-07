--- coco.nvim Snowflake cost feedback (Phase 3).

local async = require("coco.util.async")
local json = require("coco.util.json")
local state = require("coco.session.state")
local log = require("coco.util.log")

local M = {}

local cached_credits ---@type number|nil
local cached_at = 0 ---@type number
local ttl_ms = 600000 -- 10 minutes

---@return number ms
local function now_ms()
  return math.floor(vim.uv.hrtime() / 1e6)
end

---@param stdout string
---@return number|nil
local function parse_credits(stdout)
  if not stdout or stdout == "" then
    return nil
  end
  local ok, parsed = json.decode(stdout)
  if ok and type(parsed) == "table" then
    local rows = parsed.rows or parsed.result or parsed.data or parsed
    if type(rows) == "table" and #rows > 0 then
      local first = rows[1]
      if type(first) == "table" then
        for _, v in pairs(first) do
          if type(v) == "number" then
            return v
          end
        end
      end
    end
  end
  -- Fallback: scan for a floating-point number.
  local num = stdout:match("(%d+%.?%d*)")
  return num and tonumber(num) or nil
end

---@param cb fun(err: string|nil, credits: number|nil)
function M.latest(cb)
  local now = now_ms()
  if cached_credits and (now - cached_at) < ttl_ms then
    cb(nil, cached_credits)
    return
  end

  -- Filter to the last 24 hours so the value reflects current session usage
  -- rather than an ever-growing all-time total.
  local query = "SELECT SUM(CREDITS_USED) AS CREDITS FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_REST_API_USAGE_HISTORY WHERE START_TIME >= DATEADD(hour, -24, CURRENT_TIMESTAMP())"
  async.spawn({ "cortex", "sql", "-q", query, "--format", "json" }, { timeout = 60000 }, function(obj)
    if obj.code ~= 0 then
      local err = obj.stderr or "cortex sql failed"
      log.warn("cost lookup failed: " .. err)
      cb(err, nil)
      return
    end
    local credits = parse_credits(obj.stdout or "")
    if credits then
      cached_credits = credits
      cached_at = now
      state.dispatch({ type = "set_credits", credits = credits })
    end
    cb(nil, credits)
  end)
end

--- Reset cached cost (useful on connection switch).
function M.clear()
  cached_credits = nil
  cached_at = 0
end

return M
