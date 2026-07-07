--- coco.nvim command registration.

local api = require("coco")

local M = {}

---@type table<string, fun(args: table)>
local handlers = {}

function M.register()
  handlers.CocoStart = function(args)
    local opts = {}
    for _, arg in ipairs(vim.split(args.args, "%s+", { trimempty = true })) do
      if arg == "--resume" or arg == "--continue" then
        opts.resume = true
      end
    end
    api.start(opts)
  end

  handlers.CocoStop = function(_)
    api.stop()
  end

  handlers.Coco = function(_)
    api.toggle()
  end

  handlers.CocoFocus = function(_)
    api.focus()
  end

  handlers.CocoAsk = function(args)
    api.ask(args.args ~= "" and args.args or nil)
  end

  handlers.CocoSend = function(args)
    api.send(args.args)
  end

  handlers.CocoAdd = function(args)
    local parts = vim.split(args.args, "%s+", { trimempty = true })
    local path = parts[1]
    local l1 = tonumber(parts[2])
    local l2 = tonumber(parts[3])
    api.add(path, l1, l2)
  end

  handlers.CocoConnection = function(_)
    api.connection()
  end

  handlers.CocoSelectModel = function(_)
    api.select_model()
  end

  handlers.CocoMode = function(args)
    api.mode(args.args ~= "" and args.args or nil)
  end

  handlers.CocoComplete = function(_)
    api.complete()
  end

  handlers.CocoStatus = function(_)
    api.status()
  end

  handlers.CocoHealth = function(_)
    vim.cmd("checkhealth coco")
  end

  handlers.CocoDiffAccept = function(_)
    local ok, id = pcall(vim.api.nvim_buf_get_var, 0, "coco_diff_id")
    if ok and id then
      require("coco.ui.diff").accept(id)
    else
      vim.notify("[coco] no diff in current buffer", vim.log.levels.WARN)
    end
  end

  handlers.CocoDiffDeny = function(_)
    local ok, id = pcall(vim.api.nvim_buf_get_var, 0, "coco_diff_id")
    if ok and id then
      require("coco.ui.diff").deny(id)
    else
      vim.notify("[coco] no diff in current buffer", vim.log.levels.WARN)
    end
  end

  handlers.CocoCloseAllDiffs = function(_)
    require("coco.ui.diff").close_all()
  end

  for name, handler in pairs(handlers) do
    vim.api.nvim_create_user_command(name, handler, {
      nargs = name == "CocoStart" and "*" or (name == "CocoAsk" or name == "CocoSend" or name == "CocoAdd" or name == "CocoMode") and "?" or 0,
      desc = "CoCo command",
    })
  end
end

--- Invoke a registered command handler directly (used by lazy stubs).
---@param name string
---@param args table
function M.run(name, args)
  local handler = handlers[name]
  if handler then
    handler(args)
  end
end

return M
