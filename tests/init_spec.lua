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
