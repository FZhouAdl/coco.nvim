describe("performance gates", function()
  it("cold require coco loads in <= 5ms", function()
    -- Measure fresh require in a child nvim process to avoid cache.
    local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
    local script = 'local t = vim.loop.hrtime(); require("coco"); local d = (vim.loop.hrtime() - t) / 1e6; print("COLD_REQUIRE_MS=" .. d); vim.cmd("qa!")'
    local stdout = {}
    local stderr = {}
    local done = false
    local stdout_pipe = vim.loop.new_pipe(false)
    local stderr_pipe = vim.loop.new_pipe(false)
    vim.loop.spawn("nvim", {
      args = { "--headless", "-u", "NONE", "-c", "set rtp+=" .. root, "-c", "lua " .. script },
      stdio = { nil, stdout_pipe, stderr_pipe },
    }, function()
      done = true
    end)
    stdout_pipe:read_start(function(err, data)
      if data then
        table.insert(stdout, data)
      end
    end)
    stderr_pipe:read_start(function(err, data)
      if data then
        table.insert(stderr, data)
      end
    end)
    vim.wait(10000, function()
      return done
    end)
    local out = table.concat(stdout, "") .. table.concat(stderr, "")
    local ms = tonumber(out:match("COLD_REQUIRE_MS=([%d%.]+)"))
    assert.is_not_nil(ms)
    assert.is_true(ms <= 5.0, string.format("cold require took %.3f ms", ms))
  end)

  it("setup memory footprint is modest", function()
    require("coco").setup({})
    collectgarbage("collect")
    local kb = collectgarbage("count")
    -- Sanity gate: < 2 MB after setup.
    assert.is_true(kb < 2048, string.format("memory after setup: %.1f KB", kb))
  end)
end)
