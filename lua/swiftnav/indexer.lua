local api = vim.api
local util = require('swiftnav.util')

local M = {}

local TYPES = {
  Class = true,
  Struct = true,
  Enum = true,
  Protocol = true,
  Actor = true,
  Extension = true,
  TypeAlias = true,
}

local TYPE_KEYWORDS = {
  class = 'Class',
  struct = 'Struct',
  enum = 'Enum',
  protocol = 'Protocol',
  actor = 'Actor',
  extension = 'Extension',
  typealias = 'TypeAlias',
}

local RESERVED = {
  ['func'] = true,
  ['init'] = true,
  ['deinit'] = true,
  ['subscript'] = true,
  ['var'] = true,
  ['let'] = true,
  ['class'] = true,
  ['struct'] = true,
  ['enum'] = true,
  ['protocol'] = true,
  ['actor'] = true,
  ['extension'] = true,
  ['typealias'] = true,
  ['case'] = true,
  ['where'] = true,
  ['return'] = true,
  ['if'] = true,
  ['else'] = true,
  ['guard'] = true,
  ['for'] = true,
  ['while'] = true,
  ['switch'] = true,
  ['import'] = true,
  ['public'] = true,
  ['private'] = true,
  ['internal'] = true,
  ['fileprivate'] = true,
  ['open'] = true,
  ['static'] = true,
  ['final'] = true,
  ['override'] = true,
  ['mutating'] = true,
  ['nonisolated'] = true,
  ['async'] = true,
  ['throws'] = true,
  ['rethrows'] = true,
  ['inout'] = true,
  ['some'] = true,
  ['any'] = true,
  ['self'] = true,
  ['super'] = true,
  ['nil'] = true,
  ['true'] = true,
  ['false'] = true,
}

local TYPE_NODES = {
  class_declaration = true,
  protocol_declaration = true,
  actor_declaration = true,
}

local state = {
  root = nil,
  ready = false,
  building = false,
  waiters = {},
  by_name = {},
  by_path = {},
  count = 0,
  started = 0,
}

local containers = {}

local function reset(root)
  state = {
    root = root,
    ready = false,
    building = false,
    waiters = {},
    by_name = {},
    by_path = {},
    count = 0,
    started = 0,
  }
  containers = {}
end

--- Find the repository or package that owns a buffer.
function M.root(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local name = api.nvim_buf_get_name(bufnr)
  local start = name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
  local git = vim.fs.find('.git', { path = start, upward = true })[1]
  if git then
    return vim.fs.dirname(git)
  end
  for _, marker in ipairs({ 'Package.swift', 'project.yml' }) do
    local hit = vim.fs.find(marker, { path = start, upward = true })[1]
    if hit then
      return vim.fs.dirname(hit)
    end
  end
  return name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
end

local function type_name(node, source)
  for child in node:iter_children() do
    local kind = child:type()
    if kind == 'user_type' or kind == 'type_identifier' then
      return vim.treesitter.get_node_text(child, source)
    end
  end
  return nil
end

local function classify(text)
  for keyword, kind in pairs(TYPE_KEYWORDS) do
    local start, finish, name = text:find('%f[%w]' .. keyword .. '%s+([%a_][%w_]*)')
    if name and not RESERVED[name] then
      local name_start = text:find(name, finish - #name, true) or start
      return kind, name, name_start - 1
    end
  end
  local start, finish, name = text:find('%f[%w]func%s+([%a_][%w_]*)')
  if name and not RESERVED[name] then
    local name_start = text:find(name, finish - #name, true) or start
    return 'Function', name, name_start - 1
  end
  for _, keyword in ipairs({ 'let', 'var' }) do
    local _, var_finish, var_name = text:find('%f[%w]' .. keyword .. '%s+([%a_][%w_]*)')
    if var_name and not RESERVED[var_name] and var_name ~= '_' then
      local name_start = text:find(var_name, var_finish - #var_name, true)
      return 'Property', var_name, (name_start or 1) - 1
    end
  end
  local _, case_finish, case_name = text:find('%f[%w]case%s+([%a_][%w_]*)')
  if case_name and not RESERVED[case_name] then
    local name_start = text:find(case_name, case_finish - #case_name, true)
    return 'Constant', case_name, (name_start or 1) - 1
  end
  return nil
end

local function add_entry(entry)
  local names = state.by_name[entry.name]
  if not names then
    names = {}
    state.by_name[entry.name] = names
  end
  names[#names + 1] = entry
  local paths = state.by_path[entry.path]
  if not paths then
    paths = {}
    state.by_path[entry.path] = paths
  end
  paths[#paths + 1] = entry
  state.count = state.count + 1
end

local function remove_path(path)
  local entries = state.by_path[path]
  if not entries then
    return
  end
  state.by_path[path] = nil
  for _, entry in ipairs(entries) do
    local names = state.by_name[entry.name]
    if names then
      for index = #names, 1, -1 do
        if names[index] == entry then
          table.remove(names, index)
          state.count = state.count - 1
        end
      end
      if #names == 0 then
        state.by_name[entry.name] = nil
      end
    end
  end
end

local function index_text(path, text)
  local lnum = 0
  for line in text:gmatch('[^\n]+') do
    lnum = lnum + 1
    local kind, name, col = classify(line)
    if kind and name then
      add_entry({
        name = name,
        kind = kind,
        path = path,
        lnum = lnum,
        col = col,
      })
    end
  end
end

local DECLARATION = [[^[ \t]*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?[ \t]+)*(?:(?:public|private|fileprivate|internal|open|final|static|class|mutating|nonisolated|override|required|convenience|dynamic|lazy|weak|unowned|indirect|isolated|distributed|prefix|postfix|infix)[ \t]+)*(?:class|struct|enum|protocol|actor|extension|typealias|func|let|var)[ \t]+[A-Za-z_][A-Za-z0-9_]*]]
local CASE = [[^[ \t]*case[ \t]+[A-Za-z_][A-Za-z0-9_]*]]

local function scan_command()
  return {
    'rg',
    '--line-number',
    '--no-heading',
    '--with-filename',
    '--color',
    'never',
    '-e',
    DECLARATION,
    '-e',
    CASE,
    '--glob',
    '*.swift',
    '--glob',
    '!**/.build/**',
    '--glob',
    '!**/DerivedData/**',
    '--glob',
    '!**/Pods/**',
    '--glob',
    '!**/.swiftpm/**',
    '--glob',
    '!**/SourcePackages/**',
  }
end

local function finish()
  state.building = false
  state.ready = true
  local waiters = state.waiters
  state.waiters = {}
  for _, waiter in ipairs(waiters) do
    pcall(waiter, true)
  end
end

local function start(notify)
  state.building = true
  state.started = vim.uv.hrtime()
  if notify then
    util.notify('indexing Swift declarations in ' .. vim.fs.basename(state.root))
  end
  vim.system(scan_command(), { cwd = state.root, text = true }, function(object)
    vim.schedule(function()
      local output = object.stdout or ''
      for line in output:gmatch('[^\n]+') do
        local path, lnum, text = line:match('^(.-):(%d+):(.*)$')
        if path then
          local absolute = path:sub(1, 1) == '/' and path or (state.root .. '/' .. path)
          local kind, name, col = classify(text)
          if kind and name then
            add_entry({
              name = name,
              kind = kind,
              path = absolute,
              lnum = tonumber(lnum),
              col = col,
            })
          end
        end
      end
      finish()
    end)
  end)
end

--- Build or reuse the project index and run a callback when it is ready.
function M.ensure(bufnr, callback, notify)
  local root = M.root(bufnr)
  if state.root ~= root then
    reset(root)
  end
  if state.ready then
    callback(true)
    return
  end
  if state.building then
    if notify then
      util.notify('indexing Swift declarations, one moment')
    end
    state.waiters[#state.waiters + 1] = callback
    return
  end
  state.waiters[#state.waiters + 1] = callback
  start(notify)
end

function M.ready()
  return state.ready
end

function M.building()
  return state.building
end

function M.stats()
  return state.count, state.root
end

function M.rebuild()
  local root = state.root
  state.root = nil
  if root then
    reset(root)
  end
end

--- Re-index one file after a write.
function M.update_file(path)
  if not state.ready or not state.root then
    return
  end
  if not vim.startswith(path, state.root .. '/') then
    return
  end
  containers[path] = nil
  remove_path(path)
  local lines = util.read_lines(path)
  if not lines then
    return
  end
  index_text(path, table.concat(lines, '\n'))
end

local function parse_file(path)
  local cached = containers[path]
  if cached then
    return cached
  end
  local lines = util.read_lines(path)
  if not lines then
    return nil
  end
  local content = table.concat(lines, '\n')
  local ok, parser = pcall(vim.treesitter.get_string_parser, content, 'swift')
  if not ok or not parser then
    return nil
  end
  local parsed = parser:parse()[1]
  local intervals = {}
  local function walk(node)
    if TYPE_NODES[node:type()] then
      local name = type_name(node, content)
      if name then
        intervals[#intervals + 1] = {
          start_row = node:start(),
          end_row = node:end_(),
          name = name,
        }
      end
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(parsed:root())
  containers[path] = intervals
  return intervals
end

--- The type that encloses one line of a file.
function M.container_of(path, lnum)
  local intervals = parse_file(path)
  if not intervals then
    return nil
  end
  local row = lnum - 1
  local best
  for _, interval in ipairs(intervals) do
    if interval.start_row <= row and row <= interval.end_row then
      if not best or (interval.end_row - interval.start_row) < (best.end_row - best.start_row) then
        best = interval
      end
    end
  end
  return best and best.name or nil
end

--- The type that encloses a position in a buffer.
function M.enclosing_type(bufnr, row, column)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'swift')
  if not ok then
    return nil
  end
  parser:parse()
  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, column } })
  while node do
    if TYPE_NODES[node:type()] then
      return type_name(node, bufnr)
    end
    node = node:parent()
  end
  return nil
end

local function context(bufnr)
  local name = api.nvim_buf_get_name(bufnr)
  local cursor = api.nvim_win_get_cursor(0)
  local relative = name:sub(#state.root + 2)
  return {
    path = name,
    root = state.root,
    target = relative:match('^([^/]+)') or '',
    container = M.enclosing_type(bufnr, cursor[1] - 1, cursor[2]),
  }
end

local function score(entry, ctx)
  local points = 0
  local type_declaration = TYPES[entry.kind]
  if type_declaration then
    points = points + 30
    if entry.kind ~= 'Extension' then
      points = points + 400
    end
  end
  if entry.path == ctx.path then
    points = points + (type_declaration and 200 or 1000)
  end
  if entry.path:sub(#ctx.root + 2):match('^([^/]+)') == ctx.target then
    points = points + 120
  end
  return points - #entry.path * 0.02
end

--- Declarations of a name, best match first.
function M.definition_candidates(name, bufnr)
  local entries = state.by_name[name]
  if not entries then
    return {}
  end
  if #entries == 1 then
    local entry = entries[1]
    return { {
      name = entry.name,
      kind = entry.kind,
      path = entry.path,
      lnum = entry.lnum,
      col = entry.col,
    } }
  end

  local ctx = context(bufnr)
  local ranked = {}
  for _, entry in ipairs(entries) do
    ranked[#ranked + 1] = { entry = entry, points = score(entry, ctx) }
  end
  table.sort(ranked, function(left, right)
    return left.points > right.points
  end)

  local items = {}
  for index, candidate in ipairs(ranked) do
    if index > 100 then
      break
    end
    local entry = candidate.entry
    local container = nil
    if index <= 40 then
      container = M.container_of(entry.path, entry.lnum)
      if ctx.container and container == ctx.container then
        candidate.points = candidate.points + 300
      end
    end
    items[#items + 1] = {
      name = entry.name,
      kind = entry.kind,
      path = entry.path,
      lnum = entry.lnum,
      col = entry.col,
      container = container,
      points = candidate.points,
    }
  end
  table.sort(items, function(left, right)
    return left.points > right.points
  end)
  return items
end

function M.setup()
  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = '*.swift',
    callback = function(event)
      M.update_file(api.nvim_buf_get_name(event.buf))
    end,
  })
end

return M
