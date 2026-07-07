--- coco.nvim command registration.

local api = require("coco")

local M = {}

function M.register()
  vim.api.nvim_create_user_command("CocoStart", function(args)
    local opts = {}
    for _, arg in ipairs(vim.split(args.args, "%s+", { trimempty = true })) do
      if arg == "--resume" or arg == "--continue" then
        opts.resume = true
      end
    end
    api.start(opts)
  end, { nargs = "*", desc = "Start a CoCo session" })

  vim.api.nvim_create_user_command("CocoStop", function()
    api.stop()
  end, { desc = "Stop the CoCo session" })

  vim.api.nvim_create_user_command("Coco", function()
    api.toggle()
  end, { desc = "Toggle the CoCo terminal" })

  vim.api.nvim_create_user_command("CocoFocus", function()
    api.focus()
  end, { desc = "Focus the CoCo terminal" })

  vim.api.nvim_create_user_command("CocoAsk", function(args)
    api.ask(args.args ~= "" and args.args or nil)
  end, { nargs = "?", desc = "Ask CoCo (with placeholder expansion)" })

  vim.api.nvim_create_user_command("CocoSend", function(args)
    api.send(args.args)
  end, { nargs = "?", desc = "Send text to CoCo" })

  vim.api.nvim_create_user_command("CocoAdd", function(args)
    local parts = vim.split(args.args, "%s+", { trimempty = true })
    local path = parts[1]
    local l1 = tonumber(parts[2])
    local l2 = tonumber(parts[3])
    api.add(path, l1, l2)
  end, { nargs = "?", desc = "Add file/range to context" })

  vim.api.nvim_create_user_command("CocoConnection", function()
    api.connection()
  end, { desc = "Switch Snowflake connection" })

  vim.api.nvim_create_user_command("CocoSelectModel", function()
    api.select_model()
  end, { desc = "Select CoCo model" })

  vim.api.nvim_create_user_command("CocoMode", function(args)
    api.mode(args.args ~= "" and args.args or nil)
  end, { nargs = "?", desc = "Cycle/set CoCo permission mode" })

  vim.api.nvim_create_user_command("CocoStatus", function()
    api.status()
  end, { desc = "Show CoCo session status" })

  vim.api.nvim_create_user_command("CocoHealth", function()
    vim.cmd("checkhealth coco")
  end, { desc = "Run :checkhealth coco" })

  vim.api.nvim_create_user_command("CocoDiffAccept", function()
    local ok, id = pcall(vim.api.nvim_buf_get_var, 0, "coco_diff_id")
    if ok and id then
      require("coco.ui.diff").accept(id)
    else
      vim.notify("[coco] no diff in current buffer", vim.log.levels.WARN)
    end
  end, { desc = "Accept the current CoCo diff" })

  vim.api.nvim_create_user_command("CocoDiffDeny", function()
    local ok, id = pcall(vim.api.nvim_buf_get_var, 0, "coco_diff_id")
    if ok and id then
      require("coco.ui.diff").deny(id)
    else
      vim.notify("[coco] no diff in current buffer", vim.log.levels.WARN)
    end
  end, { desc = "Deny the current CoCo diff" })

  vim.api.nvim_create_user_command("CocoCloseAllDiffs", function()
    require("coco.ui.diff").close_all()
  end, { desc = "Close all CoCo diff tabs" })
end

return M
