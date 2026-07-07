# AGENTS.md — coco.nvim

Compact guidance for OpenCode sessions working in this repo.

## Project

Neovim plugin (Lua) bridging the Snowflake Cortex Code (`cortex`) CLI. Five implementation phases are complete; see `docs/coco-nvim-plan.md` and `CHANGELOG.md`.

## Development commands

```bash
make test          # run all Plenary tests (bootstraps plenary.nvim into .tests/)
make lint          # selene lua/ plugin/ tests/  (tool may not be installed)
make fmt           # stylua lua/ plugin/ tests/   (tool may not be installed)
make check         # fmt + lint + test
```

Run a single spec file:

```bash
nvim --headless -u tests/minimal.lua -c 'PlenaryBustedFile tests/rest_spec.lua' -c qa
```

CI: `.github/workflows/test.yml` runs `make test` on stable and nightly Neovim.

## Test setup

- `tests/minimal.lua` bootstraps `plenary.nvim` into `.tests/plenary.nvim/` (gitignored).
- New specs go in `tests/`. Follow the existing pattern: reset module/state in `before_each`.
- The project has no `stylua.toml` / `selene.toml` / `.luacheckrc`; use defaults.

## Architecture notes

- Entrypoint: `lua/coco/init.lua` → `setup()` registers commands.
- Commands are defined in `lua/coco/plugin/commands.lua`.
- Command stubs: `plugin/coco.lua` eagerly registers all `:Coco*` commands as thin stubs that load `lua/coco/plugin/commands.lua` on first use.
- State: TEA-style store in `lua/coco/session/state.lua`; dispatch messages, never mutate `state` directly.
- Async rule: any callback touching `vim.api` must be wrapped in `vim.schedule()` / `vim.schedule_wrap()`.
- No external Lua deps in core code paths; use `vim.loop`, `vim.system`, `vim.json`.

## Security-critical constraints

These are enforced in code and must stay enforced:

1. **MCP server binds only `127.0.0.1`**. The lock is in `config.lua` and is also asserted at bind time in `mcp/server.lua`; do not allow configurable public binds.
2. **Bearer tokens must never appear on argv**. `mcp/register.lua` writes the cortex `mcp.json` config file directly (including the `Authorization` header) and then runs `cortex mcp reconnect`, so the token is never passed on a command line.
3. **Do not use `password=` from `connections.toml` as a PAT**. `rest/auth.lua` only accepts fields explicitly named PATs/tokens; a bare `password=` returns `nil`.
4. **Redact secrets in logs**. `util/log.lua` redacts `Authorization:` and `*_PAT`/`*_TOKEN`/`*_KEY`/`*_SECRET` env values.
5. **File tool paths need workspace validation**. `openFile`/`saveDocument` in `mcp/tools.lua` normalize paths with `vim.fs.normalize` + `vim.uv.fs_realpath`, reject URI schemes and `..` traversal, and enforce that the real path is inside the current working directory.

## Known pitfalls (verified in `code-review.md`)

Read `code-review.md` before touching these areas. The highest-impact recurring issues are:

- **Lua local function ordering**: `rest/client.lua` called `parse_sse_event` before its `local function` declaration, causing nil-call crashes. Forward-declare or hoist local helpers.
- **Module vs global functions**: `rest/auth.lua:config_active_connection` and `context/snowflake.lua:parse_result` were declared as globals (`function foo`) instead of `M.foo` / `local function`. Always use `local` or attach to `M`.
- **Notifications vs requests in JSON-RPC**: `mcp/handler.lua` must not reply to notifications (`req.id == nil`).
- **`vim.fn.system` does not throw**: check `vim.v.shell_error`, not `pcall`, or use `vim.system`/`async.spawn`.
- **`nvim_buf_set_mark` rejects `<`/`>`**: use `vim.fn.setpos("'<", ...)` for visual marks or skip marks.
- **`math.random` is unseeded**: do not use for tokens/ids; prefer `vim.uv.random()` or `/dev/urandom`.
- **Placeholder ordering**: `@buffer` matches inside `@buffers`; expand longest tokens first or use anchored patterns.
- **SSE streaming UI**: rewriting the full buffer on every chunk is O(n²); append to the last line instead.
- **Cache TTL uses wall clock**: `os.time()*1000` is vulnerable to NTP jumps; prefer `vim.uv.hrtime()` for new code.

## Conventions

- Match existing module style: thin public API in `init.lua`, internals in submodules.
- Run `make test` after any change; the full suite currently passes 47 tests.
- Update `CHANGELOG.md` and `doc/coco.txt` when adding user-visible commands or behavior.
