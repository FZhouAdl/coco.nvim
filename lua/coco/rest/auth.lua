--- coco.nvim REST auth helper (Phase 4).

local toml = require("coco.util.toml")

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
  local values = toml.section_values(data, active)
  -- Explicit PAT/token fields only; never treat a bare password= as a PAT.
  return values.token or values.pat or nil
end

---@return string|nil
function M.config_active_connection()
  local ok, conn = pcall(function()
    return require("coco.config").get().snowflake.connection
  end)
  return ok and conn or nil
end

return M
