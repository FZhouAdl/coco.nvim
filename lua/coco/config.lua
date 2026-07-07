---@diagnostic disable: inject-field
-- coco.nvim configuration
-- Default values mirror the table in docs/coco-neovim-v2.md §9.

local M = {}

---@class CocoConfigCli
---@field cmd string
---@field args string[]
---@field auto_start boolean
---@field mcp_tool_timeout_ms number

---@class CocoConfigTransport
---@field terminal boolean
---@field mcp boolean
---@field rest { enabled: boolean }

---@class CocoConfigMcp
---@field host string
---@field port number
---@field server_name string
---@field token_bytes number
---@field max_body_bytes number

---@class CocoConfigSnowflakeObjectCache
---@field size number
---@field ttl_ms number

---@class CocoConfigSnowflake
---@field connection string|nil
---@field role string|nil
---@field warehouse string|nil
---@field show_cost boolean
---@field auto_object_context boolean
---@field object_cache CocoConfigSnowflakeObjectCache

---@class CocoConfigUiTerminal
---@field provider "auto"|"snacks"|"native"
---@field position "left"|"right"|"top"|"bottom"
---@field width number

---@class CocoConfigUiDiff
---@field keymaps boolean

---@class CocoConfigUi
---@field terminal CocoConfigUiTerminal
---@field diff CocoConfigUiDiff
---@field virtual_text boolean
---@field statusline boolean

---@class CocoConfigPermissions
---@field mode "confirm"|"plan"|"bypass"
---@field confirm { openDiff: boolean, saveDocument: boolean }

---@class CocoConfigContext
---@field selection_debounce_ms number

---@class CocoConfigLog
---@field level "debug"|"info"|"warn"|"error"
---@field file string

---@class CocoConfig
---@field cli CocoConfigCli
---@field transport CocoConfigTransport
---@field mcp CocoConfigMcp
---@field snowflake CocoConfigSnowflake
---@field ui CocoConfigUi
---@field permissions CocoConfigPermissions
---@field context CocoConfigContext
---@field log CocoConfigLog

---@type CocoConfig
local defaults = {
  cli = {
    cmd = "cortex",
    args = {},
    auto_start = false,
    mcp_tool_timeout_ms = 300000,
  },
  transport = {
    terminal = true,
    mcp = true,
    rest = { enabled = false },
  },
  mcp = {
    host = "127.0.0.1",
    port = 0,
    server_name = "coco-nvim",
    token_bytes = 16,
    max_body_bytes = 262144,
  },
  snowflake = {
    connection = nil,
    role = nil,
    warehouse = nil,
    show_cost = true,
    auto_object_context = true,
    object_cache = { size = 32, ttl_ms = 300000 },
  },
  ui = {
    terminal = { provider = "auto", position = "right", width = 0.4 },
    diff = { keymaps = true },
    virtual_text = true,
    statusline = true,
  },
  permissions = {
    mode = "confirm",
    confirm = { openDiff = true, saveDocument = true },
  },
  context = { selection_debounce_ms = 50 },
  log = {
    level = "info",
    file = vim.fn.stdpath("cache") .. "/coco.log",
  },
}

local config ---@type CocoConfig

local function warn(msg)
  vim.schedule(function()
    vim.notify("[coco] " .. msg, vim.log.levels.WARN)
  end)
end

local function validate(cfg)
  if type(cfg.cli) ~= "table" then
    cfg.cli = vim.deepcopy(defaults.cli)
    warn("invalid cli config; using defaults")
  end
  if type(cfg.cli.cmd) ~= "string" then
    cfg.cli.cmd = defaults.cli.cmd
    warn("cli.cmd must be a string")
  end
  if type(cfg.cli.args) ~= "table" then
    cfg.cli.args = vim.deepcopy(defaults.cli.args)
    warn("cli.args must be a table")
  end
  if type(cfg.cli.auto_start) ~= "boolean" then
    cfg.cli.auto_start = defaults.cli.auto_start
    warn("cli.auto_start must be a boolean")
  end
  if type(cfg.cli.mcp_tool_timeout_ms) ~= "number" then
    cfg.cli.mcp_tool_timeout_ms = defaults.cli.mcp_tool_timeout_ms
    warn("cli.mcp_tool_timeout_ms must be a number")
  end

  if type(cfg.transport) ~= "table" then
    cfg.transport = vim.deepcopy(defaults.transport)
    warn("invalid transport config; using defaults")
  end
  if type(cfg.transport.terminal) ~= "boolean" then
    cfg.transport.terminal = defaults.transport.terminal
    warn("transport.terminal must be a boolean")
  end
  if type(cfg.transport.mcp) ~= "boolean" then
    cfg.transport.mcp = defaults.transport.mcp
    warn("transport.mcp must be a boolean")
  end
  if type(cfg.transport.rest) ~= "table" then
    cfg.transport.rest = vim.deepcopy(defaults.transport.rest)
    warn("transport.rest must be a table")
  end
  if type(cfg.transport.rest.enabled) ~= "boolean" then
    cfg.transport.rest.enabled = defaults.transport.rest.enabled
    warn("transport.rest.enabled must be a boolean")
  end

  if type(cfg.mcp) ~= "table" then
    cfg.mcp = vim.deepcopy(defaults.mcp)
    warn("invalid mcp config; using defaults")
  end
  if type(cfg.mcp.host) ~= "string" then
    cfg.mcp.host = defaults.mcp.host
    warn("mcp.host must be a string")
  end
  if cfg.mcp.host ~= "127.0.0.1" then
    warn("mcp.host forced to 127.0.0.1 for security")
    cfg.mcp.host = "127.0.0.1"
  end
  if type(cfg.mcp.port) ~= "number" then
    cfg.mcp.port = defaults.mcp.port
    warn("mcp.port must be a number")
  end
  if type(cfg.mcp.server_name) ~= "string" then
    cfg.mcp.server_name = defaults.mcp.server_name
    warn("mcp.server_name must be a string")
  end
  if type(cfg.mcp.token_bytes) ~= "number" then
    cfg.mcp.token_bytes = defaults.mcp.token_bytes
    warn("mcp.token_bytes must be a number")
  end
  if type(cfg.mcp.max_body_bytes) ~= "number" then
    cfg.mcp.max_body_bytes = defaults.mcp.max_body_bytes
    warn("mcp.max_body_bytes must be a number")
  end

  if type(cfg.snowflake) ~= "table" then
    cfg.snowflake = vim.deepcopy(defaults.snowflake)
    warn("invalid snowflake config; using defaults")
  end
  if cfg.snowflake.connection ~= nil and type(cfg.snowflake.connection) ~= "string" then
    cfg.snowflake.connection = nil
    warn("snowflake.connection must be nil or a string")
  end
  if cfg.snowflake.role ~= nil and type(cfg.snowflake.role) ~= "string" then
    cfg.snowflake.role = nil
    warn("snowflake.role must be nil or a string")
  end
  if cfg.snowflake.warehouse ~= nil and type(cfg.snowflake.warehouse) ~= "string" then
    cfg.snowflake.warehouse = nil
    warn("snowflake.warehouse must be nil or a string")
  end
  if type(cfg.snowflake.show_cost) ~= "boolean" then
    cfg.snowflake.show_cost = defaults.snowflake.show_cost
    warn("snowflake.show_cost must be a boolean")
  end
  if type(cfg.snowflake.auto_object_context) ~= "boolean" then
    cfg.snowflake.auto_object_context = defaults.snowflake.auto_object_context
    warn("snowflake.auto_object_context must be a boolean")
  end
  if type(cfg.snowflake.object_cache) ~= "table" then
    cfg.snowflake.object_cache = vim.deepcopy(defaults.snowflake.object_cache)
    warn("snowflake.object_cache must be a table")
  end

  if type(cfg.ui) ~= "table" then
    cfg.ui = vim.deepcopy(defaults.ui)
    warn("invalid ui config; using defaults")
  end

  local valid_modes = { confirm = true, plan = true, bypass = true }
  if type(cfg.permissions) ~= "table" then
    cfg.permissions = vim.deepcopy(defaults.permissions)
    warn("invalid permissions config; using defaults")
  end
  if not valid_modes[cfg.permissions.mode] then
    cfg.permissions.mode = defaults.permissions.mode
    warn("permissions.mode must be confirm|plan|bypass")
  end
  if type(cfg.permissions.confirm) ~= "table" then
    cfg.permissions.confirm = vim.deepcopy(defaults.permissions.confirm)
    warn("permissions.confirm must be a table")
  end

  if type(cfg.context) ~= "table" then
    cfg.context = vim.deepcopy(defaults.context)
    warn("invalid context config; using defaults")
  end
  if type(cfg.context.selection_debounce_ms) ~= "number" then
    cfg.context.selection_debounce_ms = defaults.context.selection_debounce_ms
    warn("context.selection_debounce_ms must be a number")
  end

  if type(cfg.log) ~= "table" then
    cfg.log = vim.deepcopy(defaults.log)
    warn("invalid log config; using defaults")
  end
  local valid_levels = { debug = true, info = true, warn = true, error = true }
  if not valid_levels[cfg.log.level] then
    cfg.log.level = defaults.log.level
    warn("log.level must be debug|info|warn|error")
  end
  if type(cfg.log.file) ~= "string" then
    cfg.log.file = defaults.log.file
    warn("log.file must be a string")
  end
end

--- Replace the current configuration.
---@param opts CocoConfig|table|nil
function M.setup(opts)
  opts = opts or {}
  if vim.g.coco_opts and type(vim.g.coco_opts) == "table" then
    opts = vim.tbl_deep_extend("force", vim.deepcopy(vim.g.coco_opts), opts)
  end
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  validate(config)
end

--- Return the current configuration.
---@return CocoConfig
function M.get()
  if not config then
    M.setup({})
  end
  return config
end

--- Reset configuration (mostly useful in tests).
function M.reset()
  config = nil
end

return M
