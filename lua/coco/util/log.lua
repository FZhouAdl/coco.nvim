--- coco.nvim logging utility.

local M = {}

local cfg = { level = "info", file = "" }
local level_values = { debug = 0, info = 1, warn = 2, error = 3 }
local log_file

local function redact_line(line)
  -- Redact Authorization headers and known secret env names.
  line = line:gsub("(Authorization%s*:%s*Bearer%s+)%S+", "%1<redacted>")
  line = line:gsub("(Authorization=)()%S+", "%1<redacted>")
  for _, pat in ipairs({ "_PAT", "_TOKEN", "_KEY", "_SECRET" }) do
    line = line:gsub("([A-Za-z0-9_]" .. pat .. "%s*=)%S+", "%1<redacted>")
  end
  return line
end

local function log_at(level, msg)
  if level_values[level] < level_values[cfg.level] then
    return
  end
  local line = string.format("[%s] %s %s", level, os.date("%Y-%m-%d %H:%M:%S"), msg)
  line = redact_line(line)
  if cfg.file and cfg.file ~= "" then
    local ok, err = pcall(function()
      if not log_file then
        log_file = io.open(cfg.file, "a")
      end
      if log_file then
        log_file:write(line .. "\n")
        log_file:flush()
      end
    end)
    if not ok then
      -- Don't recurse into logging errors.
      vim.schedule(function()
        vim.notify("[coco] log write failed: " .. tostring(err), vim.log.levels.ERROR)
      end)
    end
  end
  if level_values[level] >= level_values.warn then
    vim.schedule(function()
      vim.notify(line, vim.log.levels[level:upper()] or vim.log.levels.INFO)
    end)
  end
end

--- Configure the logger.
---@param opts { level: string, file: string }
function M.setup(opts)
  cfg.level = opts.level or cfg.level
  cfg.file = opts.file or cfg.file
end

function M.debug(msg) log_at("debug", msg) end
function M.info(msg) log_at("info", msg) end
function M.warn(msg) log_at("warn", msg) end
function M.error(msg) log_at("error", msg) end

function M.get_level() return cfg.level end

return M
