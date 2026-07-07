--- coco.nvim REST auth helper (Phase 4).

local json = require("coco.util.json")
local toml = require("coco.util.toml")

local M = {}

---@return string|nil pat
function M.get_pat()
  for _, var in ipairs({ "SNOWFLAKE_TOKEN", "SNOWFLAKE_PAT", "CORTEX_TOKEN", "CORTEX_PAT" }) do
    local v = vim.env[var]
    if v and v ~= "" then
      return v
    end
  end

  local home = vim.env.HOME or ""

  local toml_path = home .. "/.snowflake/connections.toml"
  local fd = io.open(toml_path, "r")
  if fd then
    local data = fd:read("*a")
    fd:close()
    local active = M.config_active_connection() or "default"
    local values = toml.section_values(data, active)
    if values.token or values.pat then
      return values.token or values.pat
    end
  end

  local mcp_path = home .. "/.snowflake/cortex/mcp.json"
  local mcp_fd = io.open(mcp_path, "r")
  if mcp_fd then
    local raw = mcp_fd:read("*a")
    mcp_fd:close()
    local ok, mcp_data = json.decode(raw)
    if ok and mcp_data and mcp_data.mcpServers then
      for _, server in pairs(mcp_data.mcpServers) do
        local auth = server.headers and server.headers.Authorization or ""
        local token = auth:match("^Bearer%s+(%S+)$")
        if token then
          return token
        end
      end
    end
  end

  return nil
end

---@return string|nil
function M.config_active_connection()
  local ok, conn = pcall(function()
    return require("coco.config").get().snowflake.connection
  end)
  return ok and conn or nil
end

return M
