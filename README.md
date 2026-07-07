# coco.nvim

A Neovim bridge for the **Snowflake Cortex Code** (`cortex`) CLI.

> Work in progress. Phase 3 (Snowflake context) is being implemented.

## Install (lazy.nvim)

```lua
{
  "you/coco.nvim",
  opts = {}
}
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

See `docs/coco-neovim-v2.md` for the full design.

## Development

```bash
make test
```
