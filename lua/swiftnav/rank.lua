local M = {}

local KIND_BONUS = {
  Struct = 95,
  Class = 95,
  Actor = 92,
  Protocol = 90,
  Enum = 88,
  Interface = 88,
  Function = 74,
  Method = 70,
  Constructor = 68,
  Property = 62,
  Field = 58,
  Variable = 58,
  Constant = 56,
  Module = 40,
  File = 50,
}

--- Drop the argument list so `makeWidget(named:)` matches as `makeWidget`.
local function base_name(name)
  return name:match('^(.-)%(') or name
end

--- Collect the start of every camel-case or snake-case word in an identifier.
local function word_starts(name)
  local out = {}
  for i = 1, #name do
    local char = name:sub(i, i)
    local upper = char:match('%u') ~= nil
    if upper then
      local previous = name:sub(i - 1, i - 1)
      local following = name:sub(i + 1, i + 1)
      local after_separator = i == 1 or previous:match('[^%w]') ~= nil
      local after_lower = previous:match('[%l%d]') ~= nil
      local after_run = previous:match('%u') ~= nil and following:match('%l') ~= nil
      if after_separator or after_lower or after_run then
        out[#out + 1] = char:lower()
      end
    end
  end
  return table.concat(out)
end

--- Score an ordered subsequence match, rewarding adjacency and word boundaries.
function M.subsequence(haystack, needle)
  local position, score, streak = 1, 0, 0
  for i = 1, #needle do
    local char = needle:sub(i, i)
    local found = haystack:find(char, position, true)
    if not found then
      return nil
    end
    local boundary = found == 1 or haystack:sub(found - 1, found - 1):match('[^%w]') ~= nil
    streak = found == position and streak + 1 or 0
    score = score + 10 + streak * 8 + (boundary and 8 or 0)
    position = found + 1
  end
  return score - (#haystack - #needle)
end

--- Rank one candidate for a query. Higher is better, nil means no match.
function M.score(query, item)
  local query_lower = query:lower()
  if query_lower == '' then
    return 1
      + (KIND_BONUS[item.kind] or 40)
      + (item.current_file and 160 or 0)
      + (item.recency or 0) * 90
  end

  local name = item.kind == 'File' and item.name or base_name(item.name)
  local lower_name = name:lower()
  local container = (item.container or ''):lower()
  local path = (item.path or ''):lower()
  local base

  if lower_name == query_lower then
    base = 1400
  elseif lower_name:sub(1, #query_lower) == query_lower then
    base = 1200 - #lower_name
  elseif word_starts(name):sub(1, #query_lower) == query_lower then
    base = 1150 - #lower_name
  else
    local at = lower_name:find(query_lower, 1, true)
    if at then
      base = 1000 - at * 5 - (#lower_name - #query_lower)
      if at == 1 or lower_name:sub(at - 1, at - 1):match('[^%w]') ~= nil then
        base = base + 40
      end
    elseif container ~= '' and container:find(query_lower, 1, true) then
      base = 780 - #lower_name
    elseif path ~= '' and path:find(query_lower, 1, true) then
      base = 580 - #path * 0.2
    else
      local subsequence = M.subsequence(lower_name, query_lower)
      if not subsequence then
        return nil
      end
      base = 500 + subsequence
    end
  end

  return base
    + (KIND_BONUS[item.kind] or 40)
    + (item.current_file and 160 or 0)
    + (item.recency or 0) * 90
end

--- Filter and sort items by score, returning a new list.
function M.rank(query, items)
  local scored = {}
  for _, item in ipairs(items) do
    local score = M.score(query, item)
    if score then
      scored[#scored + 1] = { item = item, score = score }
    end
  end
  table.sort(scored, function(left, right)
    if left.score == right.score then
      return left.item.name < right.item.name
    end
    return left.score > right.score
  end)
  local out = {}
  for index, entry in ipairs(scored) do
    entry.item.score = entry.score
    out[index] = entry.item
  end
  return out
end

return M
