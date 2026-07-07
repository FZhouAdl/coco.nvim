local auth = require("coco.rest.auth")
local rest = require("coco.rest.client")
local sse = require("coco.rest.sse")
local compact = require("coco.context.compact")
local virt = require("coco.ui.virt")

describe("rest auth", function()
  local orig_home
  local tmp_home

  before_each(function()
    orig_home = vim.env.HOME
    tmp_home = vim.fn.tempname()
    vim.fn.mkdir(tmp_home, "p")
    vim.fn.mkdir(tmp_home .. "/.snowflake", "p")
    vim.env.HOME = tmp_home
    for _, var in ipairs({ "SNOWFLAKE_TOKEN", "SNOWFLAKE_PAT", "CORTEX_TOKEN", "CORTEX_PAT" }) do
      vim.env[var] = nil
    end
  end)

  after_each(function()
    vim.env.HOME = orig_home
    for _, var in ipairs({ "SNOWFLAKE_TOKEN", "SNOWFLAKE_PAT", "CORTEX_TOKEN", "CORTEX_PAT" }) do
      vim.env[var] = nil
    end
  end)

  it("reads PAT from environment", function()
    vim.env.SNOWFLAKE_TOKEN = "env-token"
    assert.equals("env-token", auth.get_pat())
  end)

  it("reads PAT from connections.toml", function()
    local fd = io.open(tmp_home .. "/.snowflake/connections.toml", "w")
    fd:write("[default]\n")
    fd:write('account = "xyz123"\n')
    fd:write('token = "toml-token"\n')
    fd:close()
    assert.equals("toml-token", auth.get_pat())
  end)

  it("reads PAT from [connections.default] section", function()
    local fd = io.open(tmp_home .. "/.snowflake/connections.toml", "w")
    fd:write("[connections.default]\n")
    fd:write('account = "xyz123"\n')
    fd:write('pat = "dotted-token"\n')
    fd:close()
    assert.equals("dotted-token", auth.get_pat())
  end)

  it("does not treat password= as a PAT", function()
    local fd = io.open(tmp_home .. "/.snowflake/connections.toml", "w")
    fd:write("[default]\n")
    fd:write('account = "xyz123"\n')
    fd:write('password = "not-a-pat"\n')
    fd:close()
    assert.is_nil(auth.get_pat())
  end)

  it("reads PAT from cortex mcp.json", function()
    vim.fn.mkdir(tmp_home .. "/.snowflake/cortex", "p")
    local fd = io.open(tmp_home .. "/.snowflake/cortex/mcp.json", "w")
    fd:write([[{"mcpServers":{"test-srv":{"url":"http://127.0.0.1:9999/mcp","type":"http","headers":{"Authorization":"Bearer mcp-json-token"}}}}]])
    fd:close()
    assert.equals("mcp-json-token", auth.get_pat())
  end)

  it("falls back to connections.toml for account", function()
    vim.env.SNOWFLAKE_ACCOUNT = nil
    local fd = io.open(tmp_home .. "/.snowflake/connections.toml", "w")
    fd:write("[connections.myconn]\n")
    fd:write('account = "tomlaccount"\n')
    fd:write('token = "secret"\n')
    fd:close()
    require("coco.config").setup({ snowflake = { connection = "myconn" } })
    assert.equals("tomlaccount", rest._get_account())
  end)

  it("reads account from config.toml via settings.json connection name", function()
    vim.env.SNOWFLAKE_ACCOUNT = nil
    vim.fn.mkdir(tmp_home .. "/.snowflake/cortex", "p")
    local settings_fd = io.open(tmp_home .. "/.snowflake/cortex/settings.json", "w")
    settings_fd:write('{"cortexAgentConnectionName": "mantel"}')
    settings_fd:close()
    local fd = io.open(tmp_home .. "/.snowflake/config.toml", "w")
    fd:write("[connections.mantel]\n")
    fd:write('account = "lfyzskf-cmdsolutions"\n')
    fd:write('user = "test"\n')
    fd:close()
    local rest2 = require("coco.rest.client")
    require("coco.config").reset()
    assert.equals("lfyzskf-cmdsolutions", rest2._get_account())
  end)
end)

describe("sse parser", function()
  it("parses a simple event", function()
    local parser = sse.new()
    local events = parser:feed("data: hello\n\n")
    assert.equals(1, #events)
    assert.equals("message", events[1].event)
    assert.equals("hello", events[1].data)
  end)

  it("handles [DONE]", function()
    local parser = sse.new()
    local events = parser:feed("data: [DONE]\n\n")
    assert.equals(1, #events)
    assert.equals("[DONE]", events[1].data)
  end)

  it("handles \\r\\n line endings", function()
    local parser = sse.new()
    local events = parser:feed("data: first\r\n\r\ndata: second\r\n\r\n")
    assert.equals(2, #events)
    assert.equals("first", events[1].data)
    assert.equals("second", events[2].data)
  end)

  it("reassembles split chunks", function()
    local parser = sse.new()
    local events = {}
    vim.list_extend(events, parser:feed("data: hel"))
    vim.list_extend(events, parser:feed("lo\n\n"))
    assert.equals(1, #events)
    assert.equals("hello", events[1].data)
  end)

  it("stores last event id", function()
    local parser = sse.new()
    parser:feed("id: 42\ndata: x\n\n")
    assert.equals("42", parser:last_event_id())
  end)

  it("caps unbounded buffer growth", function()
    local parser = sse.new()
    local huge = string.rep("x", 1024 * 1024 + 1)
    local events = parser:feed(huge)
    assert.equals(0, #events)
    local more = parser:feed("data: hello\n\n")
    assert.equals(0, #more)
  end)
end)

describe("context compaction", function()
  it("preserves system + last 10 turns within budget", function()
    local history = {
      { role = "system", content = "You are helpful." },
    }
    for i = 1, 1000 do
      table.insert(history, { role = "user", content = "turn " .. i })
      table.insert(history, { role = "assistant", content = "reply " .. i })
    end

    local result = compact.compact(history, 4000)
    assert.equals("system", result[1].role)

    local latest_count = 0
    for _, turn in ipairs(result) do
      if turn.role == "user" or turn.role == "assistant" then
        latest_count = latest_count + 1
      end
    end
    -- 990 older user+assistant turns summarized into one system summary + 10 latest turns.
    assert.equals(10, latest_count)

    local total_tokens = 0
    for _, turn in ipairs(result) do
      local content = turn.content or turn.text or ""
      if type(content) == "table" then
        content = vim.inspect(content)
      end
      total_tokens = total_tokens + math.ceil(#tostring(content) / 4) + 4
    end
    assert.is_true(total_tokens <= 4000)
  end)
end)

describe("virt completion", function()
  before_each(function()
    virt.clear()
  end)

  it("starts and updates ghost text", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    virt.start_completion("foo")
    local cur = virt.current_completion()
    assert.is_not_nil(cur)
    assert.equals("foo", cur.text)

    virt.update_completion("foobar")
    cur = virt.current_completion()
    assert.equals("foobar", cur.text)

    virt.cancel_completion()
    assert.is_nil(virt.current_completion())
  end)

  it("accepts multi-line ghost text without corrupting the buffer", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "function ()" })
    vim.api.nvim_win_set_cursor(0, { 1, #"function ()" })

    virt.start_completion("\n  body\nend")
    virt.accept_completion()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("function ()", lines[1])
    assert.equals("  body", lines[2])
    assert.equals("end", lines[3])
  end)
end)

describe("editor context", function()
  it("retrieves visual selection text from live positions", function()
    local editor = require("coco.context.editor")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello world", "foo bar" })

    local text = editor.get_visual_selection_text(1, 7, 2, 9)
    assert.equals("world\nfoo bar", text)
  end)
end)
