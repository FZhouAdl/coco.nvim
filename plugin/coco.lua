-- coco.nvim plugin loader
-- This file is sourced by Neovim at startup; keep it tiny and lazy-load the rest.

if vim.g.loaded_coco then
  return
end
vim.g.loaded_coco = true

-- Eagerly register all user-facing commands as thin stubs that load the real
-- handlers on first use. This avoids "Not an editor command" for users who
-- run :CocoStart before :Coco.
local command_specs = {
  { name = "Coco", nargs = 0 },
  { name = "CocoStart", nargs = "*" },
  { name = "CocoStop", nargs = 0 },
  { name = "CocoFocus", nargs = 0 },
  { name = "CocoAsk", nargs = "?" },
  { name = "CocoSend", nargs = "?" },
  { name = "CocoAdd", nargs = "?" },
  { name = "CocoConnection", nargs = 0 },
  { name = "CocoSelectModel", nargs = 0 },
  { name = "CocoMode", nargs = "?" },
  { name = "CocoComplete", nargs = 0 },
  { name = "CocoStatus", nargs = 0 },
  { name = "CocoHealth", nargs = 0 },
  { name = "CocoDiffAccept", nargs = 0 },
  { name = "CocoDiffDeny", nargs = 0 },
  { name = "CocoCloseAllDiffs", nargs = 0 },
}

local function lazy_register(name)
  return function(opts)
    require("coco.plugin.commands").register()
    if opts.args and opts.args ~= "" then
      vim.cmd(name .. " " .. opts.args)
    else
      vim.cmd(name)
    end
  end
end

for _, spec in ipairs(command_specs) do
  vim.api.nvim_create_user_command(spec.name, lazy_register(spec.name), {
    nargs = spec.nargs,
    desc = "CoCo command (lazy-load)",
  })
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("CocoCleanup", { clear = true }),
  callback = function()
    local ok, state = pcall(require, "coco.session.state")
    if ok and state.get().phase ~= "inactive" then
      local ok2, manager = pcall(require, "coco.session.manager")
      if ok2 and manager.stop then
        manager.stop()
      end
    end
  end,
})
