--- coco.nvim Cortex REST client (Phase 4).

local auth = require("coco.rest.auth")
local sse = require("coco.rest.sse")
local log = require("coco.util.log")
local json = require("coco.util.json")
local toml = require("coco.util.toml")

local M = {}

---@param ev table
---@return table|nil
local function parse_sse_event(ev)
  if ev.data == "" or ev.data == "[DONE]" then
    return nil
  end
  local ok, parsed = pcall(vim.json.decode, ev.data, { object = true, array = true })
  if not ok then
    return { type = "raw", data = ev.data }
  end
  local choices = parsed.choices
  if type(choices) == "table" and #choices > 0 then
    local delta = choices[1].delta
    if delta then
      if delta.content then
        return { type = "text", text = delta.content }
      elseif delta.tool_calls then
        return { type = "tool_use", tool_calls = delta.tool_calls }
      end
    end
  end
  return { type = "chunk", chunk = parsed }
end

---@class CocoRestCompleteOpts
---@field messages table[]
---@field stream boolean|nil
---@field model string|nil

---@param opts CocoRestCompleteOpts
---@param cb fun(chunk: table|nil, done: boolean, err: string|nil)
function M.complete(opts, cb)
  local pat = auth.get_pat()
  if not pat then
    cb(nil, true, "no PAT found in environment or connections.toml")
    return
  end

  local account = M._get_account()
  if not account then
    cb(nil, true, "no Snowflake account found")
    return
  end

  local url = string.format("https://%s.snowflakecomputing.com/api/v2/cortex/v1/chat/completions", account)
  local body = {
    model = opts.model or "llama3.1-70b",
    messages = opts.messages,
    stream = opts.stream ~= false,
  }
  local body_json, enc_err = json.encode(body)
  if not body_json then
    cb(nil, true, "failed to encode request: " .. tostring(enc_err))
    return
  end

  log.debug("rest request to " .. url)

  local parser = sse.new()
  -- Keep the bearer token off the command line by passing headers via stdin.
  local headers = "Authorization: Bearer " .. pat .. "\nContent-Type: application/json\n"
  local proc = vim.system({
    "curl",
    "-N",
    "-s",
    "--header",
    "@-",
    "-d",
    body_json,
    url,
  }, {
    stdin = headers,
    stdout = function(_, data)
      if data then
        vim.schedule(function()
          for _, ev in ipairs(parser:feed(data)) do
            local delta = parse_sse_event(ev)
            if delta then
              cb(delta, false, nil)
            end
          end
        end)
      end
    end,
  }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        cb(nil, true, obj.stderr or "curl failed")
        return
      end
      cb(nil, true, nil)
    end)
  end)

  return proc
end

---@return string|nil
function M._get_account()
  local account = vim.env.SNOWFLAKE_ACCOUNT
  if account and account ~= "" then
    return account
  end
  -- Try to read from connections.toml.
  local home = vim.env.HOME or ""
  local fd = io.open(home .. "/.snowflake/connections.toml", "r")
  if not fd then
    return nil
  end
  local data = fd:read("*a")
  fd:close()
  local active = auth.config_active_connection() or "default"
  local account = toml.section_value(data, active, "account")
  if account and account ~= "" then
    return account
  end
  return nil
end

return M
