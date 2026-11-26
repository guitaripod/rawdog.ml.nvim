local api = vim.api
local glyph = require('swiftnav.glyph')
local index = require('swiftnav.index')
local rank = require('swiftnav.rank')
local recency = require('swiftnav.recency')
local ui = require('swiftnav.ui')
local util = require('swiftnav.util')

local M = {}

local RESULT_LIMIT = 400
local FILE_TTL_SECONDS = 30
local MIN_SYMBOL_QUERY = 3
local RETRY_DELAYS = { 400, 900, 2000, 4000, 6000, 10000, 15000, 20000 }

local preview_namespace = api.nvim_create_namespace('swiftnav.preview')

local file_cache = { root = nil, at = 0, items = {}, loading = false }

local function file_command()
  if vim.fn.executable('fd') == 1 then
    return { 'fd', '--type', 'f', '--hidden', '--exclude', '.git', '--exclude', '.build' }
  end
  return { 'rg', '--files', '--hidden', '--glob', '!.git', '--glob', '!.build' }
end

local function is_swift_path(path)
  return path:match('%.swift$') ~= nil
end

local function load_files(root, on_done)
  local now = os.time()
  if file_cache.root == root and now - file_cache.at < FILE_TTL_SECONDS then
    on_done(file_cache.items)
    return
  end
  if file_cache.root == root and file_cache.loading then
    return
  end
  file_cache.root, file_cache.loading = root, true
  vim.system(file_command(), { cwd = root, text = true }, function(object)
    local items = {}
    if object.code == 0 and object.stdout then
      for _, relative in ipairs(vim.split(object.stdout, '\n', { trimempty = true })) do
        if is_swift_path(relative) then
          items[#items + 1] = {
            kind = 'File',
            name = util.basename(relative),
            container = vim.fs.dirname(relative),
            path = root .. '/' .. relative,
            range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
            lnum = 1,
          }
        end
      end
    end
    file_cache = { root = root, at = os.time(), items = items, loading = false }
    vim.schedule(function()
      on_done(items)
    end)
  end)
end

local function recent_items(root)
  local items, seen = {}, {}
  for index, path in ipairs(vim.v.oldfiles) do
    if is_swift_path(path) and vim.startswith(path, root) and not seen[path] then
      seen[path] = true
      items[#items + 1] = {
        kind = 'File',
        name = util.basename(path),
        container = vim.fs.dirname(util.relpath(path)),
        path = path,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
        lnum = 1,
        seed = math.max(0, 1 - index * 0.05),
      }
    end
  end
  return items
end

local function is_generated_name(name)
  return name:find('$s', 1, true) ~= nil or name:find('fMp_', 1, true) ~= nil
end

local function collect_symbols(results, current_path)
  local items = {}
  for _, entry in pairs(results or {}) do
    for _, symbol in ipairs(entry.result or {}) do
      local location = symbol.location
      local uri = location and (location.uri or location.targetUri)
      if uri and not is_generated_name(symbol.name) then
        local path = vim.uri_to_fname(uri)
        local range = location.range or location.targetSelectionRange
        if is_swift_path(path) and range then
          items[#items + 1] = {
            kind = vim.lsp.protocol.SymbolKind[symbol.kind] or 'Unknown',
            name = symbol.name,
            container = symbol.containerName,
            path = path,
            range = range,
            lnum = range.start.line + 1,
          }
        end
      end
    end
  end
  return items
end

local function format(item, width)
  local mark, group = glyph.get(item.kind)
  local label
  if item.kind == 'File' or item.container == nil or item.container == '' then
    label = item.name
  else
    label = item.container .. '.' .. item.name
  end
  local location = string.format('%s:%d', util.relpath(item.path), item.lnum or 1)
  local left = mark .. ' ' .. label
  local available = width - vim.fn.strdisplaywidth(location) - 1
  if vim.fn.strdisplaywidth(left) > available then
    left = util.fit(left, math.max(0, available))
  end
  local space = math.max(1, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(location))
  local text = left .. string.rep(' ', space) .. location

  local container_length = (item.kind ~= 'File' and item.container and item.container ~= '') and (#item.container + 1) or 0
  local name_start = #mark + 1
  local marks = {
    { 0, #mark, group },
    { name_start, name_start + container_length, 'SwiftNavContainer' },
    { name_start + container_length, name_start + container_length + #item.name, 'SwiftNavName' },
  }
  return text, marks
end

--- Render a file preview centered on a symbol, used by every Swift list.
function M.preview(item, buf, win)
  if not item or not item.path then
    return
  end
  local lines = util.read_lines(item.path, (item.lnum or 1) + 120) or {}
  api.nvim_set_option_value('modifiable', true, { buf = buf })
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_set_option_value('modifiable', false, { buf = buf })
  if vim.b[buf].swiftnav_treesitter ~= true then
    vim.b[buf].swiftnav_treesitter = true
    pcall(vim.treesitter.start, buf, 'swift')
  end
  local row = math.min(item.lnum or 1, math.max(#lines, 1))
  local column = item.range and item.range.start.character or 0
  pcall(api.nvim_win_set_cursor, win, { row, column })
  pcall(api.nvim_win_call, win, function()
    vim.cmd('normal! zz')
  end)
  api.nvim_buf_clear_namespace(buf, preview_namespace, 0, -1)
  local width = #(lines[row] or '')
  if width > 0 then
    api.nvim_buf_set_extmark(buf, preview_namespace, row - 1, 0, {
      end_col = width,
      hl_group = 'SwiftNavPreviewLine',
      priority = 150,
    })
  end
end

local function jump(item, action, on_open)
  recency.touch(item)
  local location = {
    uri = vim.uri_from_fname(item.path),
    range = item.range or { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
  }
  if action == 'vsplit' or action == 'split' or action == 'tab' then
    local command = action == 'vsplit' and 'vsplit' or (action == 'split' and 'split' or 'tabedit')
    vim.cmd(command .. ' ' .. vim.fn.fnameescape(item.path))
  end
  vim.lsp.util.show_document(location, 'utf-16', { focus = true })
  if on_open then
    on_open(item)
  end
end

--- Open Quickly: ranked workspace symbols plus files and recent edits.
function M.open(opts)
  opts = opts or {}
  local bufnr = api.nvim_get_current_buf()
  local root = util.package_root(bufnr) or vim.fn.getcwd()
  local current_path = api.nvim_buf_get_name(bufnr)
  local state = {
    files = {},
    recents = recent_items(root),
    symbols = {},
    query = '',
    generation = 0,
    pending = false,
    cancel = nil,
    retries = 0,
  }
  local picker

  local function candidates()
    local pool = {}
    vim.list_extend(pool, state.symbols)
    vim.list_extend(pool, state.recents)
    vim.list_extend(pool, state.files)
    for _, item in ipairs(pool) do
      item.recency = math.max(recency.get(item), item.seed or 0)
      item.current_file = item.path == current_path
    end
    return pool
  end

  local function status_text()
    if #vim.lsp.get_clients({ bufnr = bufnr, name = 'sourcekit' }) == 0 then
      return 'sourcekit-lsp is not attached'
    end
    if #state.symbols > 0 then
      return index.busy() and 'sourcekit is indexing — new symbols appear automatically' or nil
    end
    if state.pending then
      return 'searching'
    end
    if state.query == '' then
      return 'recent files'
    end
    if #state.query < MIN_SYMBOL_QUERY then
      return 'type three characters for workspace symbols'
    end
    if index.busy() then
      return 'sourcekit is indexing — new symbols appear automatically'
    end
    return 'no symbols match ' .. state.query
  end

  local function refresh()
    if not picker or picker.closed then
      return
    end
    local items = rank.rank(state.query, candidates())
    if #items > RESULT_LIMIT then
      local cut = {}
      for index = 1, RESULT_LIMIT do
        cut[index] = items[index]
      end
      items = cut
    end
    picker:set_items(items, status_text())
  end

  local function request_symbols(query)
    state.generation = state.generation + 1
    local generation = state.generation
    if state.cancel then
      state.cancel()
      state.cancel = nil
    end
    if #query < MIN_SYMBOL_QUERY then
      state.pending = false
      state.symbols = {}
      return
    end
    state.pending = true
    state.cancel = vim.lsp.buf_request_all(bufnr, 'workspace/symbol', { query = query }, function(results)
      vim.schedule(function()
        if generation ~= state.generation then
          return
        end
        state.pending = false
        state.symbols = collect_symbols(results, current_path)
        if #state.symbols == 0 and state.retries < #RETRY_DELAYS and state.query == query then
          state.retries = state.retries + 1
          local delay = RETRY_DELAYS[state.retries]
          if delay then
            vim.defer_fn(function()
              if picker and not picker.closed and state.query == query then
                request_symbols(query)
              end
            end, delay)
          end
        end
        refresh()
      end)
    end)
    if not state.cancel then
      state.pending = false
    end
  end

  local unsubscribe = function() end

  picker = ui.open({
    title = 'Open Quickly',
    list_title = 'Symbols and files',
    hints = '<CR> open · <C-v>/<C-x>/<C-t> splits · Tab next',
    preview_item = M.preview,
    format = format,
    prefill = opts.prefill,
    on_change = function(query)
      state.query = query
      state.retries = 0
      request_symbols(query)
      refresh()
    end,
    on_accept = function(item, action)
      jump(item, action)
    end,
    on_close = function()
      unsubscribe()
      if state.cancel then
        state.cancel()
        state.cancel = nil
      end
    end,
  })

  unsubscribe = index.on_settled(function()
    if picker and not picker.closed and state.query ~= '' and #state.symbols == 0 then
      request_symbols(state.query)
    end
  end)

  load_files(root, function(items)
    state.files = items
    refresh()
  end)

  refresh()
  return picker
end

M.jump = jump

return M
