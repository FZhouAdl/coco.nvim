# Code Review — coco.nvim (Snowflake Cortex Code bridge)

**Scope**: full plugin implementation, ~3,946 lines of Lua across 30 files under `lua/coco/` + `plugin/coco.lua`.

**Method**: 10 parallel finder angles (line-scan, missing-guard, cross-file, Lua/Nvim pitfalls, wrapper/proxy, reuse, simplification, efficiency, altitude, conventions) → verified each surviving candidate by reading the enclosing function. All entries below are **CONFIRMED** by quoting the actual code unless marked otherwise.

Ranked most-severe first. Correctness / security bugs before cleanup findings.

---

## 1. `lua/coco/rest/client.lua:60` — `parse_sse_event` is a nil global; REST streaming crashes on the first SSE chunk

```lua
-- inside M.complete's stdout callback (line 57–66):
for _, ev in ipairs(parser:feed(data)) do
  local delta = parse_sse_event(ev)   -- line 60
...
-- declared AFTER, at line 81:
local function parse_sse_event(ev)
```

Lua `local` scope begins at the declaration. The closure at line 17–77 captures `parse_sse_event` as a global, which is never assigned, so the very first parsed SSE event calls `nil`. Because the throw happens inside `vim.system`'s stdout callback, it is silently swallowed — the buffer stays on "Thinking…" forever and no error surfaces to the user.

**Failure scenario**: any user with `transport.rest.enabled = true` runs `:CocoAsk` or `:CocoComplete`. The stream stalls indefinitely on the first `data:` line.

**Fix**: hoist `local function parse_sse_event` above `M.complete`, or forward-declare `local parse_sse_event` at the top of the file.

---

## 2. `lua/coco/rest/auth.lua:46` — `config_active_connection` leaks to `_G` and is not accessible via the module

```lua
function config_active_connection()      -- line 46 — no `local`, no `M.`
```

The function is created as `_G.config_active_connection`. `rest/client.lua:117` calls `auth.config_active_connection()` — that field on the required module is `nil`, so the call throws `attempt to call a nil value (field 'config_active_connection')`.

**Failure scenario**: `SNOWFLAKE_ACCOUNT` unset, user has a valid `~/.snowflake/connections.toml`. `M._get_account()` reaches line 117 and crashes; the REST path is dead for every user relying on the TOML for account discovery.

**Fix**: prefix with `M.` (or `local`), and change `client.lua:117` to `auth.M.config_active_connection()` accordingly. The same shape (`function foo` with no `local`) appears at `context/snowflake.lua:117` (`parse_result`) — fix all three.

---

## 3. `lua/coco/mcp/tools.lua:315-346` — `openFile` + `saveDocument` are an arbitrary-file R/W primitive to any MCP peer

```lua
-- openFile handler, line 328–329:
vim.cmd("edit " .. vim.fn.fnameescape(args.filePath))
-- saveDocument default config (config.lua:108):
confirm = { openDiff = false, saveDocument = false },
```

`filePath` has zero validation — no workspace jail, no scheme guard, no realpath check. A caller can pass `/etc/passwd`, `~/.ssh/id_rsa`, or a scheme like `term://bash` to load privileged files or spawn a shell inside Neovim. Combined with `saveDocument`'s default no-confirm, a compromised or hostile MCP peer can then overwrite any user-writable file (dotfiles, shell rc, ssh config).

**Failure scenario**: peer holding the bearer token issues `openFile { filePath = "~/.ssh/authorized_keys" }` then `saveDocument` with attacker-controlled content in the buffer.

**Fix**: canonicalize `filePath` (`vim.fs.normalize` + `vim.uv.fs_realpath`), reject when it escapes the workspace root, reject buffer-scheme paths, and turn on `saveDocument`/`openDiff` confirm by default.

---

## 4. `lua/coco/session/manager.lua:20-28` — deterministic MCP bearer token when `/dev/urandom` is unavailable

```lua
if not fd then
  local parts = {}
  for _ = 1, bytes do
    table.insert(parts, string.format("%02x", math.random(0, 255)))
  end
```

`math.random` is never seeded (no `math.randomseed` anywhere in the repo). Lua initializes it to a constant, so every Neovim launch on Windows / sandboxed environments (no `/dev/urandom`) produces the **same** hex token.

**Failure scenario**: Windows/WSL/container user. Any local process on 127.0.0.1 predicts the token and hits `POST /mcp` with `Authorization: Bearer <known>` → full MCP tool access (`openFile`, `saveDocument`, `openDiff`, arbitrary file R/W per finding #3).

**Fix**: use `vim.uv.random(bytes)` (libuv CSPRNG, cross-platform) and drop the fallback entirely.

---

## 5. `lua/coco/rest/auth.lua:36-38` — Snowflake account **password** silently used as a Bearer PAT

```lua
local pwd = line:match("^%s*password%s*=%s*[\"']?([^\"']+)[\"']?%s*$")
if pwd and pwd ~= "" then
  return pwd
end
```

`get_pat()` falls back to the `password` field and returns it unchanged. `client.lua:50` then sends it as `Authorization: Bearer <password>`.

**Failure scenario**: user has only `password=` in `connections.toml` (typical for legacy auth). Their account password is transmitted in the `Authorization` header to Snowflake — not a PAT, so any proxy/log/401-echo path leaks the raw password, and it grants far more privilege than a scoped PAT was designed for.

**Fix**: only accept fields explicitly named PATs/tokens; on a bare `password=`, return `nil` with a warning.

---

## 6. `lua/coco/context/placeholders.lua:59-79` + `lua/coco/context/snowflake.lua:110` — `@object:` placeholder always returns "pending"; also spawns cascading `cortex` processes

```lua
-- placeholders.lua:75
vim.wait(2000, function() return done end, 10)
-- snowflake.lua:110 (synchronous fallthrough after fetch())
cb(nil, { pending = true, message = "lookup pending; retry shortly" })
```

`snowflake.lookup` fires the callback **synchronously** with a `pending` sentinel *before* starting the background fetch. The placeholder handler sets `done = true` immediately and `vim.wait` exits at once, so `result` is `"[object <name> lookup pending; retry shortly]"` every time. The real metadata is never awaited on this call, and there is no in-flight dedup, so N `@object:X` placeholders in one prompt or N poll retries fan out into N concurrent `cortex search` subprocesses hitting Snowflake.

**Failure scenario**: user types `@object:MY_TABLE` in `:CocoAsk`; submitted prompt contains the "pending" string, never the metadata. Rapid re-runs or `auto_object_context` on hot paths cause credit-burning stampedes.

**Fix**: track pending futures in `snowflake.lookup` keyed by `cache_key(name)`; queue additional callers onto the first spawn. Have the placeholder path actually block until the fetch completes (or defer expansion to the streaming layer).

---

## 7. `lua/coco/context/placeholders.lua:30-43` — `@buffer` runs before `@buffers` and matches inside it

```lua
prompt = prompt:gsub("@buffer", function() ... end)   -- line 30
prompt = prompt:gsub("@buffers", function() ... end)  -- line 37
```

`gsub("@buffer", ...)` matches `@buffer` as a substring of `@buffers` (no anchor / word boundary), so `"Summarize @buffers now"` first becomes `"Summarize <entire-current-buffer>s now"` — the trailing `s` glued to code — and the `@buffers` (metadata list) handler never fires.

**Failure scenario**: any prompt using `@buffers` produces a corrupted whole-buffer dump instead of the list-of-buffers summary.

**Fix**: expand longest tokens first, or use a single pattern with a word boundary `@(buffers?)`.

---

## 8. `lua/coco/context/editor.lua:44-45` — visual selection columns are always overwritten with 1 / end-of-current-line

```lua
if mode:match("[vV\22]") then
  ...  -- sl, el computed correctly
end
sc = 1                                      -- line 44 — unconditional
ec = #vim.api.nvim_get_current_line()       -- line 45 — unconditional
```

Whatever the visual mode produced is thrown away. `getCurrentSelection` reports `startCol=1, endCol=len(currentLine)` regardless of what the user highlighted (charwise/blockwise/multi-line V-selection).

**Failure scenario**: user visually selects columns 5–20 across lines 3–10. Tool returns `startCol=1, endCol=<len of line 10>`. The agent then re-anchors edits on the wrong span.

**Fix**: move the `sc = 1; ec = #...` block into the `else` branch (non-visual mode). Use `vim.fn.getpos("v")` / `vim.fn.getpos(".")` `[3]` columns for the visual branch (or `vim.fn.getregion` on Nvim ≥ 0.10, which also handles blockwise correctly).

---

## 9. `lua/coco/context/editor.lua:124` — `pcall(vim.fn.system, ...)` never errors; `git_root` becomes the "fatal" error string

```lua
local ok, root = pcall(vim.fn.system, { "git", "-C", cwd, "rev-parse", "--show-toplevel" })
if ok and root and root ~= "" then
  git_root = vim.trim(root)
end
```

`vim.fn.system` returns the combined stdout+stderr and sets `v:shell_error` on failure — it does not throw. So in a non-git directory, `ok=true`, `root="fatal: not a git repository (or any parent up to mount point ...)\n"`, and `git_root` is set to that message string.

**Failure scenario**: agent calls `getWorkspaceInfo` outside a git repo → the reported `git_root` is a shell error string. Any downstream logic that treats a truthy `git_root` as a valid path breaks.

**Fix**: check `vim.v.shell_error == 0` instead of `pcall`, or use `vim.fs.root(0, ".git")` (Nvim 0.10+) which is both correct and non-blocking.

---

## 10. `lua/coco/mcp/handler.lua:39-41` — JSON-RPC notifications get answered with an error (protocol violation)

```lua
elseif method == "notifications/initialized" then
  cb(nil)
...
else
  cb(jsonrpc.make_error(req.id, jsonrpc.METHOD_NOT_FOUND, ...))
end
```

Only `notifications/initialized` is special-cased. Any other notification (per JSON-RPC 2.0 §4.1, a request without `id`) falls into the `else` branch and receives `{jsonrpc:"2.0", id:nil, error:{code:-32601,...}}`. Notifications MUST NOT be answered.

**Failure scenario**: Cortex client sends `{jsonrpc:"2.0", method:"notifications/cancelled", params:{...}}` (no `id`). Server responds with an error object; strict clients reject as malformed, loose clients log a spurious error.

**Fix**: if `req.id == nil`, invoke `cb(nil)` unconditionally after any side-effects. Otherwise route as today.

---

## 11. `lua/coco/mcp/tools.lua:337-338` — `nvim_buf_set_mark` rejects `<` / `>` names; `openFile` with a range returns `OPEN_FAILED` despite succeeding

```lua
vim.api.nvim_buf_set_mark(0, "<", line, col - 1, {})
vim.api.nvim_buf_set_mark(0, ">", end_line, end_col - 1, {})
```

The Nvim API accepts only `a-z`, `A-Z`, `0-9` for user marks. `<` and `>` are auto-set visual marks and are rejected by `nvim_buf_set_mark`. The surrounding `pcall` catches it and returns `err_result("OPEN_FAILED", ...)`.

**Failure scenario**: MCP `openFile { filePath, startLine, endLine }` — `:edit` and cursor placement succeed, but the mark call errors and the whole tool returns failure. Agent sees a false failure and may retry indefinitely.

**Fix**: either drop the marks (`:edit` + `nvim_win_set_cursor` is enough for navigation) or use a normal mark like `"a"`/`"b"`, or set visual marks via `vim.fn.setpos("'<", ...)`.

---

## 12. `lua/coco/mcp/register.lua:113-127` — MCP bearer token is passed on argv to `cortex mcp add`, visible to every local process

```lua
async.spawn({
  "cortex", "mcp", "add", server_name, url,
  "--transport", "http",
  "-H", "Authorization: Bearer " .. token,   -- token in argv
}, ...)
```

argv is world-readable via `ps -ef` / `/proc/<pid>/cmdline` while `cortex mcp add` runs. The whole point of a per-session bearer is that it should not be observable — argv defeats that. It also lands in shell history / CLI audit logs if the CLI records invocations.

**Failure scenario**: on a shared dev host or container sidecar, another user runs `ps auxf` during the ~1s registration window and pockets the token. Once captured, all findings above (arbitrary file R/W, etc.) become exploitable.

**Fix**: write the header via stdin, an env var (`CORTEX_MCP_BEARER=`), or a file the CLI reads with `--token-file`. Do not put secrets on argv.

---

## 13. `lua/coco/context/snowflake.lua:143` — truncation loop has an unreachable break arm; kept output grows unbounded, and each iteration is O(n)

```lua
if not in_columns or #table.concat(kept, "\n") < cap - 4096 then
  table.insert(kept, line)
else
  break
end
```

The `break` fires only when `in_columns == true` **and** size ≥ cap-4096. If the CLI output doesn't contain a `Column`/`COLUMN NAME` header line (view definitions, non-English output, JSON with different wording), `in_columns` stays `false` for the whole loop and every line is appended — the advertised cap is silently defeated. Separately, `#table.concat(kept, "\n")` rebuilds the entire kept string on every iteration → O(n²) in line count, easily hundreds of ms of main-loop stall on a 300 KB dump.

**Failure scenario**: `cortex search table-details` returns 300 KB of view DDL with no `Column` marker. `parse_result` returns the entire 300 KB, blowing past the 51,200-byte cap that `mcp/tools.lua` relies on and UI-freezing for a noticeable window.

**Fix**: track running byte total in a scalar (`used = used + #line + 1`), test `used > cap - 4096` unconditionally, break when exceeded.

---

## 14. `lua/coco/mcp/tools.lua:230-238` — `getDiagnostics` response shape flips from array-of-items to a summary object under the same key

```lua
local items = editor.diagnostics(args.uri)
local json = encode(items)
local truncated = false
if #json > 51200 then
  truncated = true
  items = { truncated = true, count = #items, message = "..." }
end
cb(ok_result({ diagnostics = items, truncated = truncated }))
```

On the happy path `diagnostics` is `{{filePath=..., line=..., ...}, ...}`; on truncation it's `{truncated=true, count=N, message=...}`. Callers iterating `result.diagnostics` as an array break at exactly the size where truncation semantics matter.

**Failure scenario**: TS/Rust monorepo with 1,000 diagnostics. The CLI's diagnostics renderer iterates `for _, d in ipairs(diagnostics)` and blows up, silently dropping the payload.

**Fix**: keep `diagnostics` always an array; put truncation metadata in a sibling field (`items`, `total`, `omitted`). Better: cap early during collection instead of encoding and discarding.

---

## 15. `lua/coco/ui/input.lua:52-66` — full-buffer rewrite on every SSE chunk during streaming

```lua
for i, part in ipairs(parts) do
  if i == 1 then
    lines[line_count] = lines[line_count] .. part
  ...
end
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)   -- redraw ALL
```

Every streamed chunk (dozens per response) redraws the entire buffer, and the accumulator uses `lines[k] = lines[k] .. part` on Lua strings (immutable). Together this is O(n²) in stream length. `M.complete` at line 140 has the same shape (`text .. (chunk.text or "")` → `virt.update_completion`).

**Failure scenario**: a 20 KB streamed answer causes visible UI stutter and CPU spike for the duration of the stream; ghost-text completion for a 200-token suggestion runs the extmark rewrite 200 times over an ever-growing string.

**Fix**: keep a "current-line" scalar and only rewrite the last line via `nvim_buf_set_lines(bufnr, -2, -1, false, {current})`; append full lines with `nvim_buf_set_lines(bufnr, -1, -1, false, {new_line})`.

---

## Also worth attention (below the 15-item cap, but real)

These verified but did not make the top 15:

- **`context/snowflake.lua:19-20`** — TTL cache uses wall-clock `os.time()*1000`; NTP jumps invalidate the whole cache or extend stale entries. Prefer `vim.uv.hrtime() / 1e6`.
- **`context/snowflake.lua:32-49`** — `prune_cache` builds `keys` via `pairs`, whose order is unspecified, and evicts `keys[1]` — comment claims "LRU by insertion order" but eviction target is effectively random.
- **`mcp/tools.lua:157`** — `call_id = os.time() .. "_" .. math.random(1000000)`; unseeded `math.random` + 1s resolution → collision risk when two tool calls arrive in the same second.
- **`mcp/server.lua:280`** — server accepts `opts.host` verbatim; the 127.0.0.1 lock lives only in `config.validate`. Any future caller (test harness, hot-reload) bypassing config exposes the endpoint on every interface. Defense-in-depth: assert loopback at the bind site too.
- **`session/manager.lua:118-128`** — `M.stop` dispatches `stopped` synchronously at line 127 while `register.remove`'s async callback (which calls `server.stop()`) is still in flight. `:CocoStop` followed quickly by `:CocoStart` can have the late callback kill the newly-started MCP server. Also `probe_handle` (line 15) is declared but never assigned — the cancel branch at line 123 is dead code.
- **`ui/virt.lua:65-75`** — `accept_completion` indexes `[1]` on `nvim_buf_get_lines` result without a nil guard; if the target line was deleted between suggestion and accept, `#nil` throws.
- **`context/compact.lua:65-90`** — `remaining = budget - used - latest_tokens` is clamped to 0, but the code still appends every latest turn verbatim. If latest exceeds budget, the returned history overflows the caller's cap.
- **`plugin/coco.lua`** — only `:Coco` is created eagerly; every other documented command (`:CocoStart`, `:CocoAsk`, etc.) requires `setup()` to have run or `:Coco` to have been invoked once. Users following "add plugin and run `:CocoStart`" hit `E492: Not an editor command`.
- **`ui/select.lua:11-21`** — snacks branch is a `-- TODO` stub; the `pcall(require, 'snacks.picker')` check is dead code and always falls through to `vim.ui.select`.
- **`config.lua:119-139`** — `clone` + `deep_extend` re-implement `vim.deepcopy` + `vim.tbl_deep_extend('force', ...)`; the custom version diverges on list-valued keys (recurses into numeric indices while stdlib overwrites arrays wholesale), so behavior can silently drift from every other Nvim plugin.
- **`context/editor.lua:124`** (efficiency) — synchronous `vim.fn.system('git', ...)` on the main loop; on a slow/networked FS this blocks Neovim for 50–300 ms per `getWorkspaceInfo` call.

## What was checked and looked clean

- **HTTP framing & auth path** (`mcp/server.lua`) — bearer check runs on every request path; body size cap enforced before parse; idle timer scheduled via `vim.schedule_wrap`; `secure_eq` uses constant-time compare.
- **SSE parser** (`rest/sse.lua`) — correctly buffers partial lines across chunks and handles `\r\n`.
- **CLAUDE.md conventions** — no repo-level or ancestor CLAUDE.md governs the Lua code, so no convention violations to flag.
- **CHANGELOG-stated invariants** (127.0.0.1 bind, 5s idle, 32-conn cap, 413 cap, 50 KB truncation, `Authorization` redaction, ≥ Neovim 0.10, 10-min cost cache) are all correctly wired in code.
