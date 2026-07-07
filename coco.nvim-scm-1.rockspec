package = "coco.nvim"
version = "scm-1"
source = {
  url = "git://github.com/you/coco.nvim.git",
}
description = {
  summary = "Neovim bridge for the Snowflake Cortex Code CLI",
  detailed = [[
    coco.nvim provides a managed terminal wrapper for the Snowflake Cortex
    Code (cortex) CLI, a local MCP HTTP server with editor tools, Snowflake
    context injection, and an optional REST/SSE client for inline completions.
  ]],
  homepage = "https://github.com/you/coco.nvim",
  license = "MIT",
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  modules = {
    ["coco"] = "lua/coco/init.lua",
  },
  copy_directories = {
    "doc",
    "plugin",
  },
}
