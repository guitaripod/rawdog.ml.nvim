local M = {}

local store_path = vim.fn.stdpath('state') .. '/swiftnav.json'
local MAX_ENTRIES = 2000
local MAX_AGE_SECONDS = 60 * 60 * 24 * 60
local SAVE_DELAY_MS = 2000

local entries = {}
local loaded = false
local save_timer = nil
local newest = 1

local function entry_key(item)
  return (item.path or '') .. '\1' .. (item.name or '')
end

local function load()
  if loaded then
    return
  end
  loaded = true
  local ok, lines = pcall(vim.fn.readfile, store_path)
  if not ok or not lines then
    return
  end
  local decoded = vim.json.decode(table.concat(lines, '\n'))
  entries = decoded or {}
  for _, timestamp in pairs(entries) do
    if timestamp > newest then
      newest = timestamp
    end
  end
end

local function prune()
  local now = os.time()
  local kept, total = {}, 0
  for key, timestamp in pairs(entries) do
    if now - timestamp < MAX_AGE_SECONDS then
      kept[key] = timestamp
      total = total + 1
    end
  end
  if total <= MAX_ENTRIES then
    entries = kept
    return
  end
  local ordered = {}
  for key, timestamp in pairs(kept) do
    ordered[#ordered + 1] = { key = key, timestamp = timestamp }
  end
  table.sort(ordered, function(left, right)
    return left.timestamp > right.timestamp
  end)
  entries = {}
  for index = 1, MAX_ENTRIES do
    local entry = ordered[index]
    if entry then
      entries[entry.key] = entry.timestamp
    end
  end
end

function M.save()
  prune()
  vim.fn.mkdir(vim.fs.dirname(store_path), 'p')
  local ok, encoded = pcall(vim.json.encode, entries)
  if ok then
    vim.fn.writefile({ encoded }, store_path)
  end
end

local function schedule_save()
  if save_timer then
    return
  end
  save_timer = vim.defer_fn(function()
    save_timer = nil
    M.save()
  end, SAVE_DELAY_MS)
end

--- Normalised recency in the range 0..1 for one candidate.
function M.get(item)
  load()
  local timestamp = entries[entry_key(item)]
  if not timestamp then
    return 0
  end
  local now = os.time()
  local age = math.max(0, now - timestamp)
  local half_life = 60 * 60 * 24 * 3
  return math.exp(-age / half_life)
end

--- Record that the user opened an item.
function M.touch(item)
  load()
  local now = os.time()
  entries[entry_key(item)] = now
  if now > newest then
    newest = now
  end
  schedule_save()
end

vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    if loaded then
      M.save()
    end
  end,
})

return M
