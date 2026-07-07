# Changelog

All notable changes to `coco.nvim` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Phase 1 "Terminal Bridge (MVP)" implementation.
- Configuration system (`lua/coco/config.lua`) with validation, defaults from
  design §9, and `vim.g.coco_opts` merge.
- Utility modules: leveled logger with redaction, JSON wrappers, async spawn
  helpers (`lua/coco/util/{log,json,async}.lua`).
- Editor context primitives (`lua/coco/context/editor.lua`) and placeholder
  expansion (`lua/coco/context/placeholders.lua`) for `@this`, `@buffer`,
  `@buffers`, `@diagnostics`, `@marks`, `@quickfix`, `@visible`.
- TEA-style session state store (`lua/coco/session/state.lua`) with phases
  `inactive|starting|degraded|active|stopping` and counters.
- Terminal wrapper (`lua/coco/session/terminal.lua`) supporting snacks.nvim and
  native `:terminal` fallbacks.
- Session manager (`lua/coco/session/manager.lua`) that probes `cortex` on PATH
  and opens the CLI in a managed terminal, degrading gracefully when MCP is not
  yet available.
- Command registration (`lua/coco/plugin/commands.lua`) for `:CocoStart`,
  `:CocoStop`, `:Coco`, `:CocoFocus`, `:CocoAsk`, `:CocoSend`, `:CocoAdd`,
  `:CocoStatus`, `:CocoHealth`, and diff placeholders.
- Input UI (`lua/coco/ui/input.lua`) using snacks.input or `vim.ui.input`.
- Statusline component (`lua/coco/ui/statusline.lua`).
- Health check (`lua/coco/health.lua`) covering Neovim version, `cortex`
  presence, and optional deps.
- Plugin loader (`plugin/coco.lua`) with guarded lazy registration and
  `VimLeavePre` cleanup.
- Test bootstrap (`tests/minimal.lua`) that clones plenary.nvim into
  `.tests/plenary` when missing.
- Initial unit tests (`tests/init_spec.lua`) for config, placeholders, and
  state transitions.
- Stub modules for Phase 2/3/4 so every designed module can be `require`d.
- CI workflow (`.github/workflows/test.yml`) and `Makefile`.
- README.md skeleton with install and command reference.

- Phase 2 "MCP Server + Native Diffs" implementation.
- JSON-RPC 2.0 framing with Content-Length (`lua/coco/mcp/jsonrpc.lua`).
- Localhost HTTP MCP server on `vim.loop` (`lua/coco/mcp/server.lua`) with
  bearer-token auth, 5s idle timeout, 32-connection cap, 413 body-cap, and
  `X-Coco-Trace` headers.
- MCP request handler (`lua/coco/mcp/handler.lua`) for `initialize`,
  `tools/list`, and `tools/call`.
- Tool registry + JSON-schema-lite validator (`lua/coco/mcp/tools.lua`) with
  editor tools and diff tools wired.
- MCP registration lifecycle (`lua/coco/mcp/register.lua`) using
  `cortex mcp add/remove`, including stale-registration prune.
- Native diff review UI (`lua/coco/ui/diff.lua`) with accept/deny/close-all
  and `WinClosed` auto-reject.
- Session manager (`lua/coco/session/manager.lua`) now starts the MCP server,
  registers with `cortex`, and reports transport matrix `✅ ✅ ❌`.
- Observability counters, in-flight tool tracking, and 401 burst detection.
- `:checkhealth coco` now probes the active MCP port.
- Component tests (`tests/mcp_spec.lua`, `tests/diff_spec.lua`) covering
  JSON-RPC framing, server auth/routing, tool schema validation, and diff
  accept/reject.

### Notes
- Snowflake metadata, REST/SSE, and inline UI remain stubbed and will be
  implemented in Phases 3–4.
- The implementation follows `docs/coco-nvim-plan.md` and
  `docs/coco-neovim-v2.md` (design v2).

## [0.1.0] - Terminal Bridge (MVP)

_Planned._
- `:CocoStart`, `:Coco`, `:CocoAsk`, `:CocoSend`, `:CocoAdd`
- Terminal-wrapped `cortex` CLI with snacks.nvim/native fallback
- Placeholder expansion (`@this`, `@buffer`, `@diagnostics`, etc.)
- Statusline component and `:checkhealth coco`

## [0.2.0] - MCP Server + Native Diffs

_Planned._
- Localhost HTTP MCP server on `vim.loop`
- Editor tools: `openFile`, `openDiff`, `getCurrentSelection`, `getDiagnostics`, etc.
- Non-blocking diff review with hunk accept/reject

## [0.3.0] - Snowflake Context

_Planned._
- `@object:<NAME>` metadata injection
- Connection/role/warehouse discovery
- Cost feedback via `CORTEX_REST_API_USAGE_HISTORY`

## [0.4.0] - REST / Inline (Optional)

_Planned._
- Direct Cortex REST/SSE client
- Ghost-text completion and one-shot answers

## [1.0.0] - Polish

_Planned._
- Full test matrix, docs, packaging (lazy.nvim / vim.pack), threat-model verification

[Unreleased]: https://github.com/you/coco.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/you/coco.nvim/releases/tag/v0.1.0
[0.2.0]: https://github.com/you/coco.nvim/releases/tag/v0.2.0
[0.3.0]: https://github.com/you/coco.nvim/releases/tag/v0.3.0
[0.4.0]: https://github.com/you/coco.nvim/releases/tag/v0.4.0
[1.0.0]: https://github.com/you/coco.nvim/releases/tag/v1.0.0
