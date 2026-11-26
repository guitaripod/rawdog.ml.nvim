local api = vim.api
local index = require('swiftnav.index')
local symbols = require('swiftnav.symbols')
local util = require('swiftnav.util')

local M = {}

local namespace = api.nvim_create_namespace('swiftnav.related')
local state = { closed = true, sections = {}, rowmap = {} }

local TYPE_KINDS = {
  Struct = true,
  Class = true,
  Enum = true,
  Protocol = true,
  Interface = true,
  Actor = true,
  Extension = true,
}

local function section(sections, index, name)
  local existing = index[name]
  if existing then
    return existing
  end
  local created = { name = name, items = {}, done = false }
  index[name] = created
  sections[#sections + 1] = created
  return created
end

local function entry_key(entry)
  return table.concat({ entry.uri or '', entry.range and entry.range.start.line or -1, entry.label or '' }, '\1')
end

local function short_name(name)
  if not name or name == '' then
    return 'item'
  end
  return name:match('([^%.]+)$') or name
end

local function is_noise(name, uri, range)
  if not uri or not range then
    return true
  end
  if range.start.line == 0 and range.start.character == 0 then
    return true
  end
  local path = vim.uri_to_fname(uri)
  if path:find('%.swiftinterface$') or path:find('/usr/lib/swift/', 1, true) then
    return true
  end
  return name ~= nil and (name:find('getter:', 1, true) ~= nil or name:find('setter:', 1, true) ~= nil)
end

local function add(section_table, seen, entry)
  if is_noise(entry.label, entry.uri, entry.range) then
    return
  end
  local key = entry_key(entry)
  if seen[key] then
    return
  end
  seen[key] = true
  section_table.items[#section_table.items + 1] = entry
end

local function declaration_label(text)
  local trimmed = util.trim(text)
  local patterns = {
    'func%s+([%w_]+)',
    'init%f[%W]',
    'deinit%f[%W]',
    'var%s+([%w_]+)',
    'let%s+([%w_]+)',
    'class%s+([%w_]+)',
    'struct%s+([%w_]+)',
    'enum%s+([%w_]+)',
    'protocol%s+([%w_]+)',
    'actor%s+([%w_]+)',
    'extension%s+([%w_%.]+)',
  }
  for _, pattern in ipairs(patterns) do
    local capture = trimmed:match(pattern)
    if capture == '' then
      return 'init'
    end
    if capture then
      return capture
    end
  end
  return trimmed:sub(1, 32)
end

local function line_text(uri, line)
  local path = vim.uri_to_fname(uri)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
    return api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ''
  end
  local lines = util.read_lines(path, line + 1)
  return lines and lines[line + 1] or ''
end

--- Gather callers, callees, overrides, conformances and references for the
--- symbol at a position, reporting each section as it arrives.
function M.collect(opts)
  local bufnr = opts.bufnr
  local sections, index, seen = {}, {}, {}
  local function update()
    if opts.on_update then
      opts.on_update(sections, index)
    end
  end
  local function finish(name)
    local target = section(sections, index, name)
    target.done = true
    update()
  end
  local function request(method, params, handler)
    local supported = false
    for _, candidate in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      if candidate:supports_method(method, bufnr) then
        supported = true
        break
      end
    end
    if not supported then
      handler({}, 'utf-16')
      return
    end
    vim.lsp.buf_request_all(bufnr, method, params, function(results)
      vim.schedule(function()
        local merged, encoding = {}, 'utf-16'
        for _, entry in pairs(results or {}) do
          if entry.result then
            merged[#merged + 1] = entry.result
          end
          if entry.context and entry.context.client then
            encoding = entry.context.client.offset_encoding
          end
        end
        handler(merged, encoding)
      end)
    end)
  end
  local function position()
    return {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      position = { line = opts.line or 0, character = opts.character or 0 },
    }
  end

  symbols.for_buffer(bufnr, function(tree)
    local node = symbols.enclosing(tree, opts.line or 0, opts.character or 0)
    local kind = node and node.kind_name or nil
    local title = node and symbols.label(node) or 'cursor'
    local member = kind ~= nil and not TYPE_KINDS[kind]

    if member then
      section(sections, index, 'Callers')
      section(sections, index, 'Callees')
      section(sections, index, 'Overrides & Implementations')
      section(sections, index, 'References')
      update()

      request('textDocument/prepareCallHierarchy', position(), function(items)
        local item = items[1] and items[1][1]
        if not item then
          finish('Callers')
          finish('Callees')
          return
        end
        if item.name and item.name ~= '' then
          title = item.name
          if opts.on_title then
            opts.on_title(title)
          end
        end
        request('callHierarchy/incomingCalls', { item = item }, function(calls)
          for _, batch in ipairs(calls) do
            for _, call in ipairs(batch) do
              for _, range in ipairs(call.fromRanges or {}) do
                add(index.Callers, seen, {
                  label = short_name(call.from.name),
                  uri = call.from.uri,
                  range = range,
                })
              end
            end
          end
          finish('Callers')
        end)
        request('callHierarchy/outgoingCalls', { item = item }, function(calls)
          for _, batch in ipairs(calls) do
            for _, call in ipairs(batch) do
              local target = call.to or {}
              local range = target.selectionRange or target.range
              if target.uri and range then
                add(index.Callees, seen, {
                  label = short_name(target.name),
                  uri = target.uri,
                  range = range,
                })
              end
            end
          end
          finish('Callees')
        end)
      end)
    else
      section(sections, index, 'Supertypes')
      section(sections, index, 'Subtypes')
      section(sections, index, 'Implementations')
      section(sections, index, 'References')
      update()

      local type_name = nil
      request('textDocument/prepareTypeHierarchy', position(), function(items)
        local item = items[1] and items[1][1]
        if not item then
          finish('Supertypes')
          finish('Subtypes')
          return
        end
        if item.name and item.name ~= '' then
          title = item.name
          type_name = item.name
          if opts.on_title then
            opts.on_title(title)
          end
        end
        request('typeHierarchy/supertypes', { item = item }, function(batches)
          for _, batch in ipairs(batches) do
            for _, node in ipairs(batch) do
              add(index.Supertypes, seen, {
                label = short_name(node.name),
                uri = node.uri,
                range = node.selectionRange or node.range,
              })
            end
          end
          finish('Supertypes')
        end)
        request('typeHierarchy/subtypes', { item = item }, function(batches)
          for _, batch in ipairs(batches) do
            for _, node in ipairs(batch) do
              local name = node.name or ''
              local same_type = type_name ~= nil
                and (name == type_name or name:sub(1, #type_name + 1) == type_name .. ':')
              local extension = node.kind == vim.lsp.protocol.SymbolKind.Extension
                or same_type
                or name:find(':', 1, true) ~= nil
              if not extension then
                add(index.Subtypes, seen, {
                  label = short_name(node.name),
                  uri = node.uri,
                  range = node.selectionRange or node.range,
                })
              end
            end
          end
          finish('Subtypes')
        end)
      end)
    end

    request('textDocument/implementation', position(), function(batches)
      for _, batch in ipairs(batches) do
        for _, location in ipairs(batch) do
          local uri = location.uri or location.targetUri
          local range = location.range or location.targetSelectionRange
          if uri and range then
            add(index['Overrides & Implementations'] or index.Implementations, seen, {
              label = declaration_label(line_text(uri, range.start.line)),
              uri = uri,
              range = range,
            })
          end
        end
      end
      finish('Overrides & Implementations')
      finish('Implementations')
    end)

    local params = position()
    params.context = { includeDeclaration = false }
    request('textDocument/references', params, function(batches)
      local count = 0
      for _, batch in ipairs(batches) do
        for _, location in ipairs(batch) do
          if count < 100 then
            count = count + 1
            local text = util.trim(line_text(location.uri, location.range.start.line))
            add(index.References, seen, {
              label = util.fit(text, 64),
              uri = location.uri,
              range = location.range,
            })
          end
        end
      end
      finish('References')
    end)

    if opts.on_title then
      opts.on_title(title)
    end
  end)
end

local function close()
  if state.closed then
    return
  end
  state.closed = true
  if state.retry_timer then
    pcall(function()
      state.retry_timer:stop()
    end)
    state.retry_timer = nil
  end
  if state.win and api.nvim_win_is_valid(state.win) then
    pcall(api.nvim_win_close, state.win, true)
  end
end

local function render()
  if state.closed or not api.nvim_buf_is_valid(state.buf) then
    return
  end
  local available = math.max(20, vim.o.columns - 5)
  local width = util.clamp(math.floor(vim.o.columns * 0.72), math.min(40, available), available)
  local lines, rowmap, marks = {}, {}, {}
  lines[1] = '  ' .. (state.title or 'Related')
  marks[1] = { { 2, #lines[1], 'SwiftNavSection' } }
  if index.busy() then
    lines[1] = lines[1] .. '  ·  indexing, results refresh automatically'
    marks[1] = { { 2, #lines[1], 'SwiftNavStatus' } }
  end

  local pending = false
  for _, section_table in ipairs(state.sections) do
    local visible = not section_table.done or #section_table.items > 0
    if visible then
      pending = pending or not section_table.done
      lines[#lines + 1] = ''
      local header = section_table.done
          and string.format('  %s (%d)', section_table.name, #section_table.items)
        or string.format('  %s …', section_table.name)
      lines[#lines + 1] = header
      marks[#lines] = { { 0, #header, 'SwiftNavSection' } }
      for _, entry in ipairs(section_table.items) do
        local path = entry.uri and util.basename(vim.uri_to_fname(entry.uri)) or '?'
        local location = string.format('%s:%d', path, entry.range and (entry.range.start.line + 1) or 1)
        local text = '    ' .. entry.label
        local room = width - vim.fn.strdisplaywidth(location) - 2
        if vim.fn.strdisplaywidth(text) > room then
          text = util.fit(text, math.max(0, room))
        end
        local row = text .. string.rep(' ', math.max(1, room - vim.fn.strdisplaywidth(text))) .. location
        lines[#lines + 1] = row
        rowmap[#lines] = entry
        marks[#lines] = {
          { 0, #('    ' .. entry.label), 'SwiftNavName' },
          { #row - #location, #row, 'SwiftNavPath' },
        }
      end
    end
  end
  if #lines == 1 and not pending then
    lines[#lines + 1] = ''
    lines[#lines + 1] = '  Nothing related at the cursor.'
  end

  api.nvim_set_option_value('modifiable', true, { buf = state.buf })
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  api.nvim_set_option_value('modifiable', false, { buf = state.buf })
  api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
  for row, row_marks in pairs(marks) do
    for _, mark in ipairs(row_marks) do
      local finish = math.min(mark[2], #lines[row])
      if finish > mark[1] then
        api.nvim_buf_set_extmark(state.buf, namespace, row - 1, mark[1], {
          end_col = finish,
          hl_group = mark[3],
        })
      end
    end
  end
  state.rowmap = rowmap
  if api.nvim_win_get_cursor(state.win)[1] > #lines then
    api.nvim_win_set_cursor(state.win, { math.max(1, #lines), 0 })
  end

  local desired = util.clamp(#lines + 1, 8, math.floor(vim.o.lines * 0.8))
  if desired ~= state.height and api.nvim_win_is_valid(state.win) then
    state.height = desired
    local config = api.nvim_win_get_config(state.win)
    api.nvim_win_set_config(state.win, {
      relative = 'editor',
      width = config.width,
      height = desired,
      row = math.max(0, math.floor((vim.o.lines - desired) / 2)),
      col = config.col,
    })
  end
end

local function jump(action)
  local row = api.nvim_win_get_cursor(state.win)[1]
  local entry = state.rowmap[row]
  if not entry then
    return
  end
  close()
  if action == 'split' then
    vim.cmd('split ' .. vim.fn.fnameescape(vim.uri_to_fname(entry.uri)))
  end
  vim.lsp.util.show_document({ uri = entry.uri, range = entry.range }, 'utf-16', { focus = true })
end

local function load(attempt)
  attempt = attempt or 0
  state.sections, state.rowmap = {}, {}
  M.collect({
    bufnr = state.bufnr,
    line = state.line,
    character = state.character,
    on_title = function(title)
      state.title = title
      render()
    end,
    on_update = function(sections)
      state.sections = sections
      render()
      local done, total = true, 0
      for _, section_table in ipairs(sections) do
        if not section_table.done then
          done = false
        end
        total = total + #section_table.items
      end
      if done and total == 0 and attempt < 2 and not state.retry_timer then
        state.retry_timer = vim.defer_fn(function()
          state.retry_timer = nil
          if not state.closed then
            load(attempt + 1)
          end
        end, attempt == 0 and 1200 or 4000)
      end
    end,
  })
end

local function count_entries()
  local total = 0
  for _, section_table in ipairs(state.sections) do
    total = total + #section_table.items
  end
  return total
end

--- Open the Related Items popup for the symbol under the cursor.
function M.open()
  close()
  local win = api.nvim_get_current_win()
  local bufnr = api.nvim_get_current_buf()
  local cursor = api.nvim_win_get_cursor(win)
  local available = math.max(20, vim.o.columns - 5)
  local width = util.clamp(math.floor(vim.o.columns * 0.72), math.min(40, available), available)
  local vertical = math.max(6, vim.o.lines - 5)
  local height = util.clamp(math.floor(vim.o.lines * 0.6), math.min(10, vertical), vertical)

  state = {
    closed = false,
    bufnr = bufnr,
    line = cursor[1] - 1,
    character = cursor[2],
    sections = {},
    rowmap = {},
    height = height,
    title = 'Related',
    reloads = 0,
    retry_timer = nil,
  }

  state.buf = api.nvim_create_buf(false, true)
  state.win = api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = 'minimal',
    border = 'rounded',
    title = ' Related ',
    title_pos = 'center',
    footer = ' <CR> jump   o split   r refresh   q close ',
    footer_pos = 'center',
  })
  vim.bo[state.buf].buftype = 'nofile'
  vim.bo[state.buf].bufhidden = 'wipe'
  vim.bo[state.buf].filetype = 'swiftnav_related'
  vim.bo[state.buf].modifiable = false
  api.nvim_set_option_value('wrap', false, { win = state.win })
  api.nvim_set_option_value('cursorline', true, { win = state.win })
  api.nvim_set_option_value('winhl', 'Normal:NormalFloat,FloatBorder:FloatBorder', { win = state.win })

  vim.keymap.set('n', '<CR>', function()
    jump('edit')
  end, { buffer = state.buf, desc = 'swiftnav: jump to related item' })
  vim.keymap.set('n', 'o', function()
    jump('split')
  end, { buffer = state.buf, desc = 'swiftnav: open related item in split' })
  vim.keymap.set('n', 'r', load, { buffer = state.buf, desc = 'swiftnav: refresh related items' })
  vim.keymap.set('n', 'q', close, { buffer = state.buf, desc = 'swiftnav: close related items' })
  vim.keymap.set('n', '<Esc>', close, { buffer = state.buf, desc = 'swiftnav: close related items' })

  local group = api.nvim_create_augroup('SwiftNavRelated', { clear = true })
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'SwiftNavIndexReady',
    callback = function()
      if state.closed or state.reloads >= 2 then
        return
      end
      if count_entries() == 0 then
        state.reloads = state.reloads + 1
        load()
      end
    end,
  })

  render()
  load()
end

M.close = close

return M
