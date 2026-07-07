-- Minimal init for headless tests.
-- Bootstraps plenary.nvim into .tests/plenary if missing.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

local test_deps = root .. "/.tests"
local plenary_path = test_deps .. "/plenary.nvim"

if vim.fn.isdirectory(plenary_path) == 0 then
  vim.fn.mkdir(test_deps, "p")
  local clone = vim.fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/nvim-lua/plenary.nvim.git",
    plenary_path,
  })
  if vim.v.shell_error ~= 0 then
    error("failed to clone plenary.nvim: " .. clone)
  end
end

vim.opt.runtimepath:prepend(plenary_path)

require("coco").setup({
  log = { level = "debug", file = vim.fn.stdpath("cache") .. "/coco-test.log" },
})
