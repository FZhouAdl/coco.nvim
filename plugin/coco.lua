-- coco.nvim plugin loader
-- This file is sourced by Neovim at startup; keep it tiny and lazy-load the rest.

if vim.g.loaded_coco then
  return
end
vim.g.loaded_coco = true

vim.api.nvim_create_user_command("Coco", function()
  require("coco.plugin.commands").register()
  vim.cmd("Coco")
end, { desc = "Toggle CoCo (lazy-load)" })

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
