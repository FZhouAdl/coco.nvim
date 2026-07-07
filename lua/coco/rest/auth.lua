--- coco.nvim REST auth helper (Phase 4).

local M = {}

---@return string|nil pat
function M.get_pat()
  -- Environment variables.
  for _, var in ipairs({ "SNOWFLAKE_TOKEN", "SNOWFLAKE_PAT", "CORTEX_TOKEN", "CORTEX_PAT" }) do
    local v = vim.env[var]
    if v and v ~= "" then
      return v
    end
  end

  -- connections.toml in ~/.snowflake/.
  local home = vim.env.HOME or ""
  local toml_path = home .. "/.snowflake/connections.toml"
  local fd = io.open(toml_path, "r")
  if not fd then
    return nil
  end
  local data = fd:read("*a")
  fd:close()

  local active = M.config_active_connection() or "default"
  local in_section = false
  for line in data:gmatch("[^\r\n]+") do
    local section = line:match("^%s*%[(.-)%]%s*$")
    if section then
      in_section = section == active
    elseif in_section then
      local token = line:match("^%s*token%s*=%s*[%\"']?([^%\"']+)[%\"']?%s*$")
      if token and token ~= "" then
        return token
      end
      local pat = line:match("^%s*pat%s*=%s*[%\"']?([^%\"']+)[%\"']?%s*$")
      if pat and pat ~= "" then
        return pat
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
