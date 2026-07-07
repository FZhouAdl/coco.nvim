# coco.nvim

A Neovim bridge for the **Snowflake Cortex Code** (`cortex`) CLI.

> Phase 5 (polish, docs, packaging) is being finalized.

## Features

- Terminal-wrapped `cortex` CLI with snacks.nvim / native fallback
- Local MCP HTTP server exposing editor tools (selection, buffers, diagnostics,
  file open, diffs)
- Snowflake context: connections, `@object:<NAME>` metadata, cost feedback
- Optional REST/SSE client for one-shot answers and ghost-text completion

## Install

### lazy.nvim

```lua
{ "you/coco.nvim", opts = {} }
```

### vim.pack (Neovim >= 0.12)

```lua
vim.pack.add("you/coco.nvim")
require("coco").setup()
```

## Commands

| Command | Description |
|---------|-------------|
| `:CocoStart` | Start a CoCo session |
| `:CocoStop` | Stop the session |
| `:Coco` | Toggle the CoCo terminal |
| `:CocoAsk [prompt]` | Ask CoCo (placeholder expansion) |
| `:CocoSend [text]` | Send text to the terminal |
| `:CocoAdd <path> [l1] [l2]` | Add file/range to context |
| `:CocoStatus` | Show session status |
| `:CocoHealth` | Run `:checkhealth coco` |
| `:CocoDiffAccept` | Accept the current diff |
| `:CocoDiffDeny` | Deny the current diff |
| `:CocoCloseAllDiffs` | Close all diff tabs |
| `:CocoConnection` | Switch Snowflake connection |
| `:CocoSelectModel` | Select CoCo model |
| `:CocoMode [confirm|plan|bypass]` | Cycle/set permission mode |
| `:CocoComplete` | Trigger ghost-text completion |

## Configuration

```lua
require("coco").setup({
  cli = {
    cmd = "cortex",
    args = {},
    auto_start = false,
    mcp_tool_timeout_ms = 300000,
  },
  transport = {
    terminal = true,
    mcp = true,
    rest = { enabled = false },
  },
  mcp = {
    host = "127.0.0.1",
    port = 0,
    server_name = "coco-nvim",
    token_bytes = 16,
    max_body_bytes = 262144,
  },
  snowflake = {
    connection = nil,
    role = nil,
    warehouse = nil,
    show_cost = true,
    auto_object_context = true,
    object_cache = { size = 32, ttl_ms = 300000 },
  },
  ui = {
    terminal = { provider = "auto", position = "right", width = 0.4 },
    diff = { keymaps = true },
    virtual_text = true,
    statusline = true,
  },
  permissions = {
    mode = "confirm",
    confirm = { openDiff = true, saveDocument = true },
  },
  context = { selection_debounce_ms = 50 },
  log = { level = "info", file = vim.fn.stdpath("cache") .. "/coco.log" },
})
```

## Statusline

```vim
set statusline+=\ %{v:lua.require('coco.ui.statusline').component()}
```

Shows `connection · role · warehouse · model · ~credits` when active.

## Placeholders

`:CocoAsk` expands: `@this`, `@buffer`, `@buffers`, `@diagnostics`, `@marks`,
`@quickfix`, `@visible`, `@object:DB.SCHEMA.TABLE`.

## Examples

See `examples/` for minimal, snacks-enabled, and telescope-enabled configs.

## Development

```bash
make test
```

See `doc/coco.txt` for the full Vim help doc.
