--- coco.nvim MCP registration lifecycle (Phase 2).

local async = require("coco.util.async")
local json = require("coco.util.json")
local log = require("coco.util.log")

local M = {}

---@return string
local function mcp_json_path()
  return (vim.env.HOME or "") .. "/.snowflake/cortex/mcp.json"
end

--- Read the cortex mcp.json file if it exists.
---@return table|nil
local function read_mcp_json()
  local path = mcp_json_path()
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local data = fd:read("*a")
  fd:close()
  local ok, parsed = json.decode(data)
  if not ok then
    return nil
  end
  return parsed
end

--- Extract the port from a URL like http://127.0.0.1:1234/mcp
---@param url string
---@return number|nil
local function url_port(url)
  local port = url:match("://127%.0%.0%.1:(%d+)")
  if port then
    return tonumber(port)
  end
  port = url:match("://localhost:(%d+)")
  if port then
    return tonumber(port)
  end
  return nil
end

--- Probe whether a TCP port is reachable on 127.0.0.1.
---@param port number
---@param cb fun(reachable: boolean)
local function probe_port(port, cb)
  local sock = vim.loop.new_tcp()
  local timer = vim.loop.new_timer()
  local closed = false
  local function finish(reachable)
    if closed then
      return
    end
    closed = true
    if timer then
      timer:stop()
      timer:close()
    end
    pcall(sock.close, sock)
    cb(reachable)
  end
  timer:start(1000, 0, function()
    finish(false)
  end)
  sock:connect("127.0.0.1", port, function(err)
    finish(err == nil)
  end)
end

--- Prune stale registration for the named MCP server.
---@param server_name string
---@param expected_port number
---@param cb fun(pruned: boolean)
local function prune_stale(server_name, expected_port, cb)
  local cfg = read_mcp_json()
  if not cfg or type(cfg.mcpServers) ~= "table" then
    cb(false)
    return
  end
  local entry = cfg.mcpServers[server_name]
  if not entry or type(entry) ~= "table" then
    cb(false)
    return
  end
  local url = entry.url or entry.uri or ""
  local port = url_port(url)
  if port == expected_port then
    probe_port(port, function(reachable)
      if reachable then
        cb(false)
      else
        log.info("mcp register: pruning stale registration for " .. server_name)
        M.remove(server_name, function(_)
          cb(true)
        end)
      end
    end)
  else
    log.info("mcp register: port mismatch for " .. server_name .. ", pruning")
    M.remove(server_name, function(_)
      cb(true)
    end)
  end
end

---@param server_name string
---@param url string
---@param token string
---@param cb fun(ok: boolean, err: string|nil)
function M.add(server_name, url, token, cb)
  local port = url_port(url)
  local function do_add()
    async.spawn(
      {
        "cortex",
        "mcp",
        "add",
        server_name,
        url,
        "--transport",
        "http",
        "-H",
        "Authorization: Bearer " .. token,
      },
      { timeout = 30000 },
      function(obj)
        if obj.code ~= 0 then
          local err = (obj.stderr or "") ~= "" and obj.stderr or "cortex mcp add failed"
          log.error("mcp add failed: " .. err)
          cb(false, err)
          return
        end
        log.info("mcp add succeeded for " .. server_name)
        cb(true, nil)
      end
    )
  end

  if port then
    prune_stale(server_name, port, function(_)
      do_add()
    end)
  else
    do_add()
  end
end

---@param server_name string
---@param cb fun(ok: boolean)
function M.remove(server_name, cb)
  async.spawn({ "cortex", "mcp", "remove", server_name }, { timeout = 30000 }, function(obj)
    if obj.code ~= 0 then
      log.warn("mcp remove failed: " .. (obj.stderr or ""))
    else
      log.info("mcp remove succeeded for " .. server_name)
    end
    cb(true)
  end)
end

return M
