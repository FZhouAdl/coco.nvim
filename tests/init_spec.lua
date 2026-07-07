local coco = require("coco")

describe("coco", function()
  it("loads without error", function()
    assert.is_not_nil(coco)
    assert.is_function(coco.setup)
  end)

  it("setup accepts empty opts", function()
    coco.setup({})
    assert.is_not_nil(require("coco.config").get())
  end)
end)

describe("config", function()
  local config = require("coco.config")

  before_each(function()
    config.reset()
  end)

  it("forces mcp host to 127.0.0.1", function()
    config.setup({ mcp = { host = "0.0.0.0" } })
    assert.equals("127.0.0.1", config.get().mcp.host)
  end)

  it("falls back on invalid transport.rest.enabled", function()
    config.setup({ transport = { rest = { enabled = "yes" } } })
    assert.is_false(config.get().transport.rest.enabled)
  end)

  it("clamps out-of-range numeric config values", function()
    config.setup({
      mcp = { port = 99999, token_bytes = 2, max_body_bytes = -1 },
      snowflake = { object_cache = { size = -5, ttl_ms = -100 } },
      ui = { terminal = { width = 1.5 } },
      cli = { mcp_tool_timeout_ms = 0 },
      context = { selection_debounce_ms = -1 },
    })
    assert.equals(0, config.get().mcp.port)
    assert.equals(16, config.get().mcp.token_bytes)
    assert.equals(262144, config.get().mcp.max_body_bytes)
    assert.equals(32, config.get().snowflake.object_cache.size)
    assert.equals(300000, config.get().snowflake.object_cache.ttl_ms)
    assert.equals(0.4, config.get().ui.terminal.width)
    assert.equals(300000, config.get().cli.mcp_tool_timeout_ms)
    assert.equals(50, config.get().context.selection_debounce_ms)
  end)
end)

describe("placeholders", function()
  local placeholders = require("coco.context.placeholders")

  it("leaves plain text unchanged", function()
    assert.equals("hello world", placeholders.expand("hello world", {}))
  end)

  it("expands @this when selection text is provided", function()
    local ctx = { selection = { text = "selected code" } }
    assert.equals("explain selected code", placeholders.expand("explain @this", ctx))
  end)

  it("expands @this to cursor description when selection text is empty", function()
    local ctx = { selection = { text = "", filePath = "/tmp/x.lua", startLine = 3, startCol = 5 } }
    local out = placeholders.expand("explain @this", ctx)
    assert.is_truthy(out:find("cursor at"))
    assert.is_truthy(out:find("x.lua"))
  end)

  it("expands @buffer from provided buffers context", function()
    local ctx = { buffers = { { filePath = "/tmp/a.lua", modified = false } } }
    local out = placeholders.expand("context: @buffer", ctx)
    assert.is_truthy(out:find("/tmp/a.lua") or out == "context: ")
  end)

  it("reports no diagnostics when context diagnostics are empty", function()
    local ctx = { diagnostics = {} }
    assert.equals("fix No diagnostics.", placeholders.expand("fix @diagnostics", ctx))
  end)

  it("disambiguates @buffers from @buffer", function()
    local ctx = {
      buffers = {
        { filePath = "/tmp/a.lua", modified = false },
        { filePath = "/tmp/b.lua", modified = true },
      },
    }
    local out = placeholders.expand("open: @buffers", ctx)
    assert.is_truthy(out:find("/tmp/a.lua"))
    assert.is_truthy(out:find("/tmp/b.lua"))
    assert.is_falsy(out:find("@buffer"))
  end)
end)

describe("state", function()
  local state = require("coco.session.state")

  before_each(function()
    state.reset()
  end)

  it("starts inactive", function()
    assert.equals("inactive", state.get().phase)
  end)

  it("transitions through start -> cli_ready -> active", function()
    state.dispatch({ type = "start" })
    assert.equals("starting", state.get().phase)
    state.dispatch({ type = "cli_ready" })
    state.dispatch({ type = "active" })
    assert.equals("active", state.get().phase)
    assert.is_true(state.get().transport.terminal)
  end)

  it("increments counters", function()
    state.dispatch({ type = "counter", name = "mcp_requests_total" })
    assert.equals(1, state.get().counters.mcp_requests_total)
  end)
end)
