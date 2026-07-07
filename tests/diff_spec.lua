local diff = require("coco.ui.diff")
local state = require("coco.session.state")

describe("diff ui", function()
  before_each(function()
    diff.close_all()
    state.reset()
  end)

  after_each(function()
    diff.close_all()
  end)

  it("opens a diff view and accept writes new contents", function()
    local tmp = vim.fn.tempname() .. ".lua"
    local fd = io.open(tmp, "w")
    fd:write("old content\n")
    fd:close()

    local id = diff.open(tmp, tmp, "new content\n", "test diff")
    assert.equals(tmp, id)
    assert.is_not_nil(diff._views()[id])
    assert.equals("pending", state.get().diffs[id].status)

    diff.accept(id)
    assert.equals("FILE_SAVED", state.get().diffs[id].status)

    local rf = io.open(tmp, "r")
    local content = rf and rf:read("*a") or ""
    if rf then
      rf:close()
    end
    assert.equals("new content\n", content)
    os.remove(tmp)
  end)

  it("deny resolves DIFF_REJECTED", function()
    local tmp = vim.fn.tempname() .. ".lua"
    local fd = io.open(tmp, "w")
    fd:write("old\n")
    fd:close()

    local id = diff.open(tmp, tmp, "new\n", "test diff")
    diff.deny(id)
    assert.equals("DIFF_REJECTED", state.get().diffs[id].status)
    os.remove(tmp)
  end)
end)
