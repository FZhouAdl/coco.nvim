--- coco.nvim JSON-RPC 2.0 framing (Phase 2).

local M = {}

--- Encode a JSON-RPC 2.0 message for HTTP transport with Content-Length.
---@param msg table
---@return string
function M.write_frame(msg)
  local ok, json = pcall(vim.json.encode, msg)
  if not ok then
    return ""
  end
  return "Content-Length: " .. tostring(#json) .. "\r\n\r\n" .. json
end

--- Read the first JSON-RPC frame from an HTTP body string.
--- Returns the parsed message and any unconsumed tail.
---@param buf string
---@return table|nil msg
---@return string|nil tail
---@return string|nil err
function M.read_frame(buf)
  if type(buf) ~= "string" or buf == "" then
    return nil, buf, nil
  end
  local header_end = buf:find("\r\n\r\n", 1, true)
  if not header_end then
    return nil, buf, nil
  end
  local headers = buf:sub(1, header_end - 1)
  local len = headers:match("Content%-Length:%s*(%d+)")
  if not len then
    return nil, "", "missing Content-Length"
  end
  len = tonumber(len)
  local body_start = header_end + 4
  local body_end = body_start + len - 1
  if #buf < body_end then
    return nil, buf, nil
  end
  local body = buf:sub(body_start, body_end)
  local tail = buf:sub(body_end + 1)
  if tail == "" then
    tail = nil
  end
  local ok, obj = pcall(vim.json.decode, body, { object = true, array = true })
  if not ok then
    return nil, "", "parse error"
  end
  return obj, tail, nil
end

--- Parse a raw JSON string into a Lua value.
---@param str string
---@return table|nil
function M.parse(str)
  local ok, obj = pcall(vim.json.decode, str, { object = true, array = true })
  if not ok then
    return nil
  end
  return obj
end

---@param id any
---@param result any
---@return table
function M.make_response(id, result)
  return { jsonrpc = "2.0", id = id, result = result }
end

---@param id any
---@param code number
---@param message string
---@return table
function M.make_error(id, code, message)
  return { jsonrpc = "2.0", id = id, error = { code = code, message = message } }
end

--- Standard JSON-RPC error codes.
M.PARSE_ERROR = -32700
M.INVALID_REQUEST = -32600
M.METHOD_NOT_FOUND = -32601
M.INVALID_PARAMS = -32602
M.INTERNAL_ERROR = -32603

return M
