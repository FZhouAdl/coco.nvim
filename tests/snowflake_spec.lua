local connection = require("coco.snowflake.connection")
local snowflake = require("coco.context.snowflake")
local cost = require("coco.snowflake.cost")
local state = require("coco.session.state")
local statusline = require("coco.ui.statusline")
local placeholders = require("coco.context.placeholders")
local async = require("coco.util.async")

describe("snowflake connection", function()
  local original_spawn

  before_each(function()
    state.reset()
    original_spawn = async.spawn
  end)

  after_each(function()
    async.spawn = original_spawn
  end)

  it("parses json connection list", function()
    async.spawn = function(cmd, _, cb)
      if cmd[3] == "list" and cmd[4] == "--json" then
        cb({ code = 0, stdout = vim.json.encode({
          connections = {
            { name = "prod", active = true, role = "ADMIN", warehouse = "WH_PROD" },
            { name = "dev", active = false, role = "DEV", warehouse = "WH_DEV" },
          },
        }) })
      else
        cb({ code = 1, stderr = "unexpected" })
      end
    end

    local done = false
    local items
    connection.list(function(err, result)
      done = true
      items = result
    end)
    vim.wait(1000, function()
      return done
    end)
    assert.is_true(done)
    assert.equals(2, #items)
    assert.equals("prod", items[1].name)
    assert.equals("ADMIN", items[1].role)
    assert.equals("WH_PROD", items[1].warehouse)
    assert.equals("prod", state.get().connection)
    assert.equals("ADMIN", state.get().role)
  end)

  it("falls back to text connection list", function()
    async.spawn = function(cmd, _, cb)
      if cmd[3] == "list" and cmd[4] == "--json" then
        cb({ code = 1, stderr = "no json" })
      elseif cmd[3] == "list" then
        cb({ code = 0, stdout = "* prod ADMIN WH_PROD\n  dev DEV WH_DEV\n" })
      else
        cb({ code = 1, stderr = "unexpected" })
      end
    end

    local done = false
    local items
    connection.list(function(err, result)
      done = true
      items = result
    end)
    vim.wait(1000, function()
      return done
    end)
    assert.is_true(done)
    assert.equals(2, #items)
    assert.equals("prod", items[1].name)
    assert.is_true(items[1].active)
  end)

  it("set updates state and clears role/warehouse", function()
    state.dispatch({ type = "set_connection", connection = "old", role = "R", warehouse = "W" })
    async.spawn = function(_, _, cb)
      cb({ code = 0, stdout = "" })
    end

    local done = false
    connection.set("new", function(err)
      done = true
      assert.is_nil(err)
    end)
    vim.wait(1000, function()
      return done
    end)
    assert.equals("new", state.get().connection)
    assert.is_nil(state.get().role)
  end)
end)

describe("snowflake object lookup", function()
  local original_spawn

  before_each(function()
    state.reset()
    snowflake.clear()
    snowflake._set_clock_offset(0)
    original_spawn = async.spawn
    state.dispatch({ type = "set_connection", connection = "prod", role = "ADMIN", warehouse = "WH" })
  end)

  after_each(function()
    async.spawn = original_spawn
    snowflake._set_clock_offset(0)
  end)

  it("returns pending on cold lookup and caches result", function()
    local calls = 0
    async.spawn = function(cmd, _, cb)
      calls = calls + 1
      cb({ code = 0, stdout = vim.json.encode({ name = "ORDERS", columns = { "ID" } }) })
    end

    local result1
    snowflake.lookup("DB.SCHEMA.ORDERS", function(_, r)
      result1 = r
    end)
    vim.wait(500, function()
      return result1 ~= nil
    end)
    assert.is_not_nil(result1)
    assert.equals(true, result1.pending)

    -- Wait for background fetch.
    vim.wait(1000, function()
      return calls >= 1
    end)

    local result2
    snowflake.lookup("DB.SCHEMA.ORDERS", function(_, r)
      result2 = r
    end)
    assert.is_not_nil(result2)
    assert.equals("ORDERS", result2.name)
  end)

  it("evicts cache after ttl", function()
    async.spawn = function(_, _, cb)
      cb({ code = 0, stdout = vim.json.encode({ name = "X" }) })
    end

    snowflake.lookup("T", function() end)
    vim.wait(500, function()
      return true
    end)

    local first
    snowflake.lookup("T", function(_, r)
      first = r
    end)
    assert.equals("X", first.name)

    snowflake._set_clock_offset(400000)
    snowflake.lookup("T", function(_, r)
      first = r
    end)
    assert.equals(true, first.pending)
  end)
end)

describe("snowflake cost", function()
  local original_spawn

  before_each(function()
    state.reset()
    cost.clear()
    original_spawn = async.spawn
  end)

  after_each(function()
    async.spawn = original_spawn
  end)

  it("parses json cost and caches", function()
    async.spawn = function(cmd, _, cb)
      cb({ code = 0, stdout = vim.json.encode({ rows = { { CREDITS = 12.4 } } }) })
    end

    local done = false
    local credits
    cost.latest(function(err, c)
      done = true
      credits = c
    end)
    vim.wait(1000, function()
      return done
    end)
    assert.is_true(done)
    assert.equals(12.4, credits)
    assert.equals(12.4, state.get().credits)

    -- Second call should use cache without spawning.
    async.spawn = function()
      error("should not be called")
    end
    local credits2
    cost.latest(function(_, c)
      credits2 = c
    end)
    assert.equals(12.4, credits2)
  end)
end)

describe("object placeholder", function()
  local original_spawn

  before_each(function()
    state.reset()
    snowflake.clear()
    original_spawn = async.spawn
    state.dispatch({ type = "set_connection", connection = "prod", role = "ADMIN", warehouse = "WH" })
  end)

  after_each(function()
    async.spawn = original_spawn
  end)

  it("expands @object:<NAME> from cache", function()
    async.spawn = function(_, _, cb)
      cb({ code = 0, stdout = vim.json.encode({ name = "ORDERS", columns = { "ID" } }) })
    end

    -- Pre-warm cache.
    snowflake.lookup("DB.SCHEMA.ORDERS", function() end)
    vim.wait(500, function()
      return true
    end)

    local expanded = placeholders.expand("summarize @object:DB.SCHEMA.ORDERS", {})
    assert.is_truthy(expanded:find("ORDERS"))
  end)
end)

describe("statusline credits", function()
  before_each(function()
    state.reset()
  end)

  it("shows credits when enabled", function()
    state.dispatch({ type = "start" })
    state.dispatch({ type = "active" })
    state.dispatch({ type = "set_credits", credits = 7.5 })
    local comp = statusline.component()
    assert.is_truthy(comp:find("~7%.5"))
  end)

  it("hides credits when inactive", function()
    state.dispatch({ type = "set_credits", credits = 7.5 })
    local comp = statusline.component()
    assert.equals("", comp)
  end)
end)
