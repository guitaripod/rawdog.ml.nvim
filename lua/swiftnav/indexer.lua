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

--- Bump when the extraction rules change, so stale caches are discarded.
local INDEX_VERSION = 4

local TYPE_NODES = {
  class_declaration = true,
  protocol_declaration = true,
  actor_declaration = true,
}

local MODIFIERS = [[(?:[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?[ \t]+)*]]
local ATTRIBUTES = '(?:@[A-Za-z_][A-Za-z0-9_]*(?:\\([^)]*\\))?[ \t]+)*'

local TYPE_PATTERN = '^[ \t]*' .. ATTRIBUTES .. MODIFIERS
  .. '(class|struct|enum|protocol|actor|extension|typealias)[ \t]+([A-Za-z_][A-Za-z0-9_]*)'
local FUNCTION_PATTERN = '^[ \t]*' .. ATTRIBUTES .. MODIFIERS .. 'func[ \t]+([A-Za-z_][A-Za-z0-9_]*)'
local PROPERTY_PATTERN = '^[ \t]{0,4}' .. ATTRIBUTES .. MODIFIERS .. '(?:let|var)[ \t]+([A-Za-z_][A-Za-z0-9_]*)'
local CASE_PATTERN = '^[ \t]*case[ \t]+([A-Za-z_][A-Za-z0-9_]*)'

local EXCLUDES = {
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

local state
local containers = {}
local interned = { name = {}, path = {}, kind = {} }

local function intern(bucket, value)
  local hit = bucket[value]
  if hit then
    return hit
  end
  bucket[value] = value
  return value
end

local function new_state(root)
  return {
    root = root,
    ready = false,
    building = false,
    waiters = {},
    by_name = {},
    by_path = {},
    mtimes = {},
    count = 0,
    save_timer = nil,
    reconcile_timer = nil,
    cache_loaded = false,
  }
end

state = new_state(nil)

local function reset(root)
  state = new_state(root)
  containers = {}
  interned = { name = {}, path = {}, kind = {} }
end

local function cache_path(root)
  local hash = vim.fn.sha256(root):sub(1, 16)
  return vim.fn.stdpath('cache') .. '/swiftnav/' .. hash .. '.json'
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
  entry.name = intern(interned.name, entry.name)
  entry.path = intern(interned.path, entry.path)
  entry.kind = intern(interned.kind, entry.kind)
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
      local indented = #(line:match('^[ \t]*') or '')
      if kind ~= 'Property' or indented <= 4 then
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
end

local function schedule_save()
  if state.save_timer then
    return
  end
  state.save_timer = vim.defer_fn(function()
    state.save_timer = nil
    M.save()
  end, 2000)
end

local function finish()
  if state.building then
    state.building = false
  end
  state.ready = true
  local waiters = state.waiters
  state.waiters = {}
  for _, waiter in ipairs(waiters) do
    pcall(waiter, true)
  end
  schedule_save()
end

local function rg_command(pattern, replace)
  local command = {
    'rg',
    '--line-number',
    '--no-heading',
    '--with-filename',
    '--color',
    'never',
    '-o',
    '-r',
    replace,
    pattern,
  }
  vim.list_extend(command, EXCLUDES)
  return command
end

local function split_lines(text)
  return vim.split(text or '', '\n', { trimempty = true })
end

local function parse_type_line(line)
  local path, lnum, payload = line:match('^(.-):(%d+):(.*)$')
  if not path then
    return
  end
  local keyword, name = payload:match('^(%a+)|(.+)$')
  if keyword and name then
    add_entry({
      name = name,
      kind = TYPE_KEYWORDS[keyword] or 'Class',
      path = path:sub(1, 1) == '/' and path or (state.root .. '/' .. path),
      lnum = tonumber(lnum),
    })
  end
end

local function parse_named_line(line, kind)
  local path, lnum, name = line:match('^(.-):(%d+):(.*)$')
  if not path or name == '' then
    return
  end
  add_entry({
    name = name,
    kind = kind,
    path = path:sub(1, 1) == '/' and path or (state.root .. '/' .. path),
    lnum = tonumber(lnum),
  })
end

local function build(notify)
  local root = state.root
  local waiters = state.waiters
  reset(root)
  state.waiters = waiters
  state.building = true
  if notify then
    util.notify('indexing Swift declarations in ' .. vim.fs.basename(root))
  end

  vim.system({ 'rg', '--files', unpack(EXCLUDES) }, { cwd = root, text = true }, function(files)
    vim.schedule(function()
      if state.root ~= root then
        return
      end
      for _, relative in ipairs(split_lines(files.stdout)) do
        local path = root .. '/' .. relative
        local stat = vim.uv.fs_stat(path)
        state.mtimes[path] = stat and stat.mtime.sec or 0
      end

      local outputs = {}
      local remaining = 4
      local pump
      local function collect(key)
        return function(object)
          vim.schedule(function()
            outputs[key] = object.stdout or ''
            remaining = remaining - 1
            if remaining == 0 then
              pump(outputs)
            end
          end)
        end
      end

      pump = function(batch)
        local queues = {
          { lines = split_lines(batch.types), parse = parse_type_line },
          { lines = split_lines(batch.functions), parse = function(line)
            parse_named_line(line, 'Function')
          end },
          { lines = split_lines(batch.properties), parse = function(line)
            parse_named_line(line, 'Property')
          end },
          { lines = split_lines(batch.cases), parse = function(line)
            parse_named_line(line, 'Constant')
          end },
        }
        local queue_index, line_index = 1, 1
        local function step()
          if state.root ~= root then
            return
          end
          local budget = 6000
          while budget > 0 do
            local queue = queues[queue_index]
            if not queue then
              finish()
              return
            end
            local line = queue.lines[line_index]
            if line then
              queue.parse(line)
              line_index = line_index + 1
              budget = budget - 1
            else
              queue_index = queue_index + 1
              line_index = 1
            end
          end
          vim.defer_fn(step, 4)
        end
        step()
      end

      vim.system(rg_command(TYPE_PATTERN, '$1|$2'), { cwd = root, text = true }, collect('types'))
      vim.system(rg_command(FUNCTION_PATTERN, '$1'), { cwd = root, text = true }, collect('functions'))
      vim.system(rg_command(PROPERTY_PATTERN, '$1'), { cwd = root, text = true }, collect('properties'))
      vim.system(rg_command(CASE_PATTERN, '$1'), { cwd = root, text = true }, collect('cases'))
    end)
  end)
end

local function schedule_reconcile(root)
  if state.reconcile_timer then
    return
  end
  state.reconcile_timer = vim.defer_fn(function()
    state.reconcile_timer = nil
    if state.root == root and state.ready then
      M.reconcile()
    end
  end, 600)
end

local function load_cache(root)
  local file = io.open(cache_path(root), 'rb')
  if not file then
    return false
  end
  local data = file:read('*a')
  file:close()
  local ok, payload = pcall(vim.json.decode, data)
  if not ok or type(payload) ~= 'table' or payload.version ~= INDEX_VERSION then
    return false
  end
  state = new_state(root)
  containers = {}
  for _, item in ipairs(payload.files or {}) do
    if type(item) == 'table' and item[1] then
      state.mtimes[item[1]] = item[2]
    end
  end
  for _, item in ipairs(payload.entries or {}) do
    if type(item) == 'table' and item[2] then
      add_entry({
        kind = item[1],
        name = item[2],
        path = item[3],
        lnum = item[4],
        col = item[5] and item[5] >= 0 and item[5] or nil,
      })
    end
  end
  state.ready = true
  state.cache_loaded = true
  schedule_reconcile(root)
  return true
end

--- Build or reuse the project index and run a callback when it is ready.
function M.ensure(bufnr, callback, notify)
  local root = M.root(bufnr)
  if state.root ~= root then
    reset(root)
    if load_cache(root) then
      callback(true)
      return
    end
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
  build(notify)
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
  if lines then
    index_text(path, table.concat(lines, '\n'))
  end
  local stat = vim.uv.fs_stat(path)
  state.mtimes[path] = stat and stat.mtime.sec or 0
  schedule_save()
end

--- Compare the cached file list against the working tree and patch changes.
function M.reconcile()
  local root = state.root
  if not root or not state.ready then
    return
  end
  local command = { 'rg', '--files' }
  vim.list_extend(command, EXCLUDES)
  vim.system(command, { cwd = root, text = true }, function(object)
    vim.schedule(function()
      if state.root ~= root then
        return
      end
      local seen, changed = {}, {}
      for _, relative in ipairs(split_lines(object.stdout)) do
        local path = root .. '/' .. relative
        seen[path] = true
        local stat = vim.uv.fs_stat(path)
        local mtime = stat and stat.mtime.sec or 0
        if state.mtimes[path] ~= mtime then
          changed[#changed + 1] = path
        end
      end
      local deleted = {}
      for path in pairs(state.mtimes) do
        if not seen[path] then
          deleted[#deleted + 1] = path
        end
      end
      for _, path in ipairs(deleted) do
        remove_path(path)
        state.mtimes[path] = nil
      end
      if #changed > 80 then
        build(false)
        return
      end
      for _, path in ipairs(changed) do
        remove_path(path)
        local lines = util.read_lines(path)
        if lines then
          index_text(path, table.concat(lines, '\n'))
        end
        local stat = vim.uv.fs_stat(path)
        state.mtimes[path] = stat and stat.mtime.sec or 0
      end
      if #changed > 0 or #deleted > 0 then
        schedule_save()
      end
    end)
  end)
end

function M.save()
  local root = state.root
  if not root or not state.ready or state.count == 0 then
    return
  end
  local files = {}
  for path, mtime in pairs(state.mtimes) do
    files[#files + 1] = { path, mtime }
  end
  local entries = {}
  for _, items in pairs(state.by_path) do
    for _, entry in ipairs(items) do
      entries[#entries + 1] = { entry.kind, entry.name, entry.path, entry.lnum, entry.col or -1 }
    end
  end
  local ok, payload = pcall(vim.json.encode, {
    version = INDEX_VERSION,
    root = root,
    files = files,
    entries = entries,
  })
  if not ok then
    return
  end
  local path = cache_path(root)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local file = io.open(path, 'wb')
  if not file then
    return
  end
  file:write(payload)
  file:close()
end

--- Forget the index and its cache, so the next request rebuilds it.
function M.rebuild()
  local root = state.root
  if root then
    pcall(vim.fn.delete, cache_path(root))
  end
  reset(root)
end

local parse_file

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

parse_file = function(path)
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
    if ctx.container and index <= 12 then
      container = M.container_of(entry.path, entry.lnum)
      if container == ctx.container then
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
  vim.api.nvim_create_autocmd('VimLeavePre', {
    callback = function()
      if state.save_timer then
        pcall(function()
          state.save_timer:stop()
        end)
        state.save_timer = nil
      end
      M.save()
    end,
  })
end

return M
