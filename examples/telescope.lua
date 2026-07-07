-- coco.nvim with telescope.nvim as the optional picker.
require("coco").setup({
  ui = {
    terminal = { provider = "auto", position = "right", width = 0.4 },
    diff = { keymaps = true },
    statusline = true,
  },
})

-- Optional: override the picker to use telescope.
-- (Core pickers currently use vim.ui.select; telescope/fzf-lua integrations
-- are auto-detected when available.)
