-- coco.nvim with snacks.nvim terminal/input/picker integration.
require("coco").setup({
  ui = {
    terminal = { provider = "snacks", position = "right", width = 0.4 },
    diff = { keymaps = true },
    virtual_text = true,
    statusline = true,
  },
  permissions = {
    mode = "confirm",
    confirm = { openDiff = true, saveDocument = false },
  },
})
