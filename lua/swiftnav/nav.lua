local api = vim.api
local indexer = require('swiftnav.indexer')
local open = require('swiftnav.open')
local util = require('swiftnav.util')
local ui = require('swiftnav.ui')

local M = {}

local MAX_REFERENCES = 500
local build_settings = {}

local function has_build_settings(bufnr)
  local name = api.nvim_buf_get_name(bufnr)
  if name == '' then
    return true
  end
  local dir = vim.fs.dirname(name)
  local cached = build_settings[dir]
  if cached and os.time() - cached.at < 60 then
    return cached.value
  end
  local git = vim.fs.find('.git', { path = dir, upward = true })[1]
  local root = git and vim.fs.dirname(git) or dir
  local function inside(path)
    return vim.startswith(vim.fs.dirname(path), root)
  end
  local found = false
  for _, marker in ipairs({ 'buildServer.json', 'compile_commands.json', '.bsp' }) do
    local hit = vim.fs.find(marker, { path = dir, upward = true })[1]
    if hit and inside(hit) then
      found = true
      break
    end
  end
  if not found then
    local package = vim.fs.find('Package.swift', { path = dir, upward = true })[1]
    if package and inside(package) then
      found = true
    end
  end
  build_settings[dir] = { value = found, at = os.time() }
  return found
end

function M.reset_build_settings()
  build_settings = {}
end

local function line_at(path, lnum)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
    return api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  end
  local lines = util.read_lines(path, lnum)
  return lines and lines[lnum] or ''
end

local function short_location(path, lnum)
  local name = util.basename(path)
  local stem = name:gsub('%.swift$', '')
  if #stem > 22 then
    stem = stem:sub(1, 12) .. '…' .. stem:sub(-7)
  end
  return string.format('%s.swift:%d', stem, lnum)
end

local function reference_format(item, width)
  local location = short_location(item.path, item.lnum)
  local left = item.label or item.name or ''
  local room = width - vim.fn.strdisplaywidth(location) - 1
  if vim.fn.strdisplaywidth(left) > room then
    left = util.fit(left, math.max(0, room))
  end
  local text = left .. string.rep(' ', math.max(1, width - vim.fn.strdisplaywidth(left) - #location)) .. location
  local marks = {}
  if #left > 0 then
    marks[1] = { 0, #left, item.label and 'SwiftNavName' or 'SwiftNavPath' }
  end
  marks[#marks + 1] = { #text - #location, #text, 'SwiftNavPath' }
  return text, marks
end

local function jump(item, action)
  local lnum = item.lnum or 1
  local character = item.col or 0
  open.jump({
    name = item.name,
    path = item.path,
    lnum = lnum,
    encoding = item.encoding or 'utf-8',
    range = item.range or {
      start = { line = lnum - 1, character = character },
      ['end'] = { line = lnum - 1, character = character + #(item.name or '') },
    },
  }, action)
end

local function present(items, title, prefill, options)
  options = options or {}
  if #items == 0 then
    return
  end
  if #items == 1 then
    jump(items[1], 'edit')
    return
  end
  if items[1].points and items[2].points and items[1].points - items[2].points >= 150 then
    jump(items[1], 'edit')
    return
  end
  local preview = open.preview
  if options.preview == false then
    preview = nil
  end
  ui.open({
    title = title,
    list_title = prefill or 'Swift',
    items = items,
    prefill = prefill,
    preview_item = preview,
    format = reference_format,
    on_accept = function(item, action)
      jump(item, action)
    end,
  })
end

local function lsp_locations(bufnr, method, params, on_done)
  local supported = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client:supports_method(method, bufnr) then
      supported = true
      break
    end
  end
  if not supported then
    return false
  end
  local cancel = vim.lsp.buf_request_all(bufnr, method, params or vim.lsp.util.make_position_params(0, 'utf-16'), function(results)
    local locations = {}
    for _, entry in pairs(results or {}) do
      local encoding = 'utf-16'
      if entry.context and entry.context.client then
        encoding = entry.context.client.offset_encoding
      end
      local result = entry.result
      if result then
        if result.uri then
          locations[#locations + 1] = { uri = result.uri, range = result.range, encoding = encoding }
        else
          for _, location in ipairs(result) do
            local uri = location.uri or location.targetUri
            local range = location.range or location.targetSelectionRange or location.targetRange
            if uri and range then
              locations[#locations + 1] = { uri = uri, range = range, encoding = encoding }
            end
          end
        end
      end
    end
    vim.schedule(function()
      on_done(locations)
    end)
  end)
  return cancel ~= nil
end

local function location_items(locations)
  local items = {}
  for _, location in ipairs(locations) do
    local path = vim.uri_to_fname(location.uri)
    local lnum = location.range.start.line + 1
    items[#items + 1] = {
      name = util.trim(line_at(path, lnum)),
      label = util.trim(line_at(path, lnum)),
      kind = 'File',
      path = path,
      lnum = lnum,
      range = location.range,
      encoding = location.encoding,
    }
  end
  return items
end

local function show_locations(locations, title, prefill)
  present(location_items(locations), title, prefill)
end

local function word_under_cursor()
  return vim.fn.expand('<cword>')
end

local function self_only(locations, bufnr)
  local path = api.nvim_buf_get_name(bufnr)
  local cursor = api.nvim_win_get_cursor(0)
  for _, location in ipairs(locations) do
    if vim.uri_to_fname(location.uri) ~= path or location.range.start.line + 1 ~= cursor[1] then
      return false
    end
  end
  return #locations > 0
end

local function fallback_definition(bufnr)
  local word = word_under_cursor()
  if word == '' then
    return
  end
  indexer.ensure(bufnr, function()
    local candidates = indexer.definition_candidates(word, bufnr)
    if #candidates == 0 then
      util.notify('no Swift definition for ' .. word, vim.log.levels.WARN)
      return
    end
    present(candidates, 'Definition', word)
  end, true)
end

--- Go to definition, preferring sourcekit-lsp and falling back to the index.
function M.definition()
  local bufnr = api.nvim_get_current_buf()
  if has_build_settings(bufnr) then
    local handled = lsp_locations(bufnr, 'textDocument/definition', nil, function(locations)
      if #locations > 0 and not self_only(locations, bufnr) then
        show_locations(locations, 'Definition', word_under_cursor())
      else
        fallback_definition(bufnr)
      end
    end)
    if handled then
      return
    end
  end
  fallback_definition(bufnr)
end

M.declaration = M.definition

local TYPE_KINDS = {
  Class = true,
  Struct = true,
  Enum = true,
  Protocol = true,
  Actor = true,
  TypeAlias = true,
}

local function fallback_type_definition(bufnr, word)
  indexer.ensure(bufnr, function()
    local candidates = {}
    for _, candidate in ipairs(indexer.definition_candidates(word, bufnr)) do
      if TYPE_KINDS[candidate.kind] then
        candidates[#candidates + 1] = candidate
      end
    end
    if #candidates == 0 then
      util.notify('no type definition for ' .. word, vim.log.levels.WARN)
      return
    end
    present(candidates, 'Type definition', word)
  end, true)
end

local function fallback_implementation(bufnr, word)
  indexer.ensure(bufnr, function()
    local candidates = {}
    for _, candidate in ipairs(indexer.definition_candidates(word, bufnr)) do
      if candidate.kind == 'Function' then
        candidates[#candidates + 1] = candidate
      end
    end
    if #candidates == 0 then
      util.notify('no implementations for ' .. word, vim.log.levels.WARN)
      return
    end
    present(candidates, 'Implementations', word)
  end, true)
end

--- Go to the type of the symbol.
function M.type_definition()
  local bufnr = api.nvim_get_current_buf()
  local word = word_under_cursor()
  if has_build_settings(bufnr) then
    local handled = lsp_locations(bufnr, 'textDocument/typeDefinition', nil, function(locations)
      if #locations > 0 then
        show_locations(locations, 'Type definition', word)
      else
        fallback_type_definition(bufnr, word)
      end
    end)
    if handled then
      return
    end
  end
  fallback_type_definition(bufnr, word)
end

--- Find implementations or overrides.
function M.implementation()
  local bufnr = api.nvim_get_current_buf()
  local word = word_under_cursor()
  if has_build_settings(bufnr) then
    local handled = lsp_locations(bufnr, 'textDocument/implementation', nil, function(locations)
      if #locations > 0 then
        show_locations(locations, 'Implementations', word)
      else
        fallback_implementation(bufnr, word)
      end
    end)
    if handled then
      return
    end
  end
  fallback_implementation(bufnr, word)
end

local function fallback_references(bufnr, word, on_done)
  local root = indexer.root(bufnr)
  local command = {
    'rg',
    '--line-number',
    '--no-heading',
    '--with-filename',
    '--color',
    'never',
    '--word-regexp',
    '--fixed-strings',
    word,
    '--glob',
    '*.swift',
    '--glob',
    '!**/.build/**',
    '--glob',
    '!**/DerivedData/**',
    '--glob',
    '!**/Pods/**',
  }
  vim.system(command, { cwd = root, text = true }, function(object)
    vim.schedule(function()
      local items = {}
      for line in (object.stdout or ''):gmatch('[^\n]+') do
        local path, lnum, text = line:match('^(.-):(%d+):(.*)$')
        if path then
          local absolute = path:sub(1, 1) == '/' and path or (root .. '/' .. path)
          local col = text:find(word, 1, true)
          items[#items + 1] = {
            name = word,
            label = util.trim(text),
            kind = 'File',
            path = absolute,
            lnum = tonumber(lnum),
            col = (col or 1) - 1,
            encoding = 'utf-8',
          }
          if #items >= MAX_REFERENCES then
            break
          end
        end
      end
      on_done(items)
    end)
  end)
end

local function fallback_hover(bufnr)
  local word = word_under_cursor()
  if word == '' then
    return
  end
  indexer.ensure(bufnr, function()
    local candidates = indexer.definition_candidates(word, bufnr)
    if #candidates == 0 then
      return
    end
    local entry = candidates[1]
    local line = util.trim(line_at(entry.path, entry.lnum))
    local location = string.format('%s:%d', util.relpath(entry.path), entry.lnum)
    local lines = { line, '', location }
    vim.lsp.util.open_floating_preview(lines, 'swift', { border = 'rounded', title = word })
  end, false)
end

--- Hover with a declaration fallback when the language server has no answer.
function M.hover()
  local bufnr = api.nvim_get_current_buf()
  if not has_build_settings(bufnr) then
    fallback_hover(bufnr)
    return
  end
  local supported = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client:supports_method('textDocument/hover', bufnr) then
      supported = true
      break
    end
  end
  if not supported then
    fallback_hover(bufnr)
    return
  end
  vim.lsp.buf_request_all(bufnr, 'textDocument/hover', vim.lsp.util.make_position_params(0, 'utf-16'), function(results)
    local shown = false
    for _, entry in pairs(results or {}) do
      local result = entry.result
      local contents = result and result.contents
      if contents and (type(contents) == 'string' or (type(contents) == 'table' and not vim.tbl_isempty(contents))) then
        vim.schedule(function()
          vim.lsp.handlers['textDocument/hover'](nil, result, {
            bufnr = bufnr,
            client_id = entry.context and entry.context.client_id,
            method = 'textDocument/hover',
          }, { border = 'rounded' })
        end)
        shown = true
        break
      end
    end
    if not shown then
      vim.schedule(function()
        fallback_hover(bufnr)
      end)
    end
  end)
end

--- References with sourcekit-lsp when indexed, else a project-wide search.
function M.references()
  local bufnr = api.nvim_get_current_buf()
  local word = word_under_cursor()
  if word == '' then
    return
  end
  local function search()
    fallback_references(bufnr, word, function(items)
      if #items == 0 then
        util.notify('no references to ' .. word, vim.log.levels.WARN)
        return
      end
      present(items, 'References', word, { preview = false })
    end)
  end
  if has_build_settings(bufnr) then
    local params = vim.lsp.util.make_position_params(0, 'utf-16')
    params.context = { includeDeclaration = false }
    local handled = lsp_locations(bufnr, 'textDocument/references', params, function(locations)
      if #locations > 0 then
        show_locations(locations, 'References', word)
      else
        search()
      end
    end)
    if handled then
      return
    end
  end
  search()
end

return M
