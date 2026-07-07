--- coco.nvim compact context summarization (Phase 4).

local M = {}

--- Rough token estimate: ~4 chars per token.
---@param text string
---@return number
local function estimate_tokens(text)
  return math.ceil(#text / 4)
end

---@param turn table
---@return number
local function turn_tokens(turn)
  local content = turn.content or turn.text or ""
  if type(content) == "table" then
    content = vim.inspect(content)
  end
  return estimate_tokens(tostring(content)) + 4 -- role overhead
end

---@param turn table
---@param max_tokens number
---@return table
local function truncate_turn(turn, max_tokens)
  local content = turn.content or turn.text or ""
  if type(content) == "table" then
    content = vim.inspect(content)
  end
  content = tostring(content)
  -- Reserve 4 tokens for role overhead.
  local max_chars = math.max(0, (max_tokens - 4) * 4)
  if #content <= max_chars then
    return turn
  end
  local truncated = content:sub(1, max_chars) .. "\n[truncated]"
  return { role = turn.role, content = truncated }
end

--- Summarize older conversation turns while preserving system instructions
--- and the latest N turns, capped to a token budget.
---@param history table[]
---@param budget number target token budget
---@return table[]
function M.compact(history, budget)
  budget = budget or 4000
  local system = {}
  local turns = {}
  for _, turn in ipairs(history) do
    if turn.role == "system" then
      table.insert(system, turn)
    else
      table.insert(turns, turn)
    end
  end

  -- Always preserve system instructions.
  local result = {}
  local used = 0
  for _, turn in ipairs(system) do
    table.insert(result, turn)
    used = used + turn_tokens(turn)
  end

  -- Always preserve the last 10 turns, truncated minimally to fit.
  local keep_latest = 10
  local split = math.max(1, #turns - keep_latest + 1)
  local older = {}
  local latest = {}
  for i, turn in ipairs(turns) do
    if i < split then
      table.insert(older, turn)
    else
      table.insert(latest, turn)
    end
  end

  local remaining = math.max(0, budget - used)
  local kept_latest = {}
  -- Walk newest-to-oldest so the most recent context is preserved first.
  for i = #latest, 1, -1 do
    local turn = latest[i]
    local tokens = turn_tokens(turn)
    if tokens <= remaining then
      table.insert(kept_latest, 1, turn)
      remaining = remaining - tokens
    else
      -- The newest remaining turn does not fit; truncate it instead of dropping.
      local truncated = truncate_turn(turn, remaining)
      if truncated.content and truncated.content ~= "" then
        table.insert(kept_latest, 1, truncated)
      end
      remaining = 0
      break
    end
  end

  -- Summarize older turns by concatenating and truncating to fit budget.
  if #older > 0 and remaining > 0 then
    local summary_parts = {}
    for _, turn in ipairs(older) do
      local prefix = turn.role == "user" and "User: " or "Assistant: "
      table.insert(summary_parts, prefix .. tostring(turn.content or turn.text or ""))
    end
    local summary_text = table.concat(summary_parts, "\n")
    -- Leave a token headroom for the summary turn framing.
    local max_chars = math.max(0, remaining * 4 - 256)
    if #summary_text > max_chars then
      summary_text = summary_text:sub(1, max_chars) .. "\n[earlier context truncated]"
    end
    if summary_text ~= "" then
      table.insert(result, { role = "system", content = "Earlier conversation summary:\n" .. summary_text })
    end
  end

  -- Append latest turns verbatim (or truncated).
  for _, turn in ipairs(kept_latest) do
    table.insert(result, turn)
  end

  return result
end

return M
