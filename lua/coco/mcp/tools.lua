--- coco.nvim MCP tool registry (Phase 2).

local editor = require("coco.context.editor")
local snowflake = require("coco.context.snowflake")
local diff_ui = require("coco.ui.diff")
local state = require("coco.session.state")
local async = require("coco.util.async")
local log = require("coco.util.log")

local M = {}

---@class CocoToolSchema
---@field type "object"
---@field properties table
---@field required string[]|nil
---@field additionalProperties boolean|nil

---@class CocoTool
---@field schema CocoToolSchema
---@field handler fun(args: table, cb: fun(result: table))

local registry = {} ---@type table<string, CocoTool>

local SCHEMA_VIOLATION = "SCHEMA_VIOLATION"
local DIFF_IN_FLIGHT = "DIFF_IN_FLIGHT"
local OUTSIDE_WORKSPACE = "OUTSIDE_WORKSPACE"

local call_counter = 0

--- Canonicalize and validate a file path for MCP file tools.
--- Returns canonical path or nil, error message.
---@param raw string
---@return string|nil
---@return string|nil
local function validate_file_path(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil, "filePath must be a non-empty string"
  end
  -- Reject URI schemes and shell meta-characters.
  if raw:match("^[a-zA-Z][a-zA-Z0-9+-.]*://") then
    return nil, "filePath must be a filesystem path"
  end
  local normalized = vim.fs.normalize(raw)
  -- Reject relative traversal outside cwd.
  if normalized:find("%.%.") then
    return nil, "filePath contains disallowed traversal"
  end
  local real = vim.uv.fs_realpath(normalized)
  if not real then
    return nil, "filePath does not exist: " .. normalized
  end
  local cwd = vim.fn.getcwd()
  local rel = vim.fs.relpath(cwd, real)
  if not rel then
    return nil, "filePath outside workspace"
  end
  if rel:find("^%.%.") then
    return nil, "filePath outside workspace"
  end
  return real, nil
end

--- Encode a result for an MCP text content item.
---@param obj any
---@return string
local function encode(obj)
  local ok, json = pcall(vim.json.encode, obj)
  return ok and json or tostring(obj)
end

--- Build a successful tool result.
---@param obj any
---@return table
local function ok_result(obj)
  return {
    content = { { type = "text", text = encode(obj) } },
  }
end

--- Build an error tool result.
---@param code string
---@param message string
---@return table
local function err_result(code, message)
  return {
    isError = true,
    content = { { type = "text", text = encode({ code = code, message = message }) } },
  }
end

--- Validate arguments against a JSON-schema-lite definition.
---@param args table
---@param schema CocoToolSchema
---@return boolean ok
---@return string|nil err
local function validate(args, schema)
  if type(args) ~= "table" then
    return false, "arguments must be an object"
  end
  if schema.type ~= "object" then
    return false, "unsupported schema root"
  end
  local props = schema.properties or {}
  if schema.additionalProperties == false then
    for k, _ in pairs(args) do
      if props[k] == nil then
        return false, "unknown field: " .. k
      end
    end
  end
  for k, prop in pairs(props) do
    if prop.type then
      local v = args[k]
      if v ~= nil then
        local t = type(v)
        local expected = prop.type
        if expected == "integer" then
          if t ~= "number" or math.floor(v) ~= v then
            return false, k .. " must be an integer"
          end
        elseif expected == "number" and t ~= "number" then
          return false, k .. " must be a number"
        elseif expected == "string" and t ~= "string" then
          return false, k .. " must be a string"
        elseif expected == "boolean" and t ~= "boolean" then
          return false, k .. " must be a boolean"
        elseif expected == "array" and t ~= "table" then
          return false, k .. " must be an array"
        end
      end
    end
    if prop.enum then
      local v = args[k]
      if v ~= nil then
        local found = false
        for _, ev in ipairs(prop.enum) do
          if ev == v then
            found = true
            break
          end
        end
        if not found then
          return false, k .. " has invalid enum value"
        end
      end
    end
  end
  if schema.required then
    for _, name in ipairs(schema.required) do
      if args[name] == nil then
        return false, "missing required field: " .. name
      end
    end
  end
  return true, nil
end

--- Register a tool.
---@param name string
---@param schema CocoToolSchema
---@param handler fun(args: table, cb: fun(result: table))
function M.register(name, schema, handler)
  registry[name] = { schema = schema, handler = handler }
end

--- Return a tools/list style schema table.
---@return table[]
function M.list()
  local items = {}
  for name, tool in pairs(registry) do
    table.insert(items, { name = name, description = tool.schema.description or name, inputSchema = tool.schema })
  end
  return items
end

--- Dispatch a tool call.
---@param call { name: string, arguments: table }
---@param cb fun(result: table)
function M.dispatch(call, cb)
  state.dispatch({ type = "counter", name = "tool_calls_total", delta = 1 })
  local tool = registry[call.name]
  if not tool then
    state.dispatch({ type = "counter", name = "tool_errors_total", delta = 1 })
    cb(err_result("TOOL_NOT_FOUND", "tool not found: " .. tostring(call.name)))
    return
  end
  local ok, verr = validate(call.arguments or {}, tool.schema)
  if not ok then
    state.dispatch({ type = "counter", name = "tool_errors_total", delta = 1 })
    cb(err_result(SCHEMA_VIOLATION, verr))
    return
  end
  call_counter = call_counter + 1
  local call_id = tostring(vim.uv.hrtime()) .. "_" .. tostring(call_counter)
  state.dispatch({ type = "tool_start", id = call_id, tool = call.name, started = math.floor(vim.uv.hrtime() / 1e6) })
  local finish_called = false
  local function finish(result)
    if finish_called then
      return
    end
    finish_called = true
    state.dispatch({ type = "tool_done", id = call_id })
    if result and result.isError then
      state.dispatch({ type = "counter", name = "tool_errors_total", delta = 1 })
    end
    cb(result)
  end
  local hok, herr = pcall(tool.handler, call.arguments or {}, finish)
  if not hok then
    state.dispatch({ type = "tool_done", id = call_id })
    state.dispatch({ type = "counter", name = "tool_errors_total", delta = 1 })
    log.error("tool " .. call.name .. " handler error: " .. tostring(herr))
    finish(err_result("INTERNAL_ERROR", tostring(herr)))
  end
end

--- Reset the registry (useful in tests).
function M.reset()
  registry = {}
end

--- Expose path validation for tests.
M._validate_file_path = validate_file_path

-- Built-in tool handlers -----------------------------------------------------

M.register("getCurrentSelection", {
  type = "object",
  properties = {},
  additionalProperties = false,
}, function(_, cb)
  async.schedule(function()
    cb(ok_result(editor.selection()))
  end)
end)

M.register("getLatestSelection", {
  type = "object",
  properties = {},
  additionalProperties = false,
}, function(_, cb)
  async.schedule(function()
    cb(ok_result(editor.selection()))
  end)
end)

M.register("getOpenEditors", {
  type = "object",
  properties = {},
  additionalProperties = false,
}, function(_, cb)
  async.schedule(function()
    cb(ok_result(editor.open_buffers()))
  end)
end)

M.register("getWorkspaceInfo", {
  type = "object",
  properties = {},
  additionalProperties = false,
}, function(_, cb)
  async.schedule(function()
    cb(ok_result(editor.workspace_info()))
  end)
end)

M.register("getDiagnostics", {
  type = "object",
  properties = {
    uri = { type = "string" },
  },
  additionalProperties = false,
}, function(args, cb)
  async.schedule(function()
    local items = editor.diagnostics(args.uri)
    local cap = 50
    local total = #items
    local truncated = total > cap
    if truncated then
      local kept = {}
      for i = 1, cap do
        table.insert(kept, items[i])
      end
      items = kept
    end
    cb(ok_result({ diagnostics = items, total = total, truncated = truncated }))
  end)
end)

M.register("checkDocumentDirty", {
  type = "object",
  properties = {
    filePath = { type = "string" },
  },
  required = { "filePath" },
  additionalProperties = false,
}, function(args, cb)
  async.schedule(function()
    local dirty = false
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(b)
      if name == args.filePath then
        dirty = vim.bo[b].modified
        break
      end
    end
    cb(ok_result({ filePath = args.filePath, dirty = dirty }))
  end)
end)

M.register("saveDocument", {
  type = "object",
  properties = {
    filePath = { type = "string" },
  },
  required = { "filePath" },
  additionalProperties = false,
}, function(args, cb)
  async.schedule(function()
    local path, verr = validate_file_path(args.filePath)
    if not path then
      cb(err_result(OUTSIDE_WORKSPACE, verr or "invalid filePath"))
      return
    end

    local function do_save()
      local saved = false
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(b) == path then
          local ok, err = pcall(vim.api.nvim_buf_call, b, function()
            vim.cmd("write")
          end)
          saved = ok
          if not ok then
            log.warn("saveDocument failed: " .. tostring(err))
          end
          break
        end
      end
      cb(ok_result({ filePath = path, saved = saved }))
    end

    if require("coco.config").get().permissions.confirm.saveDocument then
      vim.ui.select({ "Yes", "No" }, {
        prompt = "CoCo wants to save " .. path .. ": ",
      }, function(choice)
        if choice == "Yes" then
          do_save()
        else
          cb(err_result("USER_DENIED", "save denied by user"))
        end
      end)
      return
    end
    do_save()
  end)
end)

M.register("closeAllDiffTabs", {
  type = "object",
  properties = {},
  additionalProperties = false,
}, function(_, cb)
  async.schedule(function()
    diff_ui.close_all()
    cb(ok_result({ closed = true }))
  end)
end)

M.register("openFile", {
  type = "object",
  properties = {
    filePath = { type = "string" },
    startLine = { type = "integer" },
    startCol = { type = "integer" },
    endLine = { type = "integer" },
    endCol = { type = "integer" },
  },
  required = { "filePath" },
  additionalProperties = false,
}, function(args, cb)
  async.schedule(function()
    local path, verr = validate_file_path(args.filePath)
    if not path then
      cb(err_result(OUTSIDE_WORKSPACE, verr or "invalid filePath"))
      return
    end

    local ok, err = pcall(function()
      -- Find an existing window showing the file; otherwise open a new split
      -- to avoid disrupting the current layout.
      local target_win
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(w)
        if vim.api.nvim_buf_get_name(buf) == path then
          target_win = w
          break
        end
      end
      if target_win then
        vim.api.nvim_set_current_win(target_win)
      else
        vim.cmd("vsplit " .. vim.fn.fnameescape(path))
      end
      if args.startLine then
        local line = args.startLine
        local col = args.startCol or 1
        vim.api.nvim_win_set_cursor(0, { line, col - 1 })
        if args.endLine then
          local end_line = args.endLine
          local end_col = args.endCol or #vim.api.nvim_get_current_line()
          vim.fn.setpos("'<", { 0, line, col, 0 })
          vim.fn.setpos("'>", { 0, end_line, end_col, 0 })
        end
      end
    end)
    if ok then
      cb(ok_result({ opened = true }))
    else
      cb(err_result("OPEN_FAILED", tostring(err)))
    end
  end)
end)

M.register("getSnowflakeObject", {
  type = "object",
  properties = {
    name = { type = "string" },
  },
  required = { "name" },
  additionalProperties = false,
}, function(args, cb)
  snowflake.lookup_poll(args.name, function(err, result)
    if err then
      cb(err_result("LOOKUP_FAILED", err))
      return
    end
    cb(ok_result(result))
  end)
end)

M.register("openDiff", {
  type = "object",
  properties = {
    oldPath = { type = "string" },
    newPath = { type = "string" },
    newContents = { type = "string" },
    tabName = { type = "string" },
  },
  required = { "oldPath", "newPath", "newContents" },
  additionalProperties = false,
}, function(args, cb)
  async.schedule(function()
    local function do_open()
      local diffs = state.get().diffs
      if diffs[args.oldPath] and diffs[args.oldPath].status == "pending" then
        cb(err_result(DIFF_IN_FLIGHT, "diff already in flight for " .. args.oldPath))
        return
      end
      local id = diff_ui.open(args.oldPath, args.newPath, args.newContents, args.tabName)
      if id == "" then
        cb(err_result("DIFF_OPEN_FAILED", "failed to open diff"))
        return
      end
      cb(ok_result({ diffId = args.oldPath, status = "pending" }))
    end

    if require("coco.config").get().permissions.confirm.openDiff then
      vim.ui.select({ "Yes", "No" }, {
        prompt = "CoCo wants to open a diff for " .. args.oldPath .. ": ",
      }, function(choice)
        if choice == "Yes" then
          do_open()
        else
          cb(err_result("USER_DENIED", "diff denied by user"))
        end
      end)
      return
    end
    do_open()
  end)
end)

M.register("getDiffResult", {
  type = "object",
  properties = {
    diffId = { type = "string" },
  },
  required = { "diffId" },
  additionalProperties = false,
}, function(args, cb)
  async.schedule(function()
    local entry = state.get().diffs[args.diffId]
    if not entry then
      cb(err_result("DIFF_NOT_FOUND", "no diff with id " .. args.diffId))
      return
    end
    cb(ok_result({ diffId = args.diffId, status = entry.status }))
  end)
end)

return M
